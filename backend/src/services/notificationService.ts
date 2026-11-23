import fs from 'fs';
import admin from 'firebase-admin';
import { capabilities, env } from '../config/env';
import { prisma } from '../lib/prisma';
import { isWithinQuietHours } from '../lib/time';

let firebaseInitialized = false;

export function initFirebaseAdmin(): boolean {
  if (firebaseInitialized) return true;
  if (!capabilities.firebase) {
    return false;
  }

  try {
    if (admin.apps.length > 0) {
      firebaseInitialized = true;
      return true;
    }

    if (env.FIREBASE_SERVICE_ACCOUNT_PATH && fs.existsSync(env.FIREBASE_SERVICE_ACCOUNT_PATH)) {
      const raw = fs.readFileSync(env.FIREBASE_SERVICE_ACCOUNT_PATH, 'utf8');
      const serviceAccount = JSON.parse(raw) as admin.ServiceAccount;
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      firebaseInitialized = true;
      return true;
    }

    if (env.FIREBASE_PROJECT_ID && env.FIREBASE_CLIENT_EMAIL && env.FIREBASE_PRIVATE_KEY) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: env.FIREBASE_PROJECT_ID,
          clientEmail: env.FIREBASE_CLIENT_EMAIL,
          privateKey: env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
        }),
      });
      firebaseInitialized = true;
      return true;
    }
  } catch (err) {
    console.error('[FCM] Gagal menginisialisasi Firebase Admin SDK:', err);
  }

  return false;
}

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
  respectQuietHours?: boolean;
}

export async function sendPushToUser(
  userId: string,
  payload: PushPayload,
): Promise<{ sent: number; skippedReason?: string }> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { deviceTokens: true },
  });

  if (!user) return { sent: 0, skippedReason: 'user_not_found' };
  if (user.deviceTokens.length === 0) {
    return { sent: 0, skippedReason: 'no_device_tokens' };
  }

  if (payload.respectQuietHours !== false) {
    const quiet = isWithinQuietHours({
      enabled: user.quietHoursEnabled,
      quietStart: user.quietStart,
      quietEnd: user.quietEnd,
      timeZone: user.timezone,
    });
    if (quiet) {
      return { sent: 0, skippedReason: 'quiet_hours_active' };
    }
  }

  if (!initFirebaseAdmin()) {
    console.info(
      `[FCM Simulasi] -> user=${user.nickname}: "${payload.title}" | ${payload.body}`,
    );
    return { sent: 0, skippedReason: 'firebase_not_configured' };
  }

  const tokens = user.deviceTokens.map((t) => t.fcmToken);
  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: {
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
      ...(payload.data ?? {}),
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'temanhari_reminders',
        sound: 'default',
        defaultVibrateTimings: true,
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
      },
      payload: {
        aps: {
          sound: 'default',
          contentAvailable: true,
        },
      },
    },
  };

  const response = await admin.messaging().sendEachForMulticast(message);

  // Bersihkan token perangkat yang sudah tidak valid
  const invalidTokens: string[] = [];
  response.responses.forEach((resp, idx) => {
    if (!resp.success) {
      const code = resp.error?.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        invalidTokens.push(tokens[idx]);
      }
    }
  });

  if (invalidTokens.length > 0) {
    await prisma.deviceToken.deleteMany({
      where: { fcmToken: { in: invalidTokens } },
    });
  }

  return { sent: response.successCount };
}
