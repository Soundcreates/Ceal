/**
 * CEAL Backend — User onboarding routes.
 *
 * POST /users              — Create a new user (generates static BLE UID)
 * GET  /users/:id          — Fetch user profile (no raw ble_uid)
 * POST /users/:id/contacts — Add emergency contacts
 * POST /users/:id/medical  — Set medical profile
 */

import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import crypto from 'node:crypto';
import { requireAuth } from '../middleware/auth.js';
import { getFullUserProfile, getEmergencyContacts, getMedicalProfile } from '../services/user-profile.js';
import { rowToUser, generateBleUid } from '../services/uid-resolver.js';
import { logger } from '../logger.js';
import type { Pool } from 'pg';

// ---------------------------------------------------------------------------
// Zod schemas
// ---------------------------------------------------------------------------

const createUserSchema = z.object({
  name: z.string().min(1).max(200).optional(),
  phone: z.string().min(5).max(20),
  language: z.string().max(10).default('en'),
});

const addContactSchema = z.object({
  name: z.string().max(200).optional(),
  phone: z.string().min(5).max(20),
  priority: z.number().int().min(1).max(10).default(1),
});

const addContactsSchema = z.union([
  addContactSchema,
  z.array(addContactSchema).min(1).max(10),
]);

const setMedicalSchema = z.object({
  bloodGroup: z.string().max(10).optional(),
  allergies: z.string().max(1000).optional(),
  conditions: z.string().max(1000).optional(),
});

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

export function createUsersRouter(pool: Pool): Router {
  const router = Router();

  // All user routes require authentication
  router.use(requireAuth);

  // -----------------------------------------------------------------------
  // POST /users — Create a new user
  // -----------------------------------------------------------------------
  router.post('/', async (req: Request, res: Response) => {
    try {
      const parsed = createUserSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid user payload',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const { name, phone, language } = parsed.data;
      const userId = crypto.randomUUID();
      const bleUid = generateBleUid(userId);

      const { rows } = await pool.query(
        `INSERT INTO users (id, name, phone, ble_uid, language)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [userId, name ?? null, phone, bleUid, language],
      );

      const user = rowToUser(rows[0]);
      logger.info(`User created: ${userId} (phone: ${phone})`);

      // Return the BLE UID hex to the client for BLE advertising
      res.status(201).json({
        id: user.id,
        name: user.name,
        phone: user.phone,
        language: user.language,
        bleUid: bleUid.toString('hex'),
        createdAt: user.createdAt,
      });
    } catch (err: any) {
      // Handle unique constraint violations
      if (err?.code === '23505') {
        const detail: string = err.detail ?? '';
        if (detail.includes('phone')) {
          res.status(409).json({ error: 'Phone number already registered' });
          return;
        }
        if (detail.includes('ble_uid')) {
          res.status(409).json({ error: 'BLE UID collision — please retry' });
          return;
        }
      }
      logger.error('User creation error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /users/:id — Fetch full user profile
  // -----------------------------------------------------------------------
  router.get('/:id', async (req: Request, res: Response) => {
    try {
      const userId = req.params.id as string;
      const profile = await getFullUserProfile(pool, userId);

      if (!profile) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      // Never expose raw ble_uid in public responses
      res.status(200).json({
        user: {
          id: profile.user.id,
          name: profile.user.name,
          phone: profile.user.phone,
          language: profile.user.language,
          createdAt: profile.user.createdAt,
        },
        contacts: profile.contacts,
        medical: profile.medical,
      });
    } catch (err) {
      logger.error('User profile fetch error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // POST /users/:id/contacts — Add emergency contacts
  // -----------------------------------------------------------------------
  router.post('/:id/contacts', async (req: Request, res: Response) => {
    try {
      const userId = req.params.id;

      // Verify user exists
      const { rows: userRows } = await pool.query(
        'SELECT id FROM users WHERE id = $1',
        [userId],
      );
      if (userRows.length === 0) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      const parsed = addContactsSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid contacts payload',
          details: parsed.error.flatten(),
        });
        return;
      }

      const contacts = Array.isArray(parsed.data) ? parsed.data : [parsed.data];
      const inserted = [];

      for (const contact of contacts) {
        const contactId = crypto.randomUUID();
        await pool.query(
          `INSERT INTO emergency_contacts (id, user_id, name, phone, priority)
           VALUES ($1, $2, $3, $4, $5)`,
          [contactId, userId, contact.name ?? null, contact.phone, contact.priority],
        );
        inserted.push({
          id: contactId,
          userId,
          name: contact.name ?? null,
          phone: contact.phone,
          priority: contact.priority,
        });
      }

      logger.info(`${inserted.length} emergency contact(s) added for user ${userId}`);
      res.status(201).json(inserted);
    } catch (err) {
      logger.error('Add contacts error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // POST /users/:id/medical — Set/update medical profile
  // -----------------------------------------------------------------------
  router.post('/:id/medical', async (req: Request, res: Response) => {
    try {
      const userId = req.params.id;

      // Verify user exists
      const { rows: userRows } = await pool.query(
        'SELECT id FROM users WHERE id = $1',
        [userId],
      );
      if (userRows.length === 0) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      const parsed = setMedicalSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid medical profile payload',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const { bloodGroup, allergies, conditions } = parsed.data;

      await pool.query(
        `INSERT INTO medical_profiles (user_id, blood_group, allergies, conditions)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id) DO UPDATE SET
           blood_group = EXCLUDED.blood_group,
           allergies   = EXCLUDED.allergies,
           conditions  = EXCLUDED.conditions`,
        [userId, bloodGroup ?? null, allergies ?? null, conditions ?? null],
      );

      logger.info(`Medical profile set for user ${userId}`);
      res.status(200).json({
        userId,
        bloodGroup: bloodGroup ?? null,
        allergies: allergies ?? null,
        conditions: conditions ?? null,
      });
    } catch (err) {
      logger.error('Set medical profile error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  return router;
}
