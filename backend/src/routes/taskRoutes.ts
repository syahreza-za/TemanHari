import { Router } from 'express';
import { z } from 'zod';
import { AuthenticatedRequest, requireAuth } from '../middleware/auth';
import {
  completeTask,
  createTask,
  deleteTask,
  listTasks,
  snoozeTask,
  updateTask,
} from '../services/taskService';

const router = Router();
router.use(requireAuth);

const createTaskSchema = z.object({
  title: z.string().min(1).max(200),
  notes: z.string().max(1000).nullable().optional(),
  dueAt: z.string().datetime({ offset: true }).nullable().optional(),
  remindAt: z.string().datetime({ offset: true }).nullable().optional(),
  priority: z.enum(['low', 'medium', 'high']).optional(),
  category: z
    .enum(['pribadi', 'kerja', 'kesehatan', 'belanja', 'lainnya'])
    .optional(),
  recurrence: z.enum(['none', 'daily', 'weekly', 'monthly']).optional(),
});

const updateTaskSchema = createTaskSchema.partial().extend({
  isCompleted: z.boolean().optional(),
});

router.get('/', async (req: AuthenticatedRequest, res, next) => {
  try {
    const includeCompleted = req.query.includeCompleted !== 'false';
    const tasks = await listTasks(req.userId!, { includeCompleted });
    res.json({ tasks });
  } catch (err) {
    next(err);
  }
});

router.post('/', async (req: AuthenticatedRequest, res, next) => {
  try {
    const parsed = createTaskSchema.parse(req.body);
    const task = await createTask({
      userId: req.userId!,
      title: parsed.title,
      notes: parsed.notes,
      dueAt: parsed.dueAt ? new Date(parsed.dueAt) : null,
      remindAt: parsed.remindAt ? new Date(parsed.remindAt) : null,
      priority: parsed.priority,
      category: parsed.category,
      recurrence: parsed.recurrence,
    });
    res.status(201).json({ task });
  } catch (err) {
    next(err);
  }
});

router.patch('/:taskId', async (req: AuthenticatedRequest, res, next) => {
  try {
    const parsed = updateTaskSchema.parse(req.body);
    const updated = await updateTask(req.userId!, String(req.params.taskId), {
      title: parsed.title,
      notes: parsed.notes,
      dueAt:
        parsed.dueAt === undefined
          ? undefined
          : parsed.dueAt
            ? new Date(parsed.dueAt)
            : null,
      remindAt:
        parsed.remindAt === undefined
          ? undefined
          : parsed.remindAt
            ? new Date(parsed.remindAt)
            : null,
      priority: parsed.priority,
      category: parsed.category,
      recurrence: parsed.recurrence,
      isCompleted: parsed.isCompleted,
    });

    if (!updated) {
      res.status(404).json({ error: 'Tugas tidak ditemukan.' });
      return;
    }
    res.json({ task: updated });
  } catch (err) {
    next(err);
  }
});

router.post('/:taskId/complete', async (req: AuthenticatedRequest, res, next) => {
  try {
    const result = await completeTask(req.userId!, String(req.params.taskId));
    if (!result) {
      res.status(404).json({ error: 'Tugas tidak ditemukan.' });
      return;
    }
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.post('/:taskId/snooze', async (req: AuthenticatedRequest, res, next) => {
  try {
    const minutes = z.coerce
      .number()
      .int()
      .min(1)
      .max(240)
      .default(10)
      .parse(req.body?.minutes ?? 10);
    const task = await snoozeTask(req.userId!, String(req.params.taskId), minutes);
    if (!task) {
      res.status(404).json({ error: 'Tugas tidak ditemukan.' });
      return;
    }
    res.json({ task });
  } catch (err) {
    next(err);
  }
});

router.delete('/:taskId', async (req: AuthenticatedRequest, res, next) => {
  try {
    const deleted = await deleteTask(req.userId!, String(req.params.taskId));
    if (!deleted) {
      res.status(404).json({ error: 'Tugas tidak ditemukan.' });
      return;
    }
    res.json({ deleted: true });
  } catch (err) {
    next(err);
  }
});

export default router;
