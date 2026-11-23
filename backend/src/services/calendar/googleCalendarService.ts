import { google } from 'googleapis';
import { capabilities, env } from '../../config/env';
import { decryptSecret, encryptSecret } from '../../lib/crypto';
import { prisma } from '../../lib/prisma';
import { signOAuthState } from '../../middleware/auth';
import { CalendarEventDTO } from './demoCalendarService';

const GOOGLE_SCOPES = [
  'https://www.googleapis.com/auth/calendar.events',
  'https://www.googleapis.com/auth/calendar.readonly',
  'https://www.googleapis.com/auth/userinfo.email',
];

function createOAuth2Client() {
  return new google.auth.OAuth2(
    env.GOOGLE_CLIENT_ID,
    env.GOOGLE_CLIENT_SECRET,
    env.GOOGLE_REDIRECT_URI,
  );
}

export function buildGoogleAuthUrl(userId: string, redirectScheme?: string): string {
  if (!capabilities.googleOAuth) {
    throw new Error(
      'Kredensial GOOGLE_CLIENT_ID dan GOOGLE_CLIENT_SECRET belum dikonfigurasi di server.',
    );
  }

  const oauth2Client = createOAuth2Client();
  const state = signOAuthState({
    userId,
    provider: 'google',
    redirectScheme: redirectScheme || env.MOBILE_DEEP_LINK_SCHEME,
  });

  return oauth2Client.generateAuthUrl({
    access_type: 'offline',
    prompt: 'consent',
    scope: GOOGLE_SCOPES,
    state,
  });
}

export async function handleGoogleCallback(
  userId: string,
  code: string,
): Promise<{ email: string | null }> {
  const oauth2Client = createOAuth2Client();
  const { tokens } = await oauth2Client.getToken(code);

  if (!tokens.access_token) {
    throw new Error('Google tidak mengembalikan access_token.');
  }

  oauth2Client.setCredentials(tokens);
  let providerEmail: string | null = null;
  try {
    const oauth2 = google.oauth2({ version: 'v2', auth: oauth2Client });
    const me = await oauth2.userinfo.get();
    providerEmail = me.data.email ?? null;
  } catch {
    providerEmail = null;
  }

  const expiresAt = tokens.expiry_date
    ? new Date(tokens.expiry_date)
    : new Date(Date.now() + 3600 * 1000);

  const existing = await prisma.oAuthAccount.findUnique({
    where: { userId_provider: { userId, provider: 'google' } },
  });

  await prisma.oAuthAccount.upsert({
    where: { userId_provider: { userId, provider: 'google' } },
    update: {
      providerEmail: providerEmail ?? existing?.providerEmail ?? null,
      accessTokenEnc: encryptSecret(tokens.access_token),
      refreshTokenEnc: tokens.refresh_token
        ? encryptSecret(tokens.refresh_token)
        : existing?.refreshTokenEnc ?? null,
      expiresAt,
      scope: tokens.scope ?? GOOGLE_SCOPES.join(' '),
    },
    create: {
      userId,
      provider: 'google',
      providerEmail,
      accessTokenEnc: encryptSecret(tokens.access_token),
      refreshTokenEnc: tokens.refresh_token ? encryptSecret(tokens.refresh_token) : null,
      expiresAt,
      scope: tokens.scope ?? GOOGLE_SCOPES.join(' '),
    },
  });

  return { email: providerEmail };
}

