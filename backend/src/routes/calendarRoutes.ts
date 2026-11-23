import { Router } from 'express';
import { z } from 'zod';
import { env } from '../config/env';
import { prisma } from '../lib/prisma';
import {
  AuthenticatedRequest,
  requireAuth,
  verifyOAuthState,
} from '../middleware/auth';
import {
  buildGoogleAuthUrl,
  handleGoogleCallback,
} from '../services/calendar/googleCalendarService';
import {
  buildMicrosoftAuthUrl,
  handleMicrosoftCallback,
} from '../services/calendar/microsoftCalendarService';
import {
  createEventOnProvider,
  getUnifiedAgenda,
} from '../services/calendar/unifiedAgendaService';

const router = Router();

const createEventSchema = z.object({
  provider: z.enum(['google', 'microsoft']),
  title: z.string().min(1).max(200),
  description: z.string().max(2000).optional(),
  location: z.string().max(250).optional(),
  startAt: z.string().datetime({ offset: true }),
  endAt: z.string().datetime({ offset: true }),
});

/**
 * GET /api/calendar/agenda?date=YYYY-MM-DD&sync=true
 */
router.get('/agenda', requireAuth, async (req: AuthenticatedRequest, res, next) => {
  try {
    const date = typeof req.query.date === 'string' ? req.query.date : undefined;
    const forceSync = req.query.sync === 'true';
    const agenda = await getUnifiedAgenda(req.userId!, { date, forceSync });
    res.json(agenda);
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/calendar/events
 * Membuat acara baru secara dua arah di Google Calendar atau Microsoft Outlook (atau Demo).
 */
router.post('/events', requireAuth, async (req: AuthenticatedRequest, res, next) => {
  try {
    const parsed = createEventSchema.parse(req.body);
    const event = await createEventOnProvider({
      userId: req.userId!,
      provider: parsed.provider,
      title: parsed.title,
      description: parsed.description,
      location: parsed.location,
      startAt: new Date(parsed.startAt),
      endAt: new Date(parsed.endAt),
    });
    res.status(201).json({ event });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/calendar/google/auth-url
 */
router.get(
  '/google/auth-url',
  requireAuth,
  async (req: AuthenticatedRequest, res, next) => {
    try {
      const redirectScheme =
        typeof req.query.redirectScheme === 'string'
          ? req.query.redirectScheme
          : undefined;
      const url = buildGoogleAuthUrl(req.userId!, redirectScheme);
      res.json({ url });
    } catch (err) {
      next(err);
    }
  },
);

/**
 * GET /api/calendar/google/callback
 * Menerima kode OAuth dari Google lalu mengarahkan kembali ke aplikasi Flutter via deep link.
 */
router.get('/google/callback', async (req, res) => {
  const code = typeof req.query.code === 'string' ? req.query.code : '';
  const state = typeof req.query.state === 'string' ? req.query.state : '';
  const errorParam = typeof req.query.error === 'string' ? req.query.error : '';

  let targetScheme = env.MOBILE_DEEP_LINK_SCHEME;
  try {
    if (!state) throw new Error('Parameter state OAuth hilang.');
    const payload = verifyOAuthState(state);
    targetScheme = payload.redirectScheme || env.MOBILE_DEEP_LINK_SCHEME;

    if (errorParam || !code) {
      const redirectUrl = `${targetScheme}?provider=google&status=error&message=${encodeURIComponent(errorParam || 'Otorisasi dibatalkan')}`;
      res.redirect(redirectUrl);
      return;
    }

    const { email } = await handleGoogleCallback(payload.userId, code);
    const redirectUrl = `${targetScheme}?provider=google&status=success&email=${encodeURIComponent(email ?? '')}`;
    res.redirect(redirectUrl);
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Gagal menghubungkan Google Calendar';
    res.redirect(
      `${targetScheme}?provider=google&status=error&message=${encodeURIComponent(msg)}`,
    );
  }
});

/**
 * GET /api/calendar/microsoft/auth-url
 */
router.get(
  '/microsoft/auth-url',
  requireAuth,
  async (req: AuthenticatedRequest, res, next) => {
    try {
      const redirectScheme =
        typeof req.query.redirectScheme === 'string'
          ? req.query.redirectScheme
          : undefined;
      const url = buildMicrosoftAuthUrl(req.userId!, redirectScheme);
      res.json({ url });
    } catch (err) {
      next(err);
    }
  },
);

/**
 * GET /api/calendar/microsoft/callback
 * Menerima kode OAuth dari Microsoft Entra ID lalu redirect ke deep link Flutter.
 */
router.get('/microsoft/callback', async (req, res) => {
  const code = typeof req.query.code === 'string' ? req.query.code : '';
  const state = typeof req.query.state === 'string' ? req.query.state : '';
  const errorParam =
    typeof req.query.error_description === 'string'
      ? req.query.error_description
      : typeof req.query.error === 'string'
        ? req.query.error
        : '';

  let targetScheme = env.MOBILE_DEEP_LINK_SCHEME;
  try {
    if (!state) throw new Error('Parameter state OAuth hilang.');
    const payload = verifyOAuthState(state);
    targetScheme = payload.redirectScheme || env.MOBILE_DEEP_LINK_SCHEME;

    if (errorParam || !code) {
      const redirectUrl = `${targetScheme}?provider=microsoft&status=error&message=${encodeURIComponent(errorParam || 'Otorisasi dibatalkan')}`;
      res.redirect(redirectUrl);
      return;
    }

    const { email } = await handleMicrosoftCallback(payload.userId, code);
    const redirectUrl = `${targetScheme}?provider=microsoft&status=success&email=${encodeURIComponent(email ?? '')}`;
    res.redirect(redirectUrl);
  } catch (err) {
    const msg =
      err instanceof Error ? err.message : 'Gagal menghubungkan Microsoft Outlook';
    res.redirect(
      `${targetScheme}?provider=microsoft&status=error&message=${encodeURIComponent(msg)}`,
    );
  }
});

/**
 * DELETE /api/calendar/:provider/disconnect
 */
router.delete(
  '/:provider/disconnect',
  requireAuth,
  async (req: AuthenticatedRequest, res, next) => {
    try {
      const provider = z.enum(['google', 'microsoft']).parse(req.params.provider);
      await prisma.oAuthAccount.deleteMany({
        where: { userId: req.userId!, provider },
      });
      await prisma.calendarEventCache.deleteMany({
        where: { userId: req.userId!, provider },
      });
      res.json({ disconnected: true, provider });
    } catch (err) {
      next(err);
    }
  },
);

export default router;
