import { describe, expect, it } from 'vitest';
import { decryptSecret, encryptSecret } from '../src/lib/crypto';
import { isWithinQuietHours } from '../src/lib/time';
import { detectEmotionalCrisis } from '../src/services/ai/promptBuilder';
import {
  detectScheduleConflicts,
  UnifiedAgendaItem,
} from '../src/services/calendar/unifiedAgendaService';

describe('TemanHari Backend Core Logic', () => {
  it('encrypts and decrypts OAuth tokens with AES-256-GCM', () => {
    const token = 'ya29.a0AfH6SMBx-super-secret-oauth-token';
    const encrypted = encryptSecret(token);
    expect(encrypted).not.toContain(token);
    expect(encrypted.split(':')).toHaveLength(3);
    expect(decryptSecret(encrypted)).toBe(token);
  });

  it('evaluates overnight Quiet Hours correctly', () => {
    const lateNight = new Date('2026-11-23T16:30:00Z'); // 23:30 WIB (UTC+7)
    const afternoon = new Date('2026-11-23T07:00:00Z'); // 14:00 WIB (UTC+7)

    expect(
      isWithinQuietHours({
        enabled: true,
        quietStart: '22:00',
        quietEnd: '06:30',
        timeZone: 'Asia/Jakarta',
        now: lateNight,
      }),
    ).toBe(true);

    expect(
      isWithinQuietHours({
        enabled: true,
        quietStart: '22:00',
        quietEnd: '06:30',
        timeZone: 'Asia/Jakarta',
        now: afternoon,
      }),
    ).toBe(false);
  });

  it('detects overlapping calendar events between Google and Outlook', () => {
    const items: UnifiedAgendaItem[] = [
      {
        id: 'ev-1',
        kind: 'event',
        source: 'google',
        sourceBadge: 'Google Calendar',
        title: 'Review Klien',
        description: null,
        location: null,
        startAt: '2026-11-23T06:30:00.000Z',
        endAt: '2026-11-23T07:30:00.000Z',
        isAllDay: false,
        isCompleted: false,
        priority: null,
        category: null,
        recurrence: null,
        notificationId: null,
        meetingLink: null,
        hasConflict: false,
        conflictWithIds: [],
      },
      {
        id: 'ev-2',
        kind: 'event',
        source: 'microsoft',
        sourceBadge: 'Microsoft Outlook',
        title: '1-on-1 Lead',
        description: null,
        location: null,
        startAt: '2026-11-23T07:00:00.000Z',
        endAt: '2026-11-23T08:00:00.000Z',
        isAllDay: false,
        isCompleted: false,
        priority: null,
        category: null,
        recurrence: null,
        notificationId: null,
        meetingLink: null,
        hasConflict: false,
        conflictWithIds: [],
      },
    ];

    const checked = detectScheduleConflicts(items);
    expect(checked[0].hasConflict).toBe(true);
    expect(checked[0].conflictWithIds).toContain('ev-2');
    expect(checked[1].hasConflict).toBe(true);
    expect(checked[1].conflictWithIds).toContain('ev-1');
  });

  it('triggers crisis safety guardrail for self-harm expressions', () => {
    expect(detectEmotionalCrisis('aku capek banget hari ini')).toBe(false);
    expect(detectEmotionalCrisis('aku pengen mati rasanya')).toBe(true);
  });
});