async function getAuthorizedGoogleClient(userId: string) {
  const account = await prisma.oAuthAccount.findUnique({
    where: { userId_provider: { userId, provider: 'google' } },
  });
  if (!account) return null;

  const oauth2Client = createOAuth2Client();
  const accessToken = decryptSecret(account.accessTokenEnc);
  const refreshToken = account.refreshTokenEnc
    ? decryptSecret(account.refreshTokenEnc)
    : undefined;

  oauth2Client.setCredentials({
    access_token: accessToken,
    refresh_token: refreshToken,
    expiry_date: account.expiresAt.getTime(),
  });

  // Auto-refresh token bila akan kedaluwarsa dalam 5 menit
  if (account.expiresAt.getTime() < Date.now() + 5 * 60_000 && refreshToken) {
    const refreshed = await oauth2Client.refreshAccessToken();
    const newCreds = refreshed.credentials;
    if (newCreds.access_token) {
      await prisma.oAuthAccount.update({
        where: { id: account.id },
        data: {
          accessTokenEnc: encryptSecret(newCreds.access_token),
          refreshTokenEnc: newCreds.refresh_token
            ? encryptSecret(newCreds.refresh_token)
            : account.refreshTokenEnc,
          expiresAt: newCreds.expiry_date
            ? new Date(newCreds.expiry_date)
            : new Date(Date.now() + 3600 * 1000),
        },
      });
    }
  }

  return oauth2Client;
}

export async function syncGoogleCalendarEvents(
  userId: string,
  timeMin: Date,
  timeMax: Date,
): Promise<CalendarEventDTO[]> {
  const authClient = await getAuthorizedGoogleClient(userId);
  if (!authClient) return [];

  const calendar = google.calendar({ version: 'v3', auth: authClient });
  const response = await calendar.events.list({
    calendarId: 'primary',
    timeMin: timeMin.toISOString(),
    timeMax: timeMax.toISOString(),
    singleEvents: true,
    orderBy: 'startTime',
    maxResults: 50,
  });

  const items = response.data.items ?? [];
  const results: CalendarEventDTO[] = [];

  for (const item of items) {
    if (!item.id || !item.start) continue;
    const isAllDay = Boolean(item.start.date && !item.start.dateTime);
    const startAt = new Date(item.start.dateTime ?? `${item.start.date}T00:00:00`);
    const endAt = new Date(
      item.end?.dateTime ??
        (item.end?.date ? `${item.end.date}T23:59:59` : startAt.getTime() + 3600_000),
    );

    const saved = await prisma.calendarEventCache.upsert({
      where: {
        userId_provider_externalId: {
          userId,
          provider: 'google',
          externalId: item.id,
        },
      },
      update: {
        title: item.summary ?? '(Tanpa Judul)',
        description: item.description ?? null,
        location: item.location ?? null,
        startAt,
        endAt,
        isAllDay,
        meetingLink: item.hangoutLink ?? item.htmlLink ?? null,
        syncedAt: new Date(),
      },
      create: {
        userId,
        provider: 'google',
        externalId: item.id,
        title: item.summary ?? '(Tanpa Judul)',
        description: item.description ?? null,
        location: item.location ?? null,
        startAt,
        endAt,
        isAllDay,
        meetingLink: item.hangoutLink ?? item.htmlLink ?? null,
      },
    });

    results.push({
      id: saved.id,
      externalId: saved.externalId,
      provider: 'google',
      sourceBadge: 'Google Calendar',
      title: saved.title,
      description: saved.description,
      location: saved.location,
      startAt: saved.startAt.toISOString(),
      endAt: saved.endAt.toISOString(),
      isAllDay: saved.isAllDay,
      meetingLink: saved.meetingLink,
    });
  }

  return results;
}

