import cron from 'node-cron';
import { prisma } from '../lib/prisma';
import { formatIndonesianTime, getDayRange, getTimePartsInZone } from '../lib/time';
import { syncGoogleCalendarEvents } from '../services/calendar/googleCalendarService';
import { syncMicrosoftCalendarEvents } from '../services/calendar/microsoftCalendarService';
import { getUnifiedAgenda } from '../services/calendar/unifiedAgendaService';
import { sendPushToUser } from '../services/notificationService';

// Menyimpan log sederhana agar push briefing/reminder tidak terkirim ganda di hari yang sama
const sentLog = new Set<string>();

function markSent(key: string): boolean {
  if (sentLog.has(key)) return false;
  sentLog.add(key);
  if (sentLog.size > 5000) {
    sentLog.clear();
  }
  return true;
}

export function startBackgroundSchedulers(): void {
  // 1. Setiap 15 menit: Sinkronisasi Google & Microsoft Calendar + kirim pengingat acara < 20 menit lagi
  cron.schedule('*/15 * * * *', async () => {
    try {
      const users = await prisma.user.findMany({
        include: { oauthAccounts: true, deviceTokens: true },
      });

      const { start, end } = getDayRange();
      const nowMs = Date.now();

      for (const user of users) {
        const hasGoogle = user.oauthAccounts.some((a) => a.provider === 'google');
        const hasMs = user.oauthAccounts.some((a) => a.provider === 'microsoft');

        if (hasGoogle) {
          try {
            await syncGoogleCalendarEvents(user.id, start, end);
          } catch (err) {
            console.warn(`[Cron] Google sync gagal untuk user ${user.id}:`, err);
          }
        }
        if (hasMs) {
          try {
            await syncMicrosoftCalendarEvents(user.id, start, end);
          } catch (err) {
            console.warn(`[Cron] Microsoft sync gagal untuk user ${user.id}:`, err);
          }
        }

        // Kirim notifikasi push untuk acara yang mulai dalam 15 menit ke depan
        const upcoming = await prisma.calendarEventCache.findMany({
          where: {
            userId: user.id,
            startAt: {
              gte: new Date(nowMs),
              lte: new Date(nowMs + 20 * 60_000),
            },
          },
        });

        for (const ev of upcoming) {
          const dedupKey = `upcoming:${user.id}:${ev.id}:${ev.startAt.toISOString()}`;
          if (!markSent(dedupKey)) continue;

          const startLabel = formatIndonesianTime(ev.startAt, user.timezone);
          await sendPushToUser(user.id, {
            title: `Sebentar lagi: ${ev.title}`,
            body: `Mulai pukul ${startLabel}${ev.location ? ` di ${ev.location}` : ''}. Tarik napas sebentar ya, ${user.nickname}!`,
            data: {
              type: 'calendar_upcoming',
              eventId: ev.id,
              route: '/today',
            },
          });
        }
      }
    } catch (err) {
      console.error('[Cron] Error pada job sinkronisasi kalender:', err);
    }
  });

  // 2. Setiap 15 menit cek zona waktu tiap user untuk Morning Briefing (07:00) & Evening Check-in (20:30)
  cron.schedule('*/15 * * * *', async () => {
    try {
      const users = await prisma.user.findMany({
        include: { deviceTokens: true },
      });
      const now = new Date();

      for (const user of users) {
        if (user.deviceTokens.length === 0) continue;

        const parts = getTimePartsInZone(now, user.timezone);
        const dateKey = `${parts.year}-${parts.month}-${parts.day}`;

        // Morning Briefing jam 07:00 - 07:14 waktu lokal pengguna
        if (parts.hour === 7 && parts.minute < 15) {
          const key = `morning:${user.id}:${dateKey}`;
          if (markSent(key)) {
            const agenda = await getUnifiedAgenda(user.id);
            const eventCount = agenda.items.filter((i) => i.kind === 'event').length;
            const taskCount = agenda.items.filter(
              (i) => i.kind === 'task' && !i.isCompleted,
            ).length;

            await sendPushToUser(user.id, {
              title: `Selamat pagi, ${user.nickname} ☀️`,
              body: `Hari ini ada ${eventCount} jadwal kalender dan ${taskCount} tugas. Aku siap nemenin langkahmu hari ini!`,
              data: {
                type: 'morning_briefing',
                route: '/today',
              },
            });
          }
        }

        // Evaluasi santai & sapaan hangat malam hari jam 20:30 - 20:44 waktu lokal pengguna
        if (parts.hour === 20 && parts.minute >= 30 && parts.minute < 45) {
          const key = `evening:${user.id}:${dateKey}`;
          if (markSent(key)) {
            await sendPushToUser(user.id, {
              title: `Gimana harimu, ${user.nickname}? 🌙`,
              body: 'Terima kasih sudah bertahan sampai malam ini. Yuk cerita sebentar atau cek mood sebelum istirahat.',
              data: {
                type: 'evening_checkin',
                route: '/chat',
              },
            });
          }
        }
      }
    } catch (err) {
      console.error('[Cron] Error pada job sapaan pagi/malam:', err);
    }
  });

  console.info('[Scheduler] Cron sinkronisasi kalender, morning briefing & sapaan malam aktif.');
}
