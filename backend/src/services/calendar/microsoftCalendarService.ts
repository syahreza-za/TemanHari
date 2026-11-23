import { capabilities, env } from '../../config/env';
import { decryptSecret, encryptSecret } from '../../lib/crypto';
import { prisma } from '../../lib/prisma';
import { signOAuthState } from '../../middleware/auth';
import { CalendarEventDTO } from './demoCalendarService';

const MICROSOFT_SCOPES = [
  'offline_access',
  'User.Read',
  'Calendars.ReadWrite',
  'Tasks.ReadWrite',
];

function getMicrosoftAuthBase(): string {
  return `https://login.microsoftonline.com/${env.MICROSOFT_TENANT_ID}/oauth2/v2.0`;
}

export function buildMicrosoftAuthUrl(userId: string, redirectScheme?: string): string {
  if (!capabilities.microsoftOAuth) {
    throw new Error(
      'Kredensial MICROSOFT_CLIENT_ID dan MICROSOFT_CLIENT_SECRET belum dikonfigurasi di server.',
    );
  }

  const state = signOAuthState({
    userId,
    provider: 'microsoft',
    redirectScheme: redirectScheme || env.MOBILE_DEEP_LINK_SCHEME,
  });

  const params = new URLSearchParams({
    client_id: env.MICROSOFT_CLIENT_ID,
    response_type: 'code',
    redirect_uri: env.MICROSOFT_REDIRECT_URI,
    response_mode: 'query',
    scope: MICROSOFT_SCOPES.join(' '),
    state,
    prompt: 'select_account',
  });

  return `${getMicrosoftAuthBase()}/authorize?${params.toString()}`;
}

interface MicrosoftTokenResponse {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  scope?: string;
  error?: string;
  error_description?: string;
}

