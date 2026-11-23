import { prisma } from '../../lib/prisma';

export interface CalendarEventDTO {
  id: string;
  externalId: string;
  provider: 'google' | 'microsoft' | 'demo';
  sourceBadge: 'Google Calendar' | 'Microsoft Outlook' | 'Mode Demo';
  title: string;
  description: string | null;
  location: string | null;
  startAt: string;
  endAt: string;
  isAllDay: boolean;
  meetingLink: string | null;
}

function buildDateOnDay(baseDay: Date, hour: number, minute: number): Date {
  const d = new Date(baseDay);
  d.setHours(hour, minute, 0, 0);
  return d;
}

/**
 * Menyediakan data jadwal simulasi realistis (Outlook + Google) saat Mode Demo aktif,
 * termasuk 1 jadwal bentrok agar pengguna dapat langsung menguji deteksi bentrok jadwal.
 */
export async function getOrSeedDemoEvents(
  userId: string,
  targetDate: Date,
): Promise<CalendarEventDTO[]> {
  const dayStart = new Date(targetDate);
  dayStart.setHours(0, 0, 0, 0);
  const dayEnd = new Date(targetDate);
  dayEnd.setHours(23, 59, 59, 999);
  const dateKey = dayStart.toISOString().slice(0, 10);

  const existing = await prisma.calendarEventCache.findMany({
    where: {
      userId,
      provider: 'demo',
      startAt: { gte: dayStart, lte: dayEnd },
    },
    orderBy: { startAt: 'asc' },
  });

  if (existing.length > 0) {
    return existing.map((ev) => ({
      id: ev.id,
      externalId: ev.externalId,
      provider: ev.externalId.startsWith('demo-outlook') ? 'microsoft' : 'google',
      sourceBadge: ev.externalId.startsWith('demo-outlook')
        ? 'Microsoft Outlook'
        : 'Google Calendar',
      title: ev.title,
      description: ev.description,
      location: ev.location,
      startAt: ev.startAt.toISOString(),
      endAt: ev.endAt.toISOString(),
      isAllDay: ev.isAllDay,
      meetingLink: ev.meetingLink,
    }));
  }

  const templates = [
    {
      externalId: `demo-outlook-standup-${dateKey}`,
      title: 'Daily Standup Tim Produk (Outlook)',
      description: 'Sinkronisasi progres sprint minggu ini bersama tim engineering & desain.',
      location: 'Microsoft Teams',
      startAt: buildDateOnDay(dayStart, 9, 0),
      endAt: buildDateOnDay(dayStart, 9, 45),
      meetingLink: 'https://teams.microsoft.com/l/meetup-join/demo-standup',
    },
    {
      externalId: `demo-google-client-${dateKey}`,
      title: 'Review Proposal Klien Nusantara',
      description: 'Presentasi timeline Q4 dan finalisasi kebutuhan integrasi.',
      location: 'Google Meet',
      startAt: buildDateOnDay(dayStart, 13, 30),
      endAt: buildDateOnDay(dayStart, 14, 30),
      meetingLink: 'https://meet.google.com/abc-defg-hij',
    },
    {
      // Sengaja tumpang tindih dengan Review Proposal (14:00 - 15:00) untuk demonstrasi deteksi bentrok
      externalId: `demo-outlook-sync-${dateKey}`,
      title: '1-on-1 Check-in dengan Lead',
      description: 'Bahas prioritas bulan depan dan dukungan yang dibutuhkan.',
      location: 'Microsoft Teams',
      startAt: buildDateOnDay(dayStart, 14, 0),
      endAt: buildDateOnDay(dayStart, 15, 0),
      meetingLink: 'https://teams.microsoft.com/l/meetup-join/demo-1on1',
    },
    {
      externalId: `demo-google-walk-${dateKey}`,
      title: 'Jalan Santai Sore & Tarik Napas',
      description: 'Waktu jeda 30 menit tanpa layar supaya pikiran kembali segar.',
      location: 'Taman Dekat Rumah',
      startAt: buildDateOnDay(dayStart, 17, 15),
      endAt: buildDateOnDay(dayStart, 17, 45),
      meetingLink: null,
    },
  ];

  const created = await Promise.all(
    templates.map((tpl) =>
      prisma.calendarEventCache.upsert({
        where: {
          userId_provider_externalId: {
            userId,
            provider: 'demo',
            externalId: tpl.externalId,
          },
        },
        update: {},
        create: {
          userId,
          provider: 'demo',
          externalId: tpl.externalId,
          title: tpl.title,
          description: tpl.description,
          location: tpl.location,
          startAt: tpl.startAt,
          endAt: tpl.endAt,
          isAllDay: false,
          meetingLink: tpl.meetingLink,
        },
      }),
    ),
  );

  return created.map((ev) => ({
    id: ev.id,
    externalId: ev.externalId,
    provider: ev.externalId.startsWith('demo-outlook') ? 'microsoft' : 'google',
    sourceBadge: ev.externalId.startsWith('demo-outlook')
      ? 'Microsoft Outlook'
      : 'Google Calendar',
    title: ev.title,
    description: ev.description,
    location: ev.location,
    startAt: ev.startAt.toISOString(),
    endAt: ev.endAt.toISOString(),
    isAllDay: ev.isAllDay,
    meetingLink: ev.meetingLink,
  }));
}

export async function createDemoCalendarEvent(params: {
  userId: string;
  providerHint: 'google' | 'microsoft';
  title: string;
  description?: string;
  location?: string;
  startAt: Date;
  endAt: Date;
}): Promise<CalendarEventDTO> {
  const prefix = params.providerHint === 'microsoft' ? 'demo-outlook' : 'demo-google';
  const externalId = `${prefix}-custom-${Date.now()}`;

  const created = await prisma.calendarEventCache.create({
    data: {
      userId: params.userId,
      provider: 'demo',
      externalId,
      title: params.title,
      description: params.description ?? null,
      location: params.location ?? null,
      startAt: params.startAt,
      endAt: params.endAt,
      isAllDay: false,
      meetingLink: null,
    },
  });

  return {
    id: created.id,
    externalId: created.externalId,
    provider: params.providerHint,
    sourceBadge:
      params.providerHint === 'microsoft' ? 'Microsoft Outlook' : 'Google Calendar',
    title: created.title,
    description: created.description,
    location: created.location,
    startAt: created.startAt.toISOString(),
    endAt: created.endAt.toISOString(),
    isAllDay: created.isAllDay,
    meetingLink: created.meetingLink,
  };
}
