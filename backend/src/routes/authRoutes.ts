import { Router } from 'express';
import { z } from 'zod';
import { capabilities } from '../config/env';
import { prisma } from '../lib/prisma';
import {
  AuthenticatedRequest,
  requireAuth,
  signAuthToken,
} from '../middleware/auth';

const router = Router();

const bootstrapSchema = z.object({
  deviceKey: z.string().min(6).max(128),
  nickname: z.string().min(1).max(40).optional(),
  timezone: z.string().min(3).max(64).optional(),
});

const updateProfileSchema = z.object({
  nickname: z.string().min(1).max(40).optional(),
  aiPersona: z.enum(['santai', 'tenang', 'ceria']).optional(),
  voiceEnabled: z.boolean().optional(),
  ttsSpeechRate: z.number().min(0.25).max(1.0).optional(),
  demoMode: z.boolean().optional(),
  quietHoursEnabled: z.boolean().optional(),
  quietStart: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  quietEnd: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  timezone: z.string().min(3).max(64).optional(),
});

const moodSchema = z.object({
  mood: z.enum(['senang', 'tenang', 'semangat', 'lelah', 'cemas', 'sedih']),
  score: z.number().int().min(1).max(5),
  note: z.string().max(400).optional(),
});

/**
 * POST /api/auth/bootstrap
 * Membuka sesi aman instan berbasis deviceKey perangkat (tanpa hambatan onboarding),
 * lalu mengembalikan JWT token + profil pengguna.
 */
router.post('/bootstrap', async (req, res, next) => {
  try {
    const parsed = bootstrapSchema.parse(req.body);
    let user = await prisma.user.findUnique({
      where: { deviceKey: parsed.deviceKey },
      include: { oauthAccounts: true },
    });

    if (!user) {
      user = await prisma.user.create({
        data: {
          deviceKey: parsed.deviceKey,
          nickname: parsed.nickname?.trim() || 'Teman',
          timezone: parsed.timezone || 'Asia/Jakarta',
          demoMode: true,
        },
        include: { oauthAccounts: true },
      });

      // Seed sapaan perdana di ruang obrolan agar pengguna langsung merasa disambut
      await prisma.chatMessage.create({
        data: {
          userId: user.id,
          role: 'assistant',
          content:
            `Halo ${user.nickname}! Aku TemanHari — teman ngobrol sekaligus pengingat harianmu. ` +
            `Kamu bisa curhat santai, tanya agenda hari ini, atau langsung bilang "Tolong ingetin besok jam 8 pagi kirim laporan" dan aku bakal pasang notifikasinya di HP-mu. Gimana kabarmu hari ini?`,
        },
      });
    }

    const token = signAuthToken({ userId: user.id, deviceKey: user.deviceKey });

    res.json({
      token,
      capabilities,
      user: {
        id: user.id,
        nickname: user.nickname,
        aiPersona: user.aiPersona,
        voiceEnabled: user.voiceEnabled,
        ttsSpeechRate: user.ttsSpeechRate,
        demoMode: user.demoMode,
        quietHoursEnabled: user.quietHoursEnabled,
        quietStart: user.quietStart,
        quietEnd: user.quietEnd,
        timezone: user.timezone,
        connectedProviders: {
          google: {
            connected: user.oauthAccounts.some((a) => a.provider === 'google'),
            email:
              user.oauthAccounts.find((a) => a.provider === 'google')?.providerEmail ??
              null,
          },
          microsoft: {
            connected: user.oauthAccounts.some((a) => a.provider === 'microsoft'),
            email:
              user.oauthAccounts.find((a) => a.provider === 'microsoft')
                ?.providerEmail ?? null,
          },
        },
      },
    });
  } catch (err) {
    next(err);
  }
});

router.get('/me', requireAuth, async (req: AuthenticatedRequest, res, next) => {
  try {
    const user = await prisma.user.findUniqueOrThrow({
      where: { id: req.userId! },
      include: { oauthAccounts: true },
    });
    const [latestMood, memories] = await Promise.all([
      prisma.moodEntry.findFirst({
        where: { userId: user.id },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.userMemory.findMany({
        where: { userId: user.id },
        orderBy: [{ importance: 'desc' }, { updatedAt: 'desc' }],
        take: 15,
      }),
    ]);

    res.json({
      capabilities,
      user: {
        id: user.id,
        nickname: user.nickname,
        aiPersona: user.aiPersona,
        voiceEnabled: user.voiceEnabled,
        ttsSpeechRate: user.ttsSpeechRate,
        demoMode: user.demoMode,
        quietHoursEnabled: user.quietHoursEnabled,
        quietStart: user.quietStart,
        quietEnd: user.quietEnd,
        timezone: user.timezone,
        connectedProviders: {
          google: {
            connected: user.oauthAccounts.some((a) => a.provider === 'google'),
            email:
              user.oauthAccounts.find((a) => a.provider === 'google')?.providerEmail ??
              null,
          },
          microsoft: {
            connected: user.oauthAccounts.some((a) => a.provider === 'microsoft'),
            email:
              user.oauthAccounts.find((a) => a.provider === 'microsoft')
                ?.providerEmail ?? null,
          },
        },
      },
      latestMood,
      memories,
    });
  } catch (err) {
    next(err);
  }
});

router.patch('/profile', requireAuth, async (req: AuthenticatedRequest, res, next) => {
  try {
    const parsed = updateProfileSchema.parse(req.body);
    const updated = await prisma.user.update({
      where: { id: req.userId! },
      data: parsed,
      include: { oauthAccounts: true },
    });

    res.json({
      user: {
        id: updated.id,
        nickname: updated.nickname,
        aiPersona: updated.aiPersona,
        voiceEnabled: updated.voiceEnabled,
        ttsSpeechRate: updated.ttsSpeechRate,
        demoMode: updated.demoMode,
        quietHoursEnabled: updated.quietHoursEnabled,
        quietStart: updated.quietStart,
        quietEnd: updated.quietEnd,
        timezone: updated.timezone,
        connectedProviders: {
          google: {
            connected: updated.oauthAccounts.some((a) => a.provider === 'google'),
            email:
              updated.oauthAccounts.find((a) => a.provider === 'google')
                ?.providerEmail ?? null,
          },
          microsoft: {
            connected: updated.oauthAccounts.some((a) => a.provider === 'microsoft'),
            email:
              updated.oauthAccounts.find((a) => a.provider === 'microsoft')
                ?.providerEmail ?? null,
          },
        },
      },
    });
  } catch (err) {
    next(err);
  }
});

router.post('/mood', requireAuth, async (req: AuthenticatedRequest, res, next) => {
  try {
    const parsed = moodSchema.parse(req.body);
    const entry = await prisma.moodEntry.create({
      data: {
        userId: req.userId!,
        mood: parsed.mood,
        score: parsed.score,
        note: parsed.note ?? null,
      },
    });
    res.status(201).json({ mood: entry });
  } catch (err) {
    next(err);
  }
});

router.get('/mood', requireAuth, async (req: AuthenticatedRequest, res, next) => {
  try {
    const entries = await prisma.moodEntry.findMany({
      where: { userId: req.userId! },
      orderBy: { createdAt: 'desc' },
      take: 14,
    });
    res.json({ moods: entries });
  } catch (err) {
    next(err);
  }
});

router.delete('/memories/:memoryId', requireAuth, async (req: AuthenticatedRequest, res, next) => {
  try {
    await prisma.userMemory.deleteMany({
      where: { id: String(req.params.memoryId), userId: req.userId! },
    });
    res.json({ deleted: true });
  } catch (err) {
    next(err);
  }
});

export default router;
