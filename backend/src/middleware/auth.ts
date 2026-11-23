import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { prisma } from '../lib/prisma';

export interface AuthTokenPayload {
  userId: string;
  deviceKey: string;
}

export interface OAuthStatePayload {
  userId: string;
  provider: 'google' | 'microsoft';
  redirectScheme: string;
}

export interface AuthenticatedRequest extends Request {
  userId?: string;
}

export function signAuthToken(payload: AuthTokenPayload): string {
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: '90d' });
}

export function verifyAuthToken(token: string): AuthTokenPayload {
  return jwt.verify(token, env.JWT_SECRET) as AuthTokenPayload;
}

export function signOAuthState(payload: OAuthStatePayload): string {
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: '15m' });
}

export function verifyOAuthState(stateToken: string): OAuthStatePayload {
  return jwt.verify(stateToken, env.JWT_SECRET) as OAuthStatePayload;
}

export async function requireAuth(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    const authHeader = req.headers.authorization;
    const queryToken = typeof req.query.token === 'string' ? req.query.token : undefined;
    const rawToken = authHeader?.startsWith('Bearer ')
      ? authHeader.slice(7).trim()
      : queryToken;

    if (!rawToken) {
      res.status(401).json({ error: 'Token autentikasi diperlukan.' });
      return;
    }

    const decoded = verifyAuthToken(rawToken);
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      select: { id: true },
    });

    if (!user) {
      res.status(401).json({ error: 'Sesi pengguna tidak ditemukan.' });
      return;
    }

    req.userId = user.id;
    next();
  } catch {
    res.status(401).json({ error: 'Token tidak valid atau sudah kedaluwarsa.' });
  }
}
