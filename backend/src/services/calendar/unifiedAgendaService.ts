import { prisma } from '../../lib/prisma';
import { getDayRange } from '../../lib/time';
import {
  CalendarEventDTO,
  createDemoCalendarEvent,
  getOrSeedDemoEvents,
} from './demoCalendarService';
import {
  createGoogleCalendarEvent,
  syncGoogleCalendarEvents,
} from './googleCalendarService';
import {
  createMicrosoftCalendarEvent,
  syncMicrosoftCalendarEvents,
} from './microsoftCalendarService';

export interface UnifiedAgendaItem {
  id: string;
  kind: 'event' | 'task';
  source: 'google' | 'microsoft' | 'task';
  sourceBadge: string;
  title: string;
  description: string | null;
  location: string | null;
  startAt: string;
  endAt: string | null;
  isAllDay: boolean;
  isCompleted: boolean;
  priority: string | null;
  category: string | null;
  recurrence: string | null;
  notificationId: number | null;
  meetingLink: string | null;
  hasConflict: boolean;
  conflictWithIds: string[];
}

export interface UnifiedAgendaResponse {
  date: string;
  demoMode: boolean;
  connectedProviders: {
    google: { connected: boolean; email: string | null };
    microsoft: { connected: boolean; email: string | null };
  };
  conflictCount: number;
  items: UnifiedAgendaItem[];
}

/**
 * Mendeteksi tumpang tindih (bentrok) antar jadwal kalender dalam hari yang sama.
 */
export function detectScheduleConflicts(items: UnifiedAgendaItem[]): UnifiedAgendaItem[] {
  const timedEvents = items
    .map((item, idx) => ({ item, idx }))
    .filter(
      ({ item }) =>
        item.kind === 'event' && !item.isAllDay && item.startAt && item.endAt,
    );

  const conflictMap = new Map<string, Set<string>>();

  for (let i = 0; i < timedEvents.length; i++) {
    const a = timedEvents[i].item;
    const aStart = new Date(a.startAt).getTime();
    const aEnd = new Date(a.endAt!).getTime();

    for (let j = i + 1; j < timedEvents.length; j++) {
      const b = timedEvents[j].item;
      const bStart = new Date(b.startAt).getTime();
      const bEnd = new Date(b.endAt!).getTime();

      if (aStart < bEnd && bStart < aEnd) {
        if (!conflictMap.has(a.id)) conflictMap.set(a.id, new Set());
        if (!conflictMap.has(b.id)) conflictMap.set(b.id, new Set());
        conflictMap.get(a.id)!.add(b.id);
        conflictMap.get(b.id)!.add(a.id);
      }
    }
  }

  return items.map((item) => {
    const conflicts = conflictMap.get(item.id);
    if (!conflicts || conflicts.size === 0) return item;
    return {
      ...item,
      hasConflict: true,
      conflictWithIds: Array.from(conflicts),
    };
  });
}

