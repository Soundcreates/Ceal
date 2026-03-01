/**
 * CEAL Backend — Admin dashboard routes.
 *
 * GET  /admin/stats              — Aggregate dashboard statistics
 * GET  /admin/events             — All SOS events (paginated + filterable)
 * GET  /admin/events/:id         — Single event detail with victim profile
 * PATCH /admin/events/:id/status — Update event status
 * GET  /admin/users              — All registered users (paginated)
 * GET  /admin/users/:id          — Full user profile (contacts + medical)
 */

import { Router, type Request, type Response } from 'express';
import type { Pool } from 'pg';
import { SosRepository } from '../db/sos-repository.js';
import { UserRepository } from '../db/user-repository.js';
import { DisasterReportRepository } from '../db/disaster-report-repository.js';
import { extractSosType, SOS_STATUSES } from '../models/sos-event.js';
import { AUTHORITY_STATUSES, VERIFICATION_STATUSES } from '../models/disaster-report.js';
import { logger } from '../logger.js';

const rid = (req: Request): string =>
  (req as Request & { reqId?: string }).reqId ?? 'no-rid';

export function createAdminRouter(pool: Pool): Router {
  const router = Router();
  const sosRepo = new SosRepository(pool);
  const userRepo = new UserRepository(pool);
  const disasterRepo = new DisasterReportRepository(pool);

  // -----------------------------------------------------------------------
  // GET /admin/stats
  // -----------------------------------------------------------------------
  router.get('/stats', async (_req: Request, res: Response) => {
    try {
      const [eventsRow, usersRow, activeRow, todayRow, kycRow] = await Promise.all([
        pool.query('SELECT COUNT(*)::int AS count FROM sos_events'),
        pool.query('SELECT COUNT(*)::int AS count FROM users'),
        pool.query(
          `SELECT COUNT(*)::int AS count FROM sos_events WHERE status IN ('active', 'relayed')`,
        ),
        pool.query(
          `SELECT COUNT(*)::int AS count FROM sos_events WHERE created_at >= CURRENT_DATE`,
        ),
        pool.query(
          `SELECT
             (COUNT(*) FILTER (WHERE kyc_status = 'verified'))::int AS verified,
             (COUNT(*) FILTER (WHERE kyc_status = 'pending'))::int  AS pending,
             (COUNT(*) FILTER (WHERE kyc_status = 'rejected'))::int AS rejected
           FROM users`,
        ),
      ]);

      // Status breakdown
      const statusBreakdown = await pool.query(
        `SELECT status, COUNT(*)::int AS count FROM sos_events GROUP BY status`,
      );

      // SOS type breakdown
      const typeBreakdown = await pool.query(
        `SELECT flags, COUNT(*)::int AS count FROM sos_events GROUP BY flags`,
      );
      const typeMap: Record<string, number> = {};
      for (const row of typeBreakdown.rows) {
        const label = extractSosType(row.flags);
        typeMap[label] = (typeMap[label] ?? 0) + row.count;
      }

      // Events per day (last 7 days)
      const dailyEvents = await pool.query(
        `SELECT DATE(created_at) AS day, COUNT(*)::int AS count
         FROM sos_events
         WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
         GROUP BY DATE(created_at)
         ORDER BY day`,
      );

      // Recent activity (last 10 events)
      const recentEvents = await pool.query(
        `SELECT * FROM sos_events ORDER BY created_at DESC LIMIT 10`,
      );

      // Disaster report stats
      const [disasterTotal, disasterToday, disasterVerification] = await Promise.all([
        pool.query('SELECT COUNT(*)::int AS count FROM disaster_reports'),
        pool.query(
          `SELECT COUNT(*)::int AS count FROM disaster_reports WHERE created_at >= CURRENT_DATE`,
        ),
        pool.query(
          `SELECT
             COUNT(*)::int AS total,
             COUNT(*) FILTER (WHERE verification_status = 'verified')::int AS verified,
             COUNT(*) FILTER (WHERE verification_status = 'pending')::int AS pending,
             COUNT(*) FILTER (WHERE verification_status = 'rejected')::int AS rejected,
             COUNT(*) FILTER (WHERE verification_status = 'flagged')::int AS flagged
           FROM disaster_reports`,
        ),
      ]);

      // Recent disaster reports (last 5)
      const recentDisasterReports = await pool.query(
        `SELECT * FROM disaster_reports ORDER BY created_at DESC LIMIT 5`,
      );

      res.json({
        totalEvents: eventsRow.rows[0].count,
        totalUsers: usersRow.rows[0].count,
        activeEvents: activeRow.rows[0].count,
        eventsToday: todayRow.rows[0].count,
        kyc: kycRow.rows[0],
        statusBreakdown: Object.fromEntries(
          statusBreakdown.rows.map((r) => [r.status, r.count]),
        ),
        typeBreakdown: typeMap,
        dailyEvents: dailyEvents.rows,
        recentEvents: recentEvents.rows.map((r) => ({
          ...sosRepo['rowToEvent'](r),
          sosType: extractSosType(r.flags ?? 0),
        })),
        disasterReports: {
          total: disasterTotal.rows[0].count,
          today: disasterToday.rows[0].count,
          verification: disasterVerification.rows[0],
        },
        recentDisasterReports: recentDisasterReports.rows.map((r) =>
          disasterRepo['rowToReport'](r),
        ),
      });
    } catch (err) {
      logger.error('Admin stats error', { message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /admin/events
  // -----------------------------------------------------------------------
  router.get('/events', async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
      const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));
      const offset = (page - 1) * limit;
      const status = req.query.status ? String(req.query.status) : null;

      let where = '';
      const params: unknown[] = [];
      if (status && SOS_STATUSES.includes(status as any)) {
        where = 'WHERE status = $1';
        params.push(status);
      }

      const countQ = await pool.query(
        `SELECT COUNT(*)::int AS total FROM sos_events ${where}`,
        params,
      );
      const total = countQ.rows[0].total;

      const dataQ = await pool.query(
        `SELECT * FROM sos_events ${where}
         ORDER BY created_at DESC
         LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        [...params, limit, offset],
      );

      const events = dataQ.rows.map((r) => ({
        ...sosRepo['rowToEvent'](r),
        sosType: extractSosType(r.flags ?? 0),
        createdAt: r.created_at instanceof Date ? r.created_at.toISOString() : r.created_at,
        updatedAt: r.updated_at instanceof Date ? r.updated_at.toISOString() : r.updated_at,
      }));

      res.json({ events, total, page, limit, pages: Math.ceil(total / limit) });
    } catch (err) {
      logger.error('Admin events list error', { reqId, message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /admin/events/:id
  // -----------------------------------------------------------------------
  router.get('/events/:id', async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const event = await sosRepo.findById(String(req.params.id));
      if (!event) {
        res.status(404).json({ error: 'Event not found' });
        return;
      }

      // Enrich with victim profile
      let victimProfile = null;
      if (event.bleUid) {
        const profile = await userRepo.findFullProfileByBleUid(
          event.bleUid.toLowerCase(),
        );
        if (profile) {
          victimProfile = {
            user: {
              id: profile.user.id,
              name: profile.user.name,
              phone: profile.user.phone,
              role: profile.user.role,
              kycStatus: profile.user.kycStatus,
            },
            contacts: profile.contacts,
            medical: profile.medical,
          };
        }
      }

      res.json({
        ...event,
        sosType: extractSosType(event.flags ?? 0),
        victimProfile,
      });
    } catch (err) {
      logger.error('Admin event detail error', { reqId, message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // PATCH /admin/events/:id/status
  // -----------------------------------------------------------------------
  router.patch('/events/:id/status', async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const { status } = req.body;
      if (!status || !SOS_STATUSES.includes(status)) {
        res.status(400).json({ error: `Invalid status. Must be one of: ${SOS_STATUSES.join(', ')}` });
        return;
      }
      const event = await sosRepo.updateStatus(String(req.params.id), status);
      if (!event) {
        res.status(404).json({ error: 'Event not found' });
        return;
      }
      logger.info('Admin updated event status', { reqId, id: event.id, status });
      res.json({ ...event, sosType: extractSosType(event.flags ?? 0) });
    } catch (err) {
      logger.error('Admin status update error', { reqId, message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /admin/users
  // -----------------------------------------------------------------------
  router.get('/users', async (req: Request, res: Response) => {
    try {
      const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
      const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));
      const offset = (page - 1) * limit;

      const countQ = await pool.query('SELECT COUNT(*)::int AS total FROM users');
      const total = countQ.rows[0].total;

      const dataQ = await pool.query(
        `SELECT * FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
        [limit, offset],
      );

      const users = dataQ.rows.map((row) => ({
        id: row.id,
        name: row.name ?? null,
        phone: row.phone,
        bleUid:
          row.ble_uid instanceof Buffer
            ? row.ble_uid.toString('hex')
            : typeof row.ble_uid === 'string'
              ? row.ble_uid
              : '',
        role: row.role,
        kycStatus: row.kyc_status,
        createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at,
      }));

      res.json({ users, total, page, limit, pages: Math.ceil(total / limit) });
    } catch (err) {
      logger.error('Admin users list error', { message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /admin/users/:id
  // -----------------------------------------------------------------------
  router.get('/users/:id', async (req: Request, res: Response) => {
    try {
      const user = await userRepo.findById(String(req.params.id));
      if (!user) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      // Get contacts + medical
      const contactsQ = await pool.query(
        'SELECT * FROM emergency_contacts WHERE user_id = $1 ORDER BY priority',
        [user.id],
      );
      const medicalQ = await pool.query(
        'SELECT * FROM medical_profiles WHERE user_id = $1',
        [user.id],
      );

      // Get user's SOS events
      const eventsQ = await pool.query(
        `SELECT * FROM sos_events WHERE ble_uid = $1 ORDER BY created_at DESC LIMIT 20`,
        [user.bleUid],
      );

      res.json({
        user,
        contacts: contactsQ.rows.map((c) => ({
          id: c.id,
          name: c.name,
          phone: c.phone,
          priority: c.priority,
        })),
        medical: medicalQ.rows[0]
          ? {
              bloodGroup: medicalQ.rows[0].blood_group,
              allergies: medicalQ.rows[0].allergies,
              conditions: medicalQ.rows[0].conditions,
            }
          : null,
        events: eventsQ.rows.map((r) => ({
          ...sosRepo['rowToEvent'](r),
          sosType: extractSosType(r.flags ?? 0),
        })),
      });
    } catch (err) {
      logger.error('Admin user detail error', { message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /admin/disaster-reports
  // -----------------------------------------------------------------------
  router.get('/disaster-reports', async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
      const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));
      const offset = (page - 1) * limit;
      const status = req.query.status ? String(req.query.status) : null;
      const category = req.query.category ? String(req.query.category) : null;

      const conditions: string[] = [];
      const params: unknown[] = [];
      let i = 1;

      if (status && (VERIFICATION_STATUSES as readonly string[]).includes(status)) {
        conditions.push(`verification_status = $${i++}`);
        params.push(status);
      }
      if (category) {
        conditions.push(`category = $${i++}`);
        params.push(category);
      }

      const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

      const countQ = await pool.query(
        `SELECT COUNT(*)::int AS total FROM disaster_reports ${where}`,
        params,
      );
      const total = countQ.rows[0].total;

      const dataQ = await pool.query(
        `SELECT dr.*, u.name AS reporter_name
         FROM disaster_reports dr
         LEFT JOIN users u ON u.id = dr.user_id
         ${where}
         ORDER BY dr.created_at DESC
         LIMIT $${i++} OFFSET $${i++}`,
        [...params, limit, offset],
      );

      const reports = dataQ.rows.map((r) => ({
        ...disasterRepo['rowToReport'](r),
        reporterName: r.reporter_name ?? null,
      }));

      res.json({ reports, total, page, limit, pages: Math.ceil(total / limit) });
    } catch (err) {
      logger.error('Admin disaster reports list error', { reqId, message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /admin/disaster-reports/:id
  // -----------------------------------------------------------------------
  router.get('/disaster-reports/:id', async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const report = await disasterRepo.findById(String(req.params.id));
      if (!report) {
        res.status(404).json({ error: 'Disaster report not found' });
        return;
      }

      // Get reporter info
      const userQ = await pool.query(
        'SELECT id, name, phone, role, kyc_status FROM users WHERE id = $1',
        [report.userId],
      );
      const reporter = userQ.rows[0]
        ? {
            id: userQ.rows[0].id,
            name: userQ.rows[0].name,
            phone: userQ.rows[0].phone,
            role: userQ.rows[0].role,
            kycStatus: userQ.rows[0].kyc_status,
          }
        : null;

      res.json({ ...report, reporter });
    } catch (err) {
      logger.error('Admin disaster report detail error', { reqId, message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // PATCH /admin/disaster-reports/:id/status
  // -----------------------------------------------------------------------
  router.patch('/disaster-reports/:id/status', async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const { authority_status } = req.body;
      if (!authority_status || !(AUTHORITY_STATUSES as readonly string[]).includes(authority_status)) {
        res.status(400).json({
          error: `Invalid authority_status. Must be one of: ${AUTHORITY_STATUSES.join(', ')}`,
        });
        return;
      }
      const report = await disasterRepo.updateAuthorityStatus(
        String(req.params.id),
        authority_status,
      );
      if (!report) {
        res.status(404).json({ error: 'Disaster report not found' });
        return;
      }
      logger.info('Admin updated disaster report status', {
        reqId,
        id: report.id,
        authorityStatus: authority_status,
      });
      res.json(report);
    } catch (err) {
      logger.error('Admin disaster status update error', { reqId, message: (err as Error).message });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  return router;
}
