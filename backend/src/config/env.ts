import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const envSchema = z.object({
  PORT: z.coerce.number().default(4000),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  APP_BASE_URL: z.string().url().default('http://localhost:4000'),
  MOBILE_DEEP_LINK_SCHEME: z.string().default('temanhari://auth-callback'),
  DATABASE_URL: z.string().default('file:./dev.db'),

  JWT_SECRET: z
    .string()
    .min(16)
    .default('temanhari-dev-jwt-secret-change-in-production-32chars'),
  TOKEN_ENCRYPTION_KEY: z
    .string()
    .min(32)
    .default('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'),

  GEMINI_API_KEY: z.string().optional().default(''),
  GEMINI_MODEL: z.string().default('gemini-2.5-flash'),

  GOOGLE_CLIENT_ID: z.string().optional().default(''),
  GOOGLE_CLIENT_SECRET: z.string().optional().default(''),
  GOOGLE_REDIRECT_URI: z
    .string()
    .optional()
    .default('http://localhost:4000/api/calendar/google/callback'),

  MICROSOFT_CLIENT_ID: z.string().optional().default(''),
  MICROSOFT_CLIENT_SECRET: z.string().optional().default(''),
  MICROSOFT_TENANT_ID: z.string().optional().default('common'),
  MICROSOFT_REDIRECT_URI: z
    .string()
    .optional()
    .default('http://localhost:4000/api/calendar/microsoft/callback'),

  FIREBASE_SERVICE_ACCOUNT_PATH: z.string().optional().default(''),
  FIREBASE_PROJECT_ID: z.string().optional().default(''),
  FIREBASE_CLIENT_EMAIL: z.string().optional().default(''),
  FIREBASE_PRIVATE_KEY: z.string().optional().default(''),
});

export const env = envSchema.parse(process.env);

export const capabilities = {
  gemini: Boolean(env.GEMINI_API_KEY.trim()),
  googleOAuth: Boolean(env.GOOGLE_CLIENT_ID.trim() && env.GOOGLE_CLIENT_SECRET.trim()),
  microsoftOAuth: Boolean(env.MICROSOFT_CLIENT_ID.trim() && env.MICROSOFT_CLIENT_SECRET.trim()),
  firebase: Boolean(
    env.FIREBASE_SERVICE_ACCOUNT_PATH.trim() ||
      (env.FIREBASE_PROJECT_ID.trim() &&
        env.FIREBASE_CLIENT_EMAIL.trim() &&
        env.FIREBASE_PRIVATE_KEY.trim()),
  ),
};
