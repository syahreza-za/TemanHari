import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { AuthenticatedRequest, requireAuth } from '../middleware/auth';
import { sendPushToUser } from '../services/notificationService';

const router = Router();
router.use(requireAuth);

const registerTokenSchema = z.object({
  fcmToken: z.string().min(10).max(512),
  platform: z.enum(['android', 'ios']).default('android'),
});

router.post('/register-device', async (req: AuthenticatedRequest, res, next) => {
  try {
    const parsed = registerTokenSchema.parse(req.body);
    await prisma.deviceToken.upsert({
      where: { fcmToken: parsed.fcmToken },
      update: {
        userId: req.userId!,
        platform: parsed.platform,
      },
      create: {
        userId: req.userId!,
        fcmToken: parsed.fcmToken,
        platform: parsed.platform,
      },
    });
    res.json({ registered: true });
  } catch (err) {
    next(err);
  }
});

router.post('/test-push', async (req: AuthenticatedRequest, res, next) => {
  try {
    const user = await prisma.user.findUniqueOrThrow({ where: { id: req.userId! } });
    const result = await sendPushToUser(user.id, {
      title: `Hai ${user.nickname}, tes sapaan TemanHari 💛`,
      body: 'Notifikasi push berhasil tersambung! Aku siap mengingatkan jadwal pentingmu.',
      respectQuietHours: false,
      data: { type: 'test_push', route: '/chat' },
    });
    res.json(result);
  } catch (err) {
    next(err);
  }
});

export default router;
