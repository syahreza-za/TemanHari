import { capabilities, env } from './config/env';
import { prisma } from './lib/prisma';
import { startBackgroundSchedulers } from './jobs/scheduler';
import { initFirebaseAdmin } from './services/notificationService';
import { createApp } from './app';

async function bootstrap() {
  await prisma.$connect();
  initFirebaseAdmin();

  const app = createApp();
  startBackgroundSchedulers();

  const server = app.listen(env.PORT, () => {
    console.info(`==========================================================`);
    console.info(`  TemanHari Backend berjalan di http://localhost:${env.PORT}`);
    console.info(`  Gemini AI       : ${capabilities.gemini ? 'AKTIF' : 'Mode Demo Fallback'}`);
    console.info(`  Google Calendar : ${capabilities.googleOAuth ? 'SIAP OAuth' : 'Mode Demo'}`);
    console.info(`  Outlook Graph   : ${capabilities.microsoftOAuth ? 'SIAP OAuth' : 'Mode Demo'}`);
    console.info(`  Firebase FCM    : ${capabilities.firebase ? 'AKTIF' : 'Simulasi Log'}`);
    console.info(`==========================================================`);
  });

  const shutdown = async () => {
    console.info('\n[Server] Menutup server dengan aman...');
    server.close(async () => {
      await prisma.$disconnect();
      process.exit(0);
    });
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

bootstrap().catch((err) => {
  console.error('[Fatal] Gagal menjalankan backend:', err);
  process.exit(1);
});