export async function getUnifiedAgenda(
  userId: string,
  options?: { date?: string; forceSync?: boolean },
): Promise<UnifiedAgendaResponse> {
  const user = await prisma.user.findUniqueOrThrow({
    where: { id: userId },
    include: { oauthAccounts: true },
  });

  const { start, end } = getDayRange(options?.date);
  const googleAccount = user.oauthAccounts.find((a) => a.provider === 'google');
  const microsoftAccount = user.oauthAccounts.find((a) => a.provider === 'microsoft');

  const events: CalendarEventDTO[] = [];

  if (options?.forceSync) {
    if (googleAccount) {
      try {
        await syncGoogleCalendarEvents(userId, start, end);
      } catch (err) {
        console.warn('[GoogleSync] Gagal sinkronisasi langsung, menggunakan cache:', err);
      }
    }
    if (microsoftAccount) {
      try {
        await syncMicrosoftCalendarEvents(userId, start, end);
      } catch (err) {
        console.warn('[MicrosoftSync] Gagal sinkronisasi langsung, menggunakan cache:', err);
      }
    }
  }

  // Muat acara dari Google / Microsoft yang sudah di-cache
  if (googleAccount || microsoftAccount) {
    const cached = await prisma.calendarEventCache.findMany({
      where: {
        userId,
        provider: { in: ['google', 'microsoft'] },
        startAt: { gte: start, lte: end },
      },
      orderBy: { startAt: 'asc' },
    });

    for (const ev of cached) {
      events.push({
        id: ev.id,
        externalId: ev.externalId,
        provider: ev.provider === 'microsoft' ? 'microsoft' : 'google',
        sourceBadge:
          ev.provider === 'microsoft' ? 'Microsoft Outlook' : 'Google Calendar',
        title: ev.title,
        description: ev.description,
        location: ev.location,
        startAt: ev.startAt.toISOString(),
        endAt: ev.endAt.toISOString(),
        isAllDay: ev.isAllDay,
        meetingLink: ev.meetingLink,
      });
    }
  }

  // Jika Mode Demo aktif (dan belum ada akun kalender yang tersambung atau demo memang dinyalakan)
  if (user.demoMode && events.length === 0) {
    const demoEvents = await getOrSeedDemoEvents(userId, start);
    events.push(...demoEvents);
  }

  // Ambil tugas harian untuk tanggal tersebut (serta tugas aktif tanpa tanggal jatuh tempo)
  const tasks = await prisma.task.findMany({
    where: {
      userId,
      OR: [
        { dueAt: { gte: start, lte: end } },
        { dueAt: null, isCompleted: false },
      ],
    },
    orderBy: [{ dueAt: 'asc' }, { createdAt: 'asc' }],
  });

  const agendaItems: UnifiedAgendaItem[] = [
    ...events.map((ev): UnifiedAgendaItem => ({
      id: ev.id,
      kind: 'event',
      source: ev.provider === 'microsoft' ? 'microsoft' : 'google',
      sourceBadge: ev.sourceBadge,
      title: ev.title,
      description: ev.description,
      location: ev.location,
      startAt: ev.startAt,
      endAt: ev.endAt,
      isAllDay: ev.isAllDay,
      isCompleted: false,
      priority: null,
      category: null,
      recurrence: null,
      notificationId: null,
      meetingLink: ev.meetingLink,
      hasConflict: false,
      conflictWithIds: [],
    })),
    ...tasks.map((t): UnifiedAgendaItem => ({
      id: t.id,
      kind: 'task',
      source: 'task',
      sourceBadge: 'Tugas Harian',
      title: t.title,
      description: t.notes,
      location: null,
      startAt: (t.dueAt ?? t.remindAt ?? start).toISOString(),
      endAt: null,
      isAllDay: !t.dueAt,
      isCompleted: t.isCompleted,
      priority: t.priority,
      category: t.category,
      recurrence: t.recurrence,
      notificationId: t.notificationId,
      meetingLink: null,
      hasConflict: false,
      conflictWithIds: [],
    })),
  ];

  agendaItems.sort(
    (a, b) => new Date(a.startAt).getTime() - new Date(b.startAt).getTime(),
  );

  const itemsWithConflicts = detectScheduleConflicts(agendaItems);
  const conflictCount = itemsWithConflicts.filter((i) => i.hasConflict).length;

  return {
    date: start.toISOString().slice(0, 10),
    demoMode: user.demoMode,
    connectedProviders: {
      google: {
        connected: Boolean(googleAccount),
        email: googleAccount?.providerEmail ?? null,
      },
      microsoft: {
        connected: Boolean(microsoftAccount),
        email: microsoftAccount?.providerEmail ?? null,
      },
    },
    conflictCount,
    items: itemsWithConflicts,
  };
}

export async function createEventOnProvider(params: {
  userId: string;
  provider: 'google' | 'microsoft';
  title: string;
  description?: string;
  location?: string;
  startAt: Date;
  endAt: Date;
}): Promise<CalendarEventDTO> {
  const user = await prisma.user.findUniqueOrThrow({
    where: { id: params.userId },
    include: { oauthAccounts: true },
  });

  const hasProvider = user.oauthAccounts.some((a) => a.provider === params.provider);

  if (hasProvider) {
    if (params.provider === 'google') {
      return createGoogleCalendarEvent({ ...params, timeZone: user.timezone });
    }
    return createMicrosoftCalendarEvent({ ...params, timeZone: user.timezone });
  }

  if (user.demoMode) {
    return createDemoCalendarEvent({
      userId: params.userId,
      providerHint: params.provider,
      title: params.title,
      description: params.description,
      location: params.location,
      startAt: params.startAt,
      endAt: params.endAt,
    });
  }

  throw new Error(
    `Akun ${params.provider === 'google' ? 'Google Calendar' : 'Microsoft Outlook'} belum terhubung. Aktifkan Mode Demo atau hubungkan akun di menu Pengaturan.`,
  );
}
