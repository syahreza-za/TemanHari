import { Content, GoogleGenAI, Part } from '@google/genai';
import { capabilities, env } from '../../config/env';
import { prisma } from '../../lib/prisma';
import {
  formatIndonesianTime,
  getGreetingByHour,
  getTimePartsInZone,
} from '../../lib/time';
import { getUnifiedAgenda } from '../calendar/unifiedAgendaService';
import {
  buildCrisisSafeResponse,
  buildSystemPrompt,
  detectEmotionalCrisis,
} from './promptBuilder';
import {
  executeGeminiTool,
  geminiToolDeclarations,
  ToolExecutionArtifact,
} from './tools';

export interface StreamCallbacks {
  onChunk: (text: string) => void;
  onToolExecuted: (artifact: ToolExecutionArtifact) => void;
}

export interface ChatTurnResult {
  assistantMessageId: string;
  fullText: string;
  artifacts: ToolExecutionArtifact[];
}

/**
 * Ekstraktor pengingat berbasis aturan Indonesia untuk Mode Demo / Fallback
 * saat GEMINI_API_KEY belum diisi, sehingga fitur tambah tugas dari obrolan tetap bekerja nyata.
 */
function extractTasksFromIndonesianMessage(
  message: string,
  now: Date,
): Array<{ title: string; dueAt: Date; category: 'pribadi' | 'kerja' | 'kesehatan' }> {
  const lower = message.toLowerCase();
  const triggerPattern = /(ingetin|ingatkan|catat|tambah tugas|buat pengingat|jangan lupa)/i;
  if (!triggerPattern.test(lower)) return [];

  const clauses = message
    .split(/\s+(?:dan|lalu|terus|sama)\s+|,\s*/i)
    .map((c) => c.trim())
    .filter((c) => c.length > 3);

  const isTomorrow = /\bbesok\b/i.test(lower);
  const extracted: Array<{
    title: string;
    dueAt: Date;
    category: 'pribadi' | 'kerja' | 'kesehatan';
  }> = [];

  for (const clause of clauses) {
    const timeMatch = clause.match(
      /(?:jam|pukul)\s*(\d{1,2})(?:[.:](\d{2}))?\s*(pagi|siang|sore|malam)?/i,
    );
    if (!timeMatch) continue;

    let hour = Number(timeMatch[1]);
    const minute = timeMatch[2] ? Number(timeMatch[2]) : 0;
    const period = (timeMatch[3] || '').toLowerCase();

    if ((period === 'malam' || period === 'sore') && hour < 12) {
      hour += 12;
    } else if (period === 'siang' && hour < 11) {
      hour += 12;
    } else if (period === 'pagi' && hour === 12) {
      hour = 0;
    }

    const due = new Date(now);
    if (isTomorrow || /\bbesok\b/i.test(clause)) {
      due.setDate(due.getDate() + 1);
    }
    due.setHours(hour, minute, 0, 0);
    if (!isTomorrow && due.getTime() <= now.getTime()) {
      due.setDate(due.getDate() + 1);
    }

    let cleanedTitle = clause
      .replace(/(?:tolong\s+)?(?:ingetin|ingatkan|catat|buat pengingat|jangan lupa)\s*/gi, '')
      .replace(/\b(?:besok|hari ini|nanti|ya|dong|deh|aku|saya|untuk)\b/gi, '')
      .replace(/(?:jam|pukul)\s*\d{1,2}(?:[.:]\d{2})?\s*(?:pagi|siang|sore|malam)?/gi, '')
      .replace(/\s+/g, ' ')
      .trim();

    if (!cleanedTitle) cleanedTitle = 'Pengingat dari Obrolan';
    cleanedTitle = cleanedTitle.charAt(0).toUpperCase() + cleanedTitle.slice(1);

    const category: 'pribadi' | 'kerja' | 'kesehatan' =
      /(vitamin|obat|minum air|olahraga|dokter|tidur)/i.test(cleanedTitle)
        ? 'kesehatan'
        : /(laporan|meeting|rapat|klien|email|presentasi|kerja)/i.test(cleanedTitle)
          ? 'kerja'
          : 'pribadi';

    extracted.push({ title: cleanedTitle, dueAt: due, category });
  }

  return extracted;
}

