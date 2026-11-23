import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { AuthenticatedRequest, requireAuth } from '../middleware/auth';
import {
  generateProactiveGreeting,
  streamCompanionReply,
} from '../services/ai/aiService';

const router = Router();
router.use(requireAuth);

const sendMessageSchema = z.object({
  message: z.string().min(1).max(4000),
  moodTag: z.string().max(40).optional(),
});

router.get('/history', async (req: AuthenticatedRequest, res, next) => {
  try {
    const messages = await prisma.chatMessage.findMany({
      where: { userId: req.userId! },
      orderBy: { createdAt: 'asc' },
      take: 60,
    });
    res.json({
      messages: messages.map((m) => ({
        id: m.id,
        role: m.role,
        content: m.content,
        moodTag: m.moodTag,
        toolArtifacts: m.toolCallsJson ? JSON.parse(m.toolCallsJson) : [],
        createdAt: m.createdAt.toISOString(),
      })),
    });
  } catch (err) {
    next(err);
  }
});

router.get('/greeting', async (req: AuthenticatedRequest, res, next) => {
  try {
    const data = await generateProactiveGreeting(req.userId!);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/chat/stream
 * Mengirimkan balasan teman AI secara real-time melalui Server-Sent Events (SSE).
 * Event types:
 * - `delta`: { text: string }
 * - `tool`: ToolExecutionArtifact (mis. tugas baru yang harus segera dijadwalkan notifikasinya di HP)
 * - `done`: { messageId: string, fullText: string, artifacts: ToolExecutionArtifact[] }
 * - `error`: { message: string }
 */
router.post('/stream', async (req: AuthenticatedRequest, res) => {
  let parsed;
  try {
    parsed = sendMessageSchema.parse(req.body);
  } catch (err) {
    res.status(400).json({ error: 'Pesan tidak valid.', details: err });
    return;
  }

  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders?.();

  const sendEvent = (event: string, data: unknown) => {
    if (!res.writableEnded) {
      res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    }
  };

  try {
    const result = await streamCompanionReply({
      userId: req.userId!,
      userMessage: parsed.message,
      moodTag: parsed.moodTag,
      callbacks: {
        onChunk: (text) => sendEvent('delta', { text }),
        onToolExecuted: (artifact) => sendEvent('tool', artifact),
      },
    });

    sendEvent('done', {
      messageId: result.assistantMessageId,
      fullText: result.fullText,
      artifacts: result.artifacts,
    });
  } catch (err) {
    const msg =
      err instanceof Error ? err.message : 'Terjadi kendala saat memproses obrolan.';
    sendEvent('error', { message: msg });
  } finally {
    if (!res.writableEnded) {
      res.end();
    }
  }
});

router.delete('/history', async (req: AuthenticatedRequest, res, next) => {
  try {
    await prisma.chatMessage.deleteMany({
      where: { userId: req.userId! },
    });
    res.json({ cleared: true });
  } catch (err) {
    next(err);
  }
});

export default router;
