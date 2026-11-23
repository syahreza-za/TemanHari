import crypto from 'crypto';
import { env } from '../config/env';

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12;

function getEncryptionKey(): Buffer {
  const raw = env.TOKEN_ENCRYPTION_KEY.trim();
  if (/^[0-9a-fA-F]{64}$/.test(raw)) {
    return Buffer.from(raw, 'hex');
  }
  return crypto.createHash('sha256').update(raw).digest();
}

/**
 * Mengenkripsi string sensitif (seperti OAuth access/refresh token) menggunakan AES-256-GCM.
 * Format hasil: ivHex:authTagHex:cipherTextHex
 */
export function encryptSecret(plainText: string): string {
  const iv = crypto.randomBytes(IV_LENGTH);
  const key = getEncryptionKey();
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
  const encrypted = Buffer.concat([cipher.update(plainText, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted.toString('hex')}`;
}

/**
 * Mendekripsi string hasil `encryptSecret`.
 */
export function decryptSecret(cipherPayload: string): string {
  const parts = cipherPayload.split(':');
  if (parts.length !== 3) {
    throw new Error('Format token terenkripsi tidak valid');
  }
  const [ivHex, authTagHex, encryptedHex] = parts;
  const iv = Buffer.from(ivHex, 'hex');
  const authTag = Buffer.from(authTagHex, 'hex');
  const encrypted = Buffer.from(encryptedHex, 'hex');
  const key = getEncryptionKey();

  const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(authTag);
  const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
  return decrypted.toString('utf8');
}

/**
 * Menghasilkan ID notifikasi integer 32-bit positif yang aman untuk Android AlarmManager.
 */
export function generateNotificationId(): number {
  return crypto.randomInt(10000, 2147483000);
}