async function runDemoFallbackChat(params: {
  userId: string;
  nickname: string;
  persona: string;
  timezone: string;
  userMessage: string;
  callbacks: StreamCallbacks;
}): Promise<{ fullText: string; artifacts: ToolExecutionArtifact[] }> {
  const { userId, nickname, persona, timezone, userMessage, callbacks } = params;
  const artifacts: ToolExecutionArtifact[] = [];
  const lower = userMessage.toLowerCase();

  // 1. Cek apakah pengguna minta membuat tugas/pengingat
  const parsedTasks = extractTasksFromIndonesianMessage(userMessage, new Date());
  if (parsedTasks.length > 0) {
    const confirmations: string[] = [];
    for (const t of parsedTasks) {
      const exec = await executeGeminiTool(userId, 'create_task', {
        title: t.title,
        dueAtIso: t.dueAt.toISOString(),
        category: t.category,
        priority: 'medium',
      });
      artifacts.push(exec.artifact);
      callbacks.onToolExecuted(exec.artifact);
      confirmations.push(
        `• **${t.title}** pukul ${formatIndonesianTime(t.dueAt, timezone)}`,
      );
    }

    const reply =
      `Siap, ${nickname}! Sudah aku catat dan pasang pengingatnya di HP-mu ya:\n` +
      `${confirmations.join('\n')}\n\n` +
      `Tenang aja, nanti notifikasinya bakal bunyi tepat waktu walau layar HP sedang mati. Ada hal lain yang lagi ada di pikiranmu?`;
    await streamSimulatedText(reply, callbacks.onChunk);
    return { fullText: reply, artifacts };
  }

  // 2. Cek apakah menanyakan jadwal hari ini
  if (/(jadwal|agenda|hari ini ada apa|rapat|meeting)/i.test(lower)) {
    const exec = await executeGeminiTool(userId, 'list_today_agenda', {});
    artifacts.push(exec.artifact);
    callbacks.onToolExecuted(exec.artifact);
    const agenda = await getUnifiedAgenda(userId);
    const lines = agenda.items
      .slice(0, 6)
      .map(
        (i) =>
          `• ${i.isAllDay ? 'Hari ini' : formatIndonesianTime(new Date(i.startAt), timezone)} — ${i.title} (${i.sourceBadge})${i.hasConflict ? ' ⚠️ Bentrok' : ''}`,
      );

    const reply =
      lines.length > 0
        ? `Ini rangkuman agenda kamu hari ini, ${nickname}:\n${lines.join('\n')}` +
          (agenda.conflictCount > 0
            ? `\n\nEh, kelihatannya ada ${agenda.conflictCount} jadwal yang waktunya bertumpuk nih. Mau aku bantu atur prioritasnya?`
            : `\n\nSemoga semuanya berjalan lancar ya! Jangan lupa selipkan jeda istirahat sebentar.`)
        : `Hari ini agenda kamu terlihat cukup lengang, ${nickname}. Cocok banget buat istirahat atau menyelesaikan hal kecil yang sempat tertunda.`;

    await streamSimulatedText(reply, callbacks.onChunk);
    return { fullText: reply, artifacts };
  }

  // 3. Respons empatik sesuai persona
  let reply: string;
  if (/(capek|lelah|burnout|pusing|stres|berat)/i.test(lower)) {
    const exec = await executeGeminiTool(userId, 'log_mood_checkin', {
      mood: 'lelah',
      score: 2,
      note: userMessage.slice(0, 120),
    });
    artifacts.push(exec.artifact);
    callbacks.onToolExecuted(exec.artifact);
    reply =
      persona === 'tenang'
        ? `Tarik napas pelan dulu ya, ${nickname}. Wajar banget kalau tubuh dan pikiranmu terasa lelah setelah melewati banyak hal. Kamu tidak harus menyelesaikan semuanya malam ini — mau cerita bagian mana yang paling bikin kamu capek?`
        : `Peluk jauh buat kamu, ${nickname}. Kelihatannya hari ini cukup menguras tenaga ya. Yuk istirahat sejenak, minum air putih, dan kalau mau curhat panjang lebar aku di sini siap dengerin kok.`;
  } else if (/(sendiri|kesepian|sepi|bosan|temenin)/i.test(lower)) {
    reply =
      `Aku di sini nemenin kamu, ${nickname}. Kadang suasana sepi memang terasa agak berat, tapi kamu nggak sendirian sekarang. Lagi pengen ngobrol santai soal apa nih — cerita hari ini, bahas hal random, atau sekadar ditemani sambil santai?`;
  } else if (persona === 'ceria') {
    reply =
      `Hai ${nickname}! Senang banget kamu mampir ngobrol sama aku. Ceritain dong apa yang lagi seru atau lagi kamu kerjakan sekarang — kalau ada yang perlu aku ingetin, tinggal bilang aja ya!`;
  } else if (persona === 'tenang') {
    reply =
      `Aku mendengarkan, ${nickname}. Terima kasih sudah berbagi denganku. Pelan-pelan saja, bagaimana perasaanmu saat ini, dan adakah hal kecil yang bisa kita rapikan bersama hari ini?`;
  } else {
    reply =
      `Halo ${nickname}, aku dengerin kok! Cerita aja santai — mau curhat, bahas rencanamu hari ini, atau minta tolong aku pasang pengingat tugas juga bisa banget. Gimana kabarmu sekarang?`;
  }

  await streamSimulatedText(reply, callbacks.onChunk);
  return { fullText: reply, artifacts };
}

