/**
 * AfterMath Backend — Disaster reporting routes.
 *
 * POST   /disaster/report      — Submit a photo-verified disaster report
 * GET    /disaster/feed         — Paginated verified report feed
 * GET    /disaster/:id          — Single report detail
 * PATCH  /disaster/:id/status   — Authority status update (admin only)
 * GET    /disaster/stats        — Aggregated statistics
 * GET    /disaster/heatmap      — Geo-clustered points for heatmap
 */

import { Router, type Request, type Response } from 'express';
import crypto from 'node:crypto';
import multer from 'multer';
import type { Pool } from 'pg';

import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { DisasterReportRepository } from '../db/disaster-report-repository.js';
import { verifyDisasterImage } from '../services/gemini-verify.js';
import {
  hashImage,
  storeImage,
  validateImageMagic,
} from '../services/image-store.js';
import {
  disasterReportBodySchema,
  disasterFeedQuerySchema,
  authorityStatusUpdateSchema,
  heatmapQuerySchema,
  statsQuerySchema,
  type DisasterCategory,
} from '../models/disaster-report.js';
import { env } from '../config.js';
import { logger } from '../logger.js';

// Multer: in-memory storage, 5 MB max, single file field "image"
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: env.DISASTER_IMAGE_MAX_BYTES },
});

const rid = (req: Request): string =>
  (req as Request & { reqId?: string }).reqId ?? 'no-rid';

