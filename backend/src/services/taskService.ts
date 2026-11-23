import { Task } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { generateNotificationId } from '../lib/crypto';

export interface CreateTaskInput {
  userId: string;
  title: string;
  notes?: string | null;
  dueAt?: Date | null;
  remindAt?: Date | null;
  priority?: 'low' | 'medium' | 'high';
  category?: 'pribadi' | 'kerja' | 'kesehatan' | 'belanja' | 'lainnya';
  recurrence?: 'none' | 'daily' | 'weekly' | 'monthly';
}

export interface UpdateTaskInput {
  title?: string;
  notes?: string | null;
  dueAt?: Date | null;
  remindAt?: Date | null;
  priority?: 'low' | 'medium' | 'high';
  category?: 'pribadi' | 'kerja' | 'kesehatan' | 'belanja' | 'lainnya';
  recurrence?: 'none' | 'daily' | 'weekly' | 'monthly';
  isCompleted?: boolean;
}

function advanceDateByRecurrence(
  base: Date,
  recurrence: string,
): Date {
  const next = new Date(base);
  switch (recurrence) {
    case 'daily':
      next.setDate(next.getDate() + 1);
      break;
    case 'weekly':
      next.setDate(next.getDate() + 7);
      break;
    case 'monthly':
      next.setMonth(next.getMonth() + 1);
      break;
    default:
      break;
  }
  return next;
}

export async function listTasks(
  userId: string,
  options?: { includeCompleted?: boolean; from?: Date; to?: Date },
): Promise<Task[]> {
  return prisma.task.findMany({
    where: {
      userId,
      ...(options?.includeCompleted === false ? { isCompleted: false } : {}),
      ...(options?.from || options?.to
        ? {
            dueAt: {
              ...(options.from ? { gte: options.from } : {}),
              ...(options.to ? { lte: options.to } : {}),
            },
          }
        : {}),
    },
    orderBy: [{ isCompleted: 'asc' }, { dueAt: 'asc' }, { createdAt: 'desc' }],
  });
}

export async function createTask(input: CreateTaskInput): Promise<Task> {
  const dueAt = input.dueAt ?? null;
  const remindAt = input.remindAt ?? dueAt;

  return prisma.task.create({
    data: {
      userId: input.userId,
      title: input.title.trim(),
      notes: input.notes?.trim() || null,
      dueAt,
      remindAt,
      priority: input.priority ?? 'medium',
      category: input.category ?? 'pribadi',
      recurrence: input.recurrence ?? 'none',
      notificationId: generateNotificationId(),
    },
  });
}

export async function updateTask(
  userId: string,
  taskId: string,
  input: UpdateTaskInput,
): Promise<Task | null> {
  const existing = await prisma.task.findFirst({
    where: { id: taskId, userId },
  });
  if (!existing) return null;

  const isCompleted = input.isCompleted ?? existing.isCompleted;
  return prisma.task.update({
    where: { id: existing.id },
    data: {
      title: input.title !== undefined ? input.title.trim() : undefined,
      notes: input.notes !== undefined ? input.notes : undefined,
      dueAt: input.dueAt !== undefined ? input.dueAt : undefined,
      remindAt: input.remindAt !== undefined ? input.remindAt : undefined,
      priority: input.priority,
      category: input.category,
      recurrence: input.recurrence,
      isCompleted,
      completedAt:
        input.isCompleted !== undefined
          ? input.isCompleted
            ? new Date()
            : null
          : undefined,
    },
  });
}

/**
 * Menandai tugas selesai. Jika tugas bersifat berulang (daily/weekly/monthly),
 * otomatis membuat jadwal berikutnya agar pengingat rutin tidak terputus.
 */
export async function completeTask(
  userId: string,
  taskId: string,
): Promise<{ completedTask: Task; nextRecurringTask: Task | null } | null> {
  const existing = await prisma.task.findFirst({
    where: { id: taskId, userId },
  });
  if (!existing) return null;

  const completedTask = await prisma.task.update({
    where: { id: existing.id },
    data: {
      isCompleted: true,
      completedAt: new Date(),
    },
  });

  let nextRecurringTask: Task | null = null;
  if (existing.recurrence !== 'none' && !existing.isCompleted) {
    const baseDue = existing.dueAt ?? new Date();
    const nextDue = advanceDateByRecurrence(baseDue, existing.recurrence);
    const nextRemind = existing.remindAt
      ? advanceDateByRecurrence(existing.remindAt, existing.recurrence)
      : nextDue;

    nextRecurringTask = await prisma.task.create({
      data: {
        userId,
        title: existing.title,
        notes: existing.notes,
        dueAt: nextDue,
        remindAt: nextRemind,
        priority: existing.priority,
        category: existing.category,
        recurrence: existing.recurrence,
        notificationId: generateNotificationId(),
      },
    });
  }

  return { completedTask, nextRecurringTask };
}

export async function snoozeTask(
  userId: string,
  taskId: string,
  minutes = 10,
): Promise<Task | null> {
  const existing = await prisma.task.findFirst({
    where: { id: taskId, userId },
  });
  if (!existing) return null;

  const snoozedTime = new Date(Date.now() + minutes * 60_000);
  return prisma.task.update({
    where: { id: existing.id },
    data: {
      remindAt: snoozedTime,
      isCompleted: false,
      completedAt: null,
    },
  });
}

export async function deleteTask(userId: string, taskId: string): Promise<boolean> {
  const deleted = await prisma.task.deleteMany({
    where: { id: taskId, userId },
  });
  return deleted.count > 0;
}

export async function completeTaskByTitleMatch(
  userId: string,
  query: string,
): Promise<{ completedTask: Task; nextRecurringTask: Task | null } | null> {
  const activeTasks = await prisma.task.findMany({
    where: { userId, isCompleted: false },
    orderBy: { dueAt: 'asc' },
  });

  const normalized = query.toLowerCase().trim();
  const matched = activeTasks.find((t) =>
    t.title.toLowerCase().includes(normalized),
  );
  if (!matched) return null;
  return completeTask(userId, matched.id);
}