async function streamSimulatedText(
  text: string,
  onChunk: (chunk: string) => void,
): Promise<void> {
  const words = text.split(/(\s+)/);
  for (let i = 0; i < words.length; i += 3) {
    const piece = words.slice(i, i + 3).join('');
    onChunk(piece);
    await new Promise((r) => setTimeout(r, 15));
  }
}

/**
 * Mengirim pesan ke Gemini (`@google/genai`) dengan Streaming SSE & multi-turn Function Calling.
 */
export async function streamCompanionReply(params: {
  userId: string;
  userMessage: string;
  moodTag?: string;
  callbacks: StreamCallbacks;
}): Promise<ChatTurnResult> {
  const { userId, userMessage, moodTag, callbacks } = params;

  const user = await prisma.user.findUniqueOrThrow({ where: { id: userId } });

  // Simpan pesan user terlebih dahulu
  await prisma.chatMessage.create({
    data: {
      userId,
      role: 'user',
      content: userMessage,
      moodTag: moodTag ?? null,
    },
  });

  // Guardrail krisis emosional prioritas tertinggi
  if (detectEmotionalCrisis(userMessage)) {
    const safeText = buildCrisisSafeResponse(user.nickname);
    await streamSimulatedText(safeText, callbacks.onChunk);
    const saved = await prisma.chatMessage.create({
      data: {
        userId,
        role: 'assistant',
        content: safeText,
        moodTag: 'crisis_support',
      },
    });
    return {
      assistantMessageId: saved.id,
      fullText: safeText,
      artifacts: [],
    };
  }

  // Jika GEMINI_API_KEY belum disetel, gunakan Smart Indonesian Demo AI Fallback
  if (!capabilities.gemini) {
    const fallback = await runDemoFallbackChat({
      userId,
      nickname: user.nickname,
      persona: user.aiPersona,
      timezone: user.timezone,
      userMessage,
      callbacks,
    });

    const saved = await prisma.chatMessage.create({
      data: {
        userId,
        role: 'assistant',
        content: fallback.fullText,
        toolCallsJson:
          fallback.artifacts.length > 0
            ? JSON.stringify(fallback.artifacts)
            : null,
      },
    });

    return {
      assistantMessageId: saved.id,
      fullText: fallback.fullText,
      artifacts: fallback.artifacts,
    };
  }

  // Muat konteks: memori pribadi, mood terakhir, agenda hari ini, dan 16 pesan terakhir
  const [memories, latestMood, agenda, recentMessages] = await Promise.all([
    prisma.userMemory.findMany({
      where: { userId },
      orderBy: [{ importance: 'desc' }, { updatedAt: 'desc' }],
      take: 20,
    }),
    prisma.moodEntry.findFirst({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    }),
    getUnifiedAgenda(userId),
    prisma.chatMessage.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 16,
    }),
  ]);

  const systemInstruction = buildSystemPrompt({
    user,
    memories,
    latestMood,
    agenda,
  });

  const history: Content[] = recentMessages
    .reverse()
    .map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));

  const ai = new GoogleGenAI({ apiKey: env.GEMINI_API_KEY });
  const artifacts: ToolExecutionArtifact[] = [];
  let fullText = '';

  const contents: Content[] = [...history];

  // Loop hingga 4 ronde function calling untuk mendukung beberapa tool sekaligus
  for (let round = 0; round < 4; round++) {
    const stream = await ai.models.generateContentStream({
      model: env.GEMINI_MODEL,
      contents,
      config: {
        systemInstruction,
        temperature: 0.75,
        tools: [{ functionDeclarations: geminiToolDeclarations }],
      },
    });

    const roundFunctionCalls: Array<{
      name: string;
      args: Record<string, unknown>;
    }> = [];
    let roundText = '';

    for await (const chunk of stream) {
      if (chunk.text) {
        roundText += chunk.text;
        fullText += chunk.text;
        callbacks.onChunk(chunk.text);
      }
      if (chunk.functionCalls && chunk.functionCalls.length > 0) {
        for (const fc of chunk.functionCalls) {
          if (fc.name) {
            roundFunctionCalls.push({
              name: fc.name,
              args: (fc.args as Record<string, unknown>) ?? {},
            });
          }
        }
      }
    }

    if (roundFunctionCalls.length === 0) {
      break;
    }

    // Tambahkan model turn (teks + functionCall parts) ke percakapan
    const modelParts: Part[] = [];
    if (roundText) modelParts.push({ text: roundText });
    for (const fc of roundFunctionCalls) {
      modelParts.push({
        functionCall: {
          name: fc.name,
          args: fc.args,
        },
      });
    }
    contents.push({ role: 'model', parts: modelParts });

    // Jalankan semua tool dan kirim kembali sebagai functionResponse
    const responseParts: Part[] = [];
    for (const fc of roundFunctionCalls) {
      const executed = await executeGeminiTool(userId, fc.name, fc.args);
      artifacts.push(executed.artifact);
      callbacks.onToolExecuted(executed.artifact);
      responseParts.push({
        functionResponse: {
          name: fc.name,
          response: executed.result,
        },
      });
    }
    contents.push({ role: 'user', parts: responseParts });
  }

  if (!fullText.trim()) {
    fullText = `Sudah aku bereskan ya, ${user.nickname}! Ada lagi yang bisa aku bantu?`;
    callbacks.onChunk(fullText);
  }

  const saved = await prisma.chatMessage.create({
    data: {
      userId,
      role: 'assistant',
      content: fullText,
      toolCallsJson: artifacts.length > 0 ? JSON.stringify(artifacts) : null,
    },
  });

  return {
    assistantMessageId: saved.id,
    fullText,
    artifacts,
  };
}