export async function createGoogleCalendarEvent(params: {
  userId: string;
  title: string;
  description?: string;
  location?: string;
  startAt: Date;
  endAt: Date;
  timeZone: string;
}): Promise<CalendarEventDTO> {
  const authClient = await getAuthorizedGoogleClient(params.userId);
  if (!authClient) {
    throw new Error('Akun Google Calendar belum terhubung.');
  }

  const calendar = google.calendar({ version: 'v3', auth: authClient });
  const created = await calendar.events.insert({
    calendarId: 'primary',
    requestBody: {
      summary: params.title,
      description: params.description,
      location: params.location,
      start: {
        dateTime: params.startAt.toISOString(),
        timeZone: params.timeZone,
      },
      end: {
        dateTime: params.endAt.toISOString(),
        timeZone: params.timeZone,
      },
    },
  });

  const externalId = created.data.id ?? `google-${Date.now()}`;
  const cached = await prisma.calendarEventCache.upsert({
    where: {
      userId_provider_externalId: {
        userId: params.userId,
        provider: 'google',
        externalId,
      },
    },
    update: {
      title: params.title,
      description: params.description ?? null,
      location: params.location ?? null,
      startAt: params.startAt,
      endAt: params.endAt,
      meetingLink: created.data.hangoutLink ?? created.data.htmlLink ?? null,
      syncedAt: new Date(),
    },
    create: {
      userId: params.userId,
      provider: 'google',
      externalId,
      title: params.title,
      description: params.description ?? null,
      location: params.location ?? null,
      startAt: params.startAt,
      endAt: params.endAt,
      isAllDay: false,
      meetingLink: created.data.hangoutLink ?? created.data.htmlLink ?? null,
    },
  });

  return {
    id: cached.id,
    externalId: cached.externalId,
    provider: 'google',
    sourceBadge: 'Google Calendar',
    title: cached.title,
    description: cached.description,
    location: cached.location,
    startAt: cached.startAt.toISOString(),
    endAt: cached.endAt.toISOString(),
    isAllDay: cached.isAllDay,
    meetingLink: cached.meetingLink,
  };
}

export async function updateGoogleCalendarEvent(params: {
  userId: string;
  externalId: string;
  title?: string;
  description?: string;
  location?: string;
  startAt?: Date;
  endAt?: Date;
  timeZone: string;
}): Promise<CalendarEventDTO> {
  const authClient = await getAuthorizedGoogleClient(params.userId);
  if (!authClient) {
    throw new Error('Akun Google Calendar belum terhubung.');
  }

  const calendar = google.calendar({ version: 'v3', auth: authClient });
  const updated = await calendar.events.patch({
    calendarId: 'primary',
    eventId: params.externalId,
    requestBody: {
      summary: params.title,
      description: params.description,
      location: params.location,
      ...(params.startAt
        ? { start: { dateTime: params.startAt.toISOString(), timeZone: params.timeZone } }
        : {}),
      ...(params.endAt
        ? { end: { dateTime: params.endAt.toISOString(), timeZone: params.timeZone } }
        : {}),
    },
  });

  const startAt = new Date(
    updated.data.start?.dateTime ?? params.startAt?.toISOString() ?? Date.now(),
  );
  const endAt = new Date(
    updated.data.end?.dateTime ?? params.endAt?.toISOString() ?? startAt.getTime() + 3600_000,
  );

  const cached = await prisma.calendarEventCache.upsert({
    where: {
      userId_provider_externalId: {
        userId: params.userId,
        provider: 'google',
        externalId: params.externalId,
      },
    },
    update: {
      title: updated.data.summary ?? params.title ?? '(Tanpa Judul)',
      description: updated.data.description ?? null,
      location: updated.data.location ?? null,
      startAt,
      endAt,
      syncedAt: new Date(),
    },
    create: {
      userId: params.userId,
      provider: 'google',
      externalId: params.externalId,
      title: updated.data.summary ?? params.title ?? '(Tanpa Judul)',
      description: updated.data.description ?? null,
      location: updated.data.location ?? null,
      startAt,
      endAt,
      isAllDay: false,
      meetingLink: updated.data.hangoutLink ?? updated.data.htmlLink ?? null,
    },
  });

  return {
    id: cached.id,
    externalId: cached.externalId,
    provider: 'google',
    sourceBadge: 'Google Calendar',
    title: cached.title,
    description: cached.description,
    location: cached.location,
    startAt: cached.startAt.toISOString(),
    endAt: cached.endAt.toISOString(),
    isAllDay: cached.isAllDay,
    meetingLink: cached.meetingLink,
  };
}
