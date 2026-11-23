/**
 * Utilitas waktu & zona waktu untuk pengecekan Jam Tenang (Quiet Hours) dan format tanggal Indonesia.
 */

export function getTimePartsInZone(date: Date, timeZone: string): {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
} {
  let validZone = timeZone || 'Asia/Jakarta';
  try {
    Intl.DateTimeFormat('en-US', { timeZone: validZone });
  } catch {
    validZone = 'Asia/Jakarta';
  }

  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: validZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });

  const parts = formatter.formatToParts(date);
  const lookup = (type: string): number =>
    Number(parts.find((p) => p.type === type)?.value ?? '0');

  return {
    year: lookup('year'),
    month: lookup('month'),
    day: lookup('day'),
    hour: lookup('hour'),
    minute: lookup('minute'),
  };
}

function parseMinutesOfDay(hhmm: string): number {
  const [h, m] = hhmm.split(':').map((n) => Number(n));
  if (Number.isNaN(h) || Number.isNaN(m)) return 0;
  return h * 60 + m;
}

/**
 * Memeriksa apakah waktu `now` berada dalam rentang Jam Tenang pengguna.
 * Mendukung rentang lintas tengah malam (misal 22:00 - 06:30).
 */
export function isWithinQuietHours(params: {
  enabled: boolean;
  quietStart: string;
  quietEnd: string;
  timeZone: string;
  now?: Date;
}): boolean {
  if (!params.enabled) return false;
  const now = params.now ?? new Date();
  const { hour, minute } = getTimePartsInZone(now, params.timeZone);
  const currentMinutes = hour * 60 + minute;
  const startMinutes = parseMinutesOfDay(params.quietStart);
  const endMinutes = parseMinutesOfDay(params.quietEnd);

  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) {
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }
  // Lintas tengah malam, contoh: 22:00 s.d. 06:30
  return currentMinutes >= startMinutes || currentMinutes < endMinutes;
}

export function getDayRange(dateStr?: string): { start: Date; end: Date } {
  const base = dateStr ? new Date(dateStr) : new Date();
  const safeBase = Number.isNaN(base.getTime()) ? new Date() : base;
  const start = new Date(safeBase);
  start.setHours(0, 0, 0, 0);
  const end = new Date(safeBase);
  end.setHours(23, 59, 59, 999);
  return { start, end };
}

export function formatIndonesianTime(date: Date, timeZone = 'Asia/Jakarta'): string {
  try {
    return new Intl.DateTimeFormat('id-ID', {
      timeZone,
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).format(date);
  } catch {
    return date.toTimeString().slice(0, 5);
  }
}

export function formatIndonesianDateTime(date: Date, timeZone = 'Asia/Jakarta'): string {
  try {
    return new Intl.DateTimeFormat('id-ID', {
      timeZone,
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).format(date);
  } catch {
    return date.toISOString();
  }
}

export function getGreetingByHour(hour: number): string {
  if (hour >= 4 && hour < 11) return 'Selamat pagi';
  if (hour >= 11 && hour < 15) return 'Selamat siang';
  if (hour >= 15 && hour < 18) return 'Selamat sore';
  return 'Selamat malam';
}