/**
 * Menghasilkan sapaan hangat proaktif yang kontekstual terhadap jam & agenda hari ini.
 */
export async function generateProactiveGreeting(userId: string): Promise<{
  greeting: string;
  upcomingTitle: string | null;
  pendingTaskCount: number;
}> {
  const [user, agenda] = await Promise.all([
    prisma.user.findUniqueOrThrow({ where: { id: userId } }),
    getUnifiedAgenda(userId),
  ]);

  const now = new Date();
  const { hour } = getTimePartsInZone(now, user.timezone);
  const timeGreeting = getGreetingByHour(hour);

  const upcomingEvent = agenda.items.find(
    (item) => item.kind === 'event' && new Date(item.startAt).getTime() > now.getTime(),
  );
  const pendingTasks = agenda.items.filter(
    (item) => item.kind === 'task' && !item.isCompleted,
  );

  let extra = '';
  if (upcomingEvent) {
    extra = ` Sebentar lagi ada "${upcomingEvent.title}" jam ${formatIndonesianTime(new Date(upcomingEvent.startAt), user.timezone)} — semangat ya!`;
  } else if (pendingTasks.length > 0) {
    extra = ` Hari ini ada ${pendingTasks.length} tugas ringan yang bisa kita selesaikan pelan-pelan.`;
  } else {
    extra = ' Gimana perasaanmu hari ini? Cerita aja kalau butuh teman ngobrol.';
  }

  return {
    greeting: `${timeGreeting}, ${user.nickname}!${extra}`,
    upcomingTitle: upcomingEvent?.title ?? null,
    pendingTaskCount: pendingTasks.length,
  };
}