async function exchangeMicrosoftToken(body: URLSearchParams): Promise<MicrosoftTokenResponse> {
  const response = await fetch(`${getMicrosoftAuthBase()}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  const data = (await response.json()) as MicrosoftTokenResponse;
  if (!response.ok || !data.access_token) {
    throw new Error(
      data.error_description || data.error || 'Gagal menukar token OAuth Microsoft.',
    );
  }
  return data;
}

export async function handleMicrosoftCallback(
  userId: string,
  code: string,
): Promise<{ email: string | null }> {
  const form = new URLSearchParams({
    client_id: env.MICROSOFT_CLIENT_ID,
    client_secret: env.MICROSOFT_CLIENT_SECRET,
    code,
    redirect_uri: env.MICROSOFT_REDIRECT_URI,
    grant_type: 'authorization_code',
    scope: MICROSOFT_SCOPES.join(' '),
  });

  const tokenData = await exchangeMicrosoftToken(form);
  const accessToken = tokenData.access_token!;

  let providerEmail: string | null = null;
  try {
    const meRes = await fetch('https://graph.microsoft.com/v1.0/me', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (meRes.ok) {
      const me = (await meRes.json()) as { mail?: string; userPrincipalName?: string };
      providerEmail = me.mail ?? me.userPrincipalName ?? null;
    }
  } catch {
    providerEmail = null;
  }

  const expiresAt = new Date(Date.now() + (tokenData.expires_in ?? 3600) * 1000);
  const existing = await prisma.oAuthAccount.findUnique({
    where: { userId_provider: { userId, provider: 'microsoft' } },
  });

  await prisma.oAuthAccount.upsert({
    where: { userId_provider: { userId, provider: 'microsoft' } },
    update: {
      providerEmail: providerEmail ?? existing?.providerEmail ?? null,
      accessTokenEnc: encryptSecret(accessToken),
      refreshTokenEnc: tokenData.refresh_token
        ? encryptSecret(tokenData.refresh_token)
        : existing?.refreshTokenEnc ?? null,
      expiresAt,
      scope: tokenData.scope ?? MICROSOFT_SCOPES.join(' '),
    },
    create: {
      userId,
      provider: 'microsoft',
      providerEmail,
      accessTokenEnc: encryptSecret(accessToken),
      refreshTokenEnc: tokenData.refresh_token
        ? encryptSecret(tokenData.refresh_token)
        : null,
      expiresAt,
      scope: tokenData.scope ?? MICROSOFT_SCOPES.join(' '),
    },
  });

  return { email: providerEmail };
}

async function getValidMicrosoftAccessToken(userId: string): Promise<string | null> {
  const account = await prisma.oAuthAccount.findUnique({
    where: { userId_provider: { userId, provider: 'microsoft' } },
  });
  if (!account) return null;

  // Auto-refresh jika kedaluwarsa dalam 5 menit
  if (account.expiresAt.getTime() < Date.now() + 5 * 60_000 && account.refreshTokenEnc) {
    const refreshToken = decryptSecret(account.refreshTokenEnc);
    const form = new URLSearchParams({
      client_id: env.MICROSOFT_CLIENT_ID,
      client_secret: env.MICROSOFT_CLIENT_SECRET,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
      scope: MICROSOFT_SCOPES.join(' '),
    });
    const refreshed = await exchangeMicrosoftToken(form);
    const newAccessToken = refreshed.access_token!;
    await prisma.oAuthAccount.update({
      where: { id: account.id },
      data: {
        accessTokenEnc: encryptSecret(newAccessToken),
        refreshTokenEnc: refreshed.refresh_token
          ? encryptSecret(refreshed.refresh_token)
          : account.refreshTokenEnc,
        expiresAt: new Date(Date.now() + (refreshed.expires_in ?? 3600) * 1000),
      },
    });
    return newAccessToken;
  }

  return decryptSecret(account.accessTokenEnc);
}

interface GraphEvent {
  id: string;
  subject?: string;
  bodyPreview?: string;
  location?: { displayName?: string };
  start?: { dateTime: string; timeZone: string };
  end?: { dateTime: string; timeZone: string };
  isAllDay?: boolean;
  onlineMeeting?: { joinUrl?: string };
  webLink?: string;
}

export async function syncMicrosoftCalendarEvents(
  userId: string,
  timeMin: Date,
  timeMax: Date,
): Promise<CalendarEventDTO[]> {
  const accessToken = await getValidMicrosoftAccessToken(userId);
  if (!accessToken) return [];

  const params = new URLSearchParams({
    startDateTime: timeMin.toISOString(),
    endDateTime: timeMax.toISOString(),
    $orderby: 'start/dateTime',
    $top: '50',
  });

  const res = await fetch(
    `https://graph.microsoft.com/v1.0/me/calendarView?${params.toString()}`,
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Prefer: 'outlook.timezone="UTC"',
      },
    },
  );

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Microsoft Graph calendarView error (${res.status}): ${errText}`);
  }

  const payload = (await res.json()) as { value?: GraphEvent[] };
  const events = payload.value ?? [];
  const results: CalendarEventDTO[] = [];

  for (const item of events) {
    if (!item.id || !item.start?.dateTime) continue;
    const startIso = item.start.dateTime.endsWith('Z')
      ? item.start.dateTime
      : `${item.start.dateTime}Z`;
    const endIso = item.end?.dateTime
      ? item.end.dateTime.endsWith('Z')
        ? item.end.dateTime
        : `${item.end.dateTime}Z`
      : new Date(new Date(startIso).getTime() + 3600_000).toISOString();

    const startAt = new Date(startIso);
    const endAt = new Date(endIso);

    const saved = await prisma.calendarEventCache.upsert({
      where: {
        userId_provider_externalId: {
          userId,
          provider: 'microsoft',
          externalId: item.id,
        },
      },
      update: {
        title: item.subject ?? '(Tanpa Judul)',
        description: item.bodyPreview ?? null,
        location: item.location?.displayName ?? null,
        startAt,
        endAt,
        isAllDay: Boolean(item.isAllDay),
        meetingLink: item.onlineMeeting?.joinUrl ?? item.webLink ?? null,
        syncedAt: new Date(),
      },
      create: {
        userId,
        provider: 'microsoft',
        externalId: item.id,
        title: item.subject ?? '(Tanpa Judul)',
        description: item.bodyPreview ?? null,
        location: item.location?.displayName ?? null,
        startAt,
        endAt,
        isAllDay: Boolean(item.isAllDay),
        meetingLink: item.onlineMeeting?.joinUrl ?? item.webLink ?? null,
      },
    });

    results.push({
      id: saved.id,
      externalId: saved.externalId,
      provider: 'microsoft',
      sourceBadge: 'Microsoft Outlook',
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

export async function createMicrosoftCalendarEvent(params: {
  userId: string;
  title: string;
  description?: string;
  location?: string;
  startAt: Date;
  endAt: Date;
  timeZone: string;
}): Promise<CalendarEventDTO> {
  const accessToken = await getValidMicrosoftAccessToken(params.userId);
  if (!accessToken) {
    throw new Error('Akun Microsoft Outlook belum terhubung.');
  }

  const res = await fetch('https://graph.microsoft.com/v1.0/me/events', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      subject: params.title,
      body: {
        contentType: 'Text',
        content: params.description ?? '',
      },
      location: params.location ? { displayName: params.location } : undefined,
      start: {
        dateTime: params.startAt.toISOString().replace('Z', ''),
        timeZone: 'UTC',
      },
      end: {
        dateTime: params.endAt.toISOString().replace('Z', ''),
        timeZone: 'UTC',
      },
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gagal membuat acara Outlook (${res.status}): ${errText}`);
  }

  const created = (await res.json()) as GraphEvent;
  const externalId = created.id ?? `ms-${Date.now()}`;

  const cached = await prisma.calendarEventCache.upsert({
    where: {
      userId_provider_externalId: {
        userId: params.userId,
        provider: 'microsoft',
        externalId,
      },
    },
    update: {
      title: params.title,
      description: params.description ?? null,
      location: params.location ?? null,
      startAt: params.startAt,
      endAt: params.endAt,
      meetingLink: created.onlineMeeting?.joinUrl ?? created.webLink ?? null,
      syncedAt: new Date(),
    },
    create: {
      userId: params.userId,
      provider: 'microsoft',
      externalId,
      title: params.title,
      description: params.description ?? null,
      location: params.location ?? null,
      startAt: params.startAt,
      endAt: params.endAt,
      isAllDay: false,
      meetingLink: created.onlineMeeting?.joinUrl ?? created.webLink ?? null,
    },
  });

  return {
    id: cached.id,
    externalId: cached.externalId,
    provider: 'microsoft',
    sourceBadge: 'Microsoft Outlook',
    title: cached.title,
    description: cached.description,
    location: cached.location,
    startAt: cached.startAt.toISOString(),
    endAt: cached.endAt.toISOString(),
    isAllDay: cached.isAllDay,
    meetingLink: cached.meetingLink,
  };
}