const pickFirstString = (value: string | string[] | undefined): string | null => {
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return value[0] ?? null;
  return null;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function createDisasterRouter(pool: Pool): Router {
  const router = Router();
  const repo = new DisasterReportRepository(pool);

  // -----------------------------------------------------------------------
  // POST /disaster/report
  // -----------------------------------------------------------------------
  router.post(
    '/report',
    requireAuth,
    upload.single('image'),
    async (req: Request, res: Response) => {
      const reqId = rid(req);
      try {
        const userId = req.user!.sub;

        // --- Validate image presence ---
        if (!req.file) {
          res.status(400).json({ error: 'Image file is required (field: "image")' });
          return;
        }

        // --- Validate image magic bytes ---
        const detectedMime = validateImageMagic(req.file.buffer);
        if (!detectedMime) {
          res.status(400).json({
            error: 'Invalid image format. Only JPEG, PNG, and WebP are accepted.',
          });
          return;
        }

        // --- Validate body fields ---
        const bodyParsed = disasterReportBodySchema.safeParse(req.body);
        if (!bodyParsed.success) {
          res.status(400).json({
            error: 'Invalid report payload',
            details: bodyParsed.error.flatten().fieldErrors,
          });
          return;
        }

        const { lat, lon, description } = bodyParsed.data;

        // --- Per-user rate limit ---
        const recentCount = await repo.countRecentByUser(userId);
        if (recentCount >= env.DISASTER_REPORT_RATE_LIMIT) {
          logger.warn(`Rate limit hit: user ${userId} has ${recentCount} reports in last hour`, { reqId });
          res.status(429).json({
            error: 'Too many reports. Max 5 per hour.',
            retryAfterSeconds: 3600,
          });
          return;
        }

        // --- Image hash dedup ---
        const imgHash = hashImage(req.file.buffer);
        const isDuplicate = await repo.findRecentByHash(imgHash);
        if (isDuplicate) {
          logger.warn(`Duplicate image hash detected: ${imgHash.slice(0, 16)}…`, { reqId });
          res.status(409).json({ error: 'This image was already submitted recently.' });
          return;
        }

        // --- Store image ---
        const reportId = crypto.randomUUID();
        const imageUrl = await storeImage(req.file.buffer, userId, reportId, detectedMime);

        // --- LLM verification ---
        const geminiResult = await verifyDisasterImage(
          req.file.buffer,
          detectedMime,
          lat,
          lon,
          description,
        );

        let verificationStatus: 'verified' | 'rejected' | 'flagged' | 'pending';
        let rejectionReason: string | null = null;
        let category: DisasterCategory = 'other';
        let severityScore = 3;
        let llmConfidence = 0;

        if (!geminiResult) {
          // Gemini unavailable — manual review needed
          verificationStatus = 'pending';
        } else if (!geminiResult.isReal) {
          verificationStatus = 'rejected';
          rejectionReason = geminiResult.reasoning;
          category = geminiResult.category;
          severityScore = geminiResult.severity;
          llmConfidence = geminiResult.confidence;
        } else if (geminiResult.flags.length > 0) {
          // Real but flagged for review
          verificationStatus = 'flagged';
          category = geminiResult.category;
          severityScore = geminiResult.severity;
          llmConfidence = geminiResult.confidence;
        } else {
          verificationStatus = 'verified';
          category = geminiResult.category;
          severityScore = geminiResult.severity;
          llmConfidence = geminiResult.confidence;
        }

        // --- Persist ---
        const report = await repo.create({
          id: reportId,
          userId,
          lat,
          lon,
          imageUrl,
          imageHash: imgHash,
          category,
          severityScore,
          llmConfidence,
          llmRawResponse: geminiResult as Record<string, unknown> | null,
          verificationStatus,
          rejectionReason,
          description: description ?? null,
          linkedSosId: null,
        });

        logger.info(
          `Disaster report ${reportId}: status=${verificationStatus} cat=${category} sev=${severityScore}`,
          { reqId },
        );

        const statusCode = verificationStatus === 'rejected' ? 200 : 201;
        res.status(statusCode).json({
          report: {
            id: report.id,
            verificationStatus: report.verificationStatus,
            category: report.category,
            severityScore: report.severityScore,
            llmConfidence: report.llmConfidence,
            rejectionReason: report.rejectionReason,
            imageUrl: report.imageUrl,
            createdAt: report.createdAt,
          },
        });
      } catch (err) {
        logger.error(`Disaster report submission failed: ${(err as Error).message}`, { reqId });
        res.status(500).json({ error: 'Failed to process disaster report' });
      }
    },
  );

  // -----------------------------------------------------------------------
  // GET /disaster/feed
  // -----------------------------------------------------------------------
  router.get('/feed', optionalAuth, async (req: Request, res: Response) => {
    try {
      const parsed = disasterFeedQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid query parameters',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const q = parsed.data;
      const { reports, total } = await repo.findFeed({
        category: q.category,
        severityMin: q.severity_min,
        since: q.since,
        neLat: q.ne_lat,
        neLon: q.ne_lon,
        swLat: q.sw_lat,
        swLon: q.sw_lon,
        page: q.page,
        limit: q.limit,
      });

      res.json({
        reports,
        total,
        page: q.page,
        limit: q.limit,
        totalPages: Math.ceil(total / q.limit),
      });
    } catch (err) {
      logger.error(`Feed query failed: ${(err as Error).message}`);
      res.status(500).json({ error: 'Failed to fetch feed' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /disaster/stats
  // -----------------------------------------------------------------------
  router.get('/stats', optionalAuth, async (req: Request, res: Response) => {
    try {
      const parsed = statsQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        res.status(400).json({ error: 'Invalid query', details: parsed.error.flatten().fieldErrors });
        return;
      }
      const stats = await repo.stats(parsed.data.range);
      res.json(stats);
    } catch (err) {
      logger.error(`Stats query failed: ${(err as Error).message}`);
      res.status(500).json({ error: 'Failed to fetch stats' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /disaster/heatmap
  // -----------------------------------------------------------------------
  router.get('/heatmap', optionalAuth, async (req: Request, res: Response) => {
    try {
      const parsed = heatmapQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        res.status(400).json({ error: 'Invalid query', details: parsed.error.flatten().fieldErrors });
        return;
      }
      const points = await repo.heatmap({
        precision: parsed.data.precision,
        since: parsed.data.since,
        category: parsed.data.category,
      });
      res.json({ points });
    } catch (err) {
      logger.error(`Heatmap query failed: ${(err as Error).message}`);
      res.status(500).json({ error: 'Failed to fetch heatmap' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /disaster/:id
  // -----------------------------------------------------------------------
  router.get('/:id', optionalAuth, async (req: Request, res: Response) => {
    try {
      const id = pickFirstString(req.params.id);
      if (!id || !UUID_RE.test(id)) {
        res.status(404).json({ error: 'Report not found' });
        return;
      }
      const report = await repo.findById(id);
      if (!report) {
        res.status(404).json({ error: 'Report not found' });
        return;
      }
      res.json({ report });
    } catch (err) {
      logger.error(`Report fetch failed: ${(err as Error).message}`);
      res.status(500).json({ error: 'Failed to fetch report' });
    }
  });

  // -----------------------------------------------------------------------
  // PATCH /disaster/:id/status
  // -----------------------------------------------------------------------
  router.patch('/:id/status', requireAuth, async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const id = pickFirstString(req.params.id);
      if (!id || !UUID_RE.test(id)) {
        res.status(404).json({ error: 'Report not found' });
        return;
      }

      // Only admins can update authority status
      if (req.user!.role !== 'admin') {
        res.status(403).json({ error: 'Admin access required' });
        return;
      }

      const parsed = authorityStatusUpdateSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid status update',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const report = await repo.updateAuthorityStatus(id, parsed.data.authority_status);
      if (!report) {
        res.status(404).json({ error: 'Report not found' });
        return;
      }

      logger.info(
        `Report ${id} authority_status → ${parsed.data.authority_status} by ${req.user!.sub}`,
        { reqId },
      );

      res.json({ report });
    } catch (err) {
      logger.error(`Status update failed: ${(err as Error).message}`, { reqId });
      res.status(500).json({ error: 'Failed to update status' });
    }
  });

  return router;
}
