import cors from 'cors';
import express, { NextFunction, Request, Response } from 'express';
import helmet from 'helmet';
import { ZodError } from 'zod';
import { capabilities } from './config/env';
import authRoutes from './routes/authRoutes';
import calendarRoutes from './routes/calendarRoutes';
import chatRoutes from './routes/chatRoutes';
import notificationRoutes from './routes/notificationRoutes';
import taskRoutes from './routes/taskRoutes';

export function createApp() {
  const app = express();

  app.use(helmet());
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));

  app.get('/health', (_req, res) => {
    res.json({
      status: 'ok',
      service: 'temanhari-backend',
      timestamp: new Date().toISOString(),
      capabilities,
    });
  });

  app.use('/api/auth', authRoutes);
  app.use('/api/tasks', taskRoutes);
  app.use('/api/calendar', calendarRoutes);
  app.use('/api/chat', chatRoutes);
  app.use('/api/notifications', notificationRoutes);

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof ZodError) {
      res.status(400).json({
        error: 'Validasi data gagal.',
        details: err.flatten(),
      });
      return;
    }

    const message =
      err instanceof Error ? err.message : 'Terjadi kesalahan internal pada server.';
    console.error('[Error]', err);
    res.status(500).json({ error: message });
  });

  return app;
}
