import { FunctionDeclaration, Type } from '@google/genai';
import { prisma } from '../../lib/prisma';
import {
  completeTask,
  completeTaskByTitleMatch,
  createTask,
} from '../taskService';
import {
  createEventOnProvider,
  getUnifiedAgenda,
} from '../calendar/unifiedAgendaService';

export const geminiToolDeclarations: FunctionDeclaration[] = [
  {
    name: 'create_task',
    description:
      'Membuat tugas harian atau pengingat baru untuk pengguna beserta jadwal notifikasi lokal di HP Android/iOS. Panggil tool ini setiap kali pengguna meminta diingatkan atau mencatat tugas.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        title: {
          type: Type.STRING,
          description: 'Judul singkat dan jelas untuk tugas/pengingat, misal: "Kirim laporan bulanan" atau "Minum vitamin".',
        },
        notes: {
          type: Type.STRING,
          description: 'Catatan tambahan opsional untuk tugas.',
        },
        dueAtIso: {
          type: Type.STRING,
          description:
            'Waktu jatuh tempo/pengingat dalam format ISO 8601 lengkap dengan zona waktu (contoh: 2026-11-24T08:00:00+07:00). Wajib dihitung relatif terhadap waktu sekarang.',
        },
        priority: {
          type: Type.STRING,
          enum: ['low', 'medium', 'high'],
          description: 'Tingkat prioritas tugas.',
        },
        category: {
          type: Type.STRING,
          enum: ['pribadi', 'kerja', 'kesehatan', 'belanja', 'lainnya'],
          description: 'Kategori tugas.',
        },
        recurrence: {
          type: Type.STRING,
          enum: ['none', 'daily', 'weekly', 'monthly'],
          description: 'Frekuensi pengulangan tugas rutin.',
        },
      },
      required: ['title'],
    },
  },
  {
    name: 'list_today_agenda',
    description:
      'Mengambil daftar lengkap agenda gabungan hari ini atau tanggal tertentu (Google Calendar, Microsoft Outlook, dan Tugas Harian) termasuk informasi bentrok jadwal.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        dateIso: {
          type: Type.STRING,
          description: 'Tanggal target dalam format YYYY-MM-DD (opsional, default hari ini).',
        },
      },
    },
  },
  {
    name: 'complete_task',
    description:
      'Menandai sebuah tugas harian sebagai selesai berdasarkan ID tugas atau kecocokan judul.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        taskId: {
          type: Type.STRING,
          description: 'ID tugas jika diketahui.',
        },
        titleQuery: {
          type: Type.STRING,
          description: 'Kata kunci judul tugas jika ID tidak diketahui.',
        },
      },
    },
  },
  {
    name: 'save_user_memory',
    description:
      'Menyimpan fakta pribadi, preferensi, rutinitas, atau hal penting yang diceritakan pengguna agar diingat pada percakapan berikutnya.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        key: {
          type: Type.STRING,
          description: 'Kunci unik singkat (snake_case), misal: "minuman_favorit", "jam_olahraga", "nama_kucing".',
        },
        category: {
          type: Type.STRING,
          enum: ['preference', 'routine', 'fact', 'relationship', 'emotion'],
          description: 'Kategori memori pribadi.',
        },
        content: {
          type: Type.STRING,
          description: 'Ringkasan fakta atau preferensi pengguna dalam 1 kalimat singkat.',
        },
        importance: {
          type: Type.INTEGER,
          description: 'Skor kepentingan 1 (rendah) sampai 5 (sangat penting).',
        },
      },
      required: ['key', 'content'],
    },
  },
  {
    name: 'create_calendar_event',
    description:
      'Membuat acara baru di kalender Google Calendar atau Microsoft Outlook pengguna.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        provider: {
          type: Type.STRING,
          enum: ['google', 'microsoft'],
          description: 'Kalender tujuan: "google" atau "microsoft".',
        },
        title: {
          type: Type.STRING,
          description: 'Judul acara/rapat.',
        },
        startAtIso: {
          type: Type.STRING,
          description: 'Waktu mulai ISO 8601 lengkap dengan offset zona waktu.',
        },
        endAtIso: {
          type: Type.STRING,
          description: 'Waktu selesai ISO 8601 lengkap (default +1 jam dari startAtIso bila tidak disebut).',
        },
        location: {
          type: Type.STRING,
          description: 'Lokasi acara atau tautan rapat.',
        },
        description: {
          type: Type.STRING,
          description: 'Deskripsi singkat acara.',
        },
      },
      required: ['provider', 'title', 'startAtIso'],
    },
  },
  {
    name: 'log_mood_checkin',
    description:
      'Mencatat suasana hati (mood) pengguna ketika mereka membagikan perasaannya.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        mood: {
          type: Type.STRING,
          enum: ['senang', 'tenang', 'semangat', 'lelah', 'cemas', 'sedih'],
          description: 'Label perasaan pengguna.',
        },
        score: {
          type: Type.INTEGER,
          description: 'Skor suasana hati 1 (sangat berat) sampai 5 (sangat baik).',
        },
        note: {
          type: Type.STRING,
          description: 'Catatan singkat tentang pemicu atau konteks perasaan.',
        },
      },
      required: ['mood', 'score'],
    },
  },
];

export interface ToolExecutionArtifact {
  toolName: string;
  success: boolean;
  summary: string;
  createdTask?: {
    id: string;
    title: string;
    notes: string | null;
    dueAt: string | null;
    remindAt: string | null;
    priority: string;
    category: string;
    recurrence: string;
    notificationId: number;
    isCompleted: boolean;
  };
  completedTaskId?: string;
  createdEvent?: {
    id: string;
    title: string;
    provider: string;
    startAt: string;
    endAt: string;
  };
}

export async function executeGeminiTool(
  userId: string,
  name: string,
  args: Record<string, unknown>,
): Promise<{ result: Record<string, unknown>; artifact: ToolExecutionArtifact }> {
  try {
    switch (name) {
      case 'create_task': {
        const title = String(args.title ?? '').trim();
        if (!title) {
          throw new Error('Judul tugas tidak boleh kosong.');
        }
        const dueAt = args.dueAtIso ? new Date(String(args.dueAtIso)) : null;
        const safeDueAt = dueAt && !Number.isNaN(dueAt.getTime()) ? dueAt : null;

        const task = await createTask({
          userId,
          title,
          notes: args.notes ? String(args.notes) : null,
          dueAt: safeDueAt,
          remindAt: safeDueAt,
          priority: (args.priority as 'low' | 'medium' | 'high') ?? 'medium',
          category:
            (args.category as
              | 'pribadi'
              | 'kerja'
              | 'kesehatan'
              | 'belanja'
              | 'lainnya') ?? 'pribadi',
          recurrence:
            (args.recurrence as 'none' | 'daily' | 'weekly' | 'monthly') ?? 'none',
        });

        const dto = {
          id: task.id,
          title: task.title,
          notes: task.notes,
          dueAt: task.dueAt?.toISOString() ?? null,
          remindAt: task.remindAt?.toISOString() ?? null,
          priority: task.priority,
          category: task.category,
          recurrence: task.recurrence,
          notificationId: task.notificationId,
          isCompleted: task.isCompleted,
        };

        return {
          result: { status: 'created', task: dto },
          artifact: {
            toolName: name,
            success: true,
            summary: `Tugas "${task.title}" dijadwalkan`,
            createdTask: dto,
          },
        };
      }

      case 'list_today_agenda': {
        const agenda = await getUnifiedAgenda(userId, {
          date: args.dateIso ? String(args.dateIso) : undefined,
        });
        return {
          result: {
            date: agenda.date,
            conflictCount: agenda.conflictCount,
            items: agenda.items.map((i) => ({
              id: i.id,
              kind: i.kind,
              source: i.sourceBadge,
              title: i.title,
              startAt: i.startAt,
              endAt: i.endAt,
              isCompleted: i.isCompleted,
              hasConflict: i.hasConflict,
            })),
          },
          artifact: {
            toolName: name,
            success: true,
            summary: `Memuat ${agenda.items.length} agenda untuk ${agenda.date}`,
          },
        };
      }

      case 'complete_task': {
        const taskId = args.taskId ? String(args.taskId) : '';
        const titleQuery = args.titleQuery ? String(args.titleQuery) : '';
        const done = taskId
          ? await completeTask(userId, taskId)
          : await completeTaskByTitleMatch(userId, titleQuery);

        if (!done) {
          return {
            result: { status: 'not_found', message: 'Tugas aktif tidak ditemukan.' },
            artifact: {
              toolName: name,
              success: false,
              summary: 'Tugas tidak ditemukan',
            },
          };
        }

        return {
          result: {
            status: 'completed',
            taskTitle: done.completedTask.title,
            nextRecurringDueAt: done.nextRecurringTask?.dueAt?.toISOString() ?? null,
          },
          artifact: {
            toolName: name,
            success: true,
            summary: `Tugas "${done.completedTask.title}" ditandai selesai`,
            completedTaskId: done.completedTask.id,
          },
        };
      }

      case 'save_user_memory': {
        const key = String(args.key ?? '')
          .toLowerCase()
          .replace(/[^a-z0-9_]+/g, '_')
          .slice(0, 64);
        const content = String(args.content ?? '').trim();
        const category = String(args.category ?? 'fact');
        const importance = Math.min(5, Math.max(1, Number(args.importance ?? 3)));

        if (!key || !content) {
          throw new Error('Key dan content memori wajib diisi.');
        }

        await prisma.userMemory.upsert({
          where: { userId_key: { userId, key } },
          update: { content, category, importance },
          create: { userId, key, content, category, importance },
        });

        return {
          result: { status: 'saved', key, content },
          artifact: {
            toolName: name,
            success: true,
            summary: `Mengingat: ${content}`,
          },
        };
      }

      case 'create_calendar_event': {
        const provider =
          args.provider === 'microsoft' ? 'microsoft' : 'google';
        const title = String(args.title ?? '').trim();
        const startAt = new Date(String(args.startAtIso));
        if (Number.isNaN(startAt.getTime())) {
          throw new Error('Format startAtIso tidak valid.');
        }
        const endAt = args.endAtIso
          ? new Date(String(args.endAtIso))
          : new Date(startAt.getTime() + 60 * 60_000);

        const created = await createEventOnProvider({
          userId,
          provider,
          title,
          description: args.description ? String(args.description) : undefined,
          location: args.location ? String(args.location) : undefined,
          startAt,
          endAt: Number.isNaN(endAt.getTime())
            ? new Date(startAt.getTime() + 60 * 60_000)
            : endAt,
        });

        return {
          result: { status: 'created', event: created },
          artifact: {
            toolName: name,
            success: true,
            summary: `Acara "${created.title}" ditambahkan ke ${created.sourceBadge}`,
            createdEvent: {
              id: created.id,
              title: created.title,
              provider: created.provider,
              startAt: created.startAt,
              endAt: created.endAt,
            },
          },
        };
      }

      case 'log_mood_checkin': {
        const mood = String(args.mood ?? 'tenang');
        const score = Math.min(5, Math.max(1, Number(args.score ?? 3)));
        const note = args.note ? String(args.note) : null;

        await prisma.moodEntry.create({
          data: { userId, mood, score, note },
        });

        return {
          result: { status: 'logged', mood, score },
          artifact: {
            toolName: name,
            success: true,
            summary: `Mood "${mood}" tercatat`,
          },
        };
      }

      default:
        return {
          result: { error: `Tool ${name} tidak dikenali.` },
          artifact: {
            toolName: name,
            success: false,
            summary: `Tool ${name} tidak dikenal`,
          },
        };
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Gagal menjalankan tool.';
    return {
      result: { error: message },
      artifact: {
        toolName: name,
        success: false,
        summary: message,
      },
    };
  }
}
