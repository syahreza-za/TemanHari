import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/agenda_item.dart';

class AgendaCard extends StatelessWidget {
  const AgendaCard({
    super.key,
    required this.item,
    this.onToggleComplete,
    this.onSnooze,
    this.onDelete,
  });

  final UnifiedAgendaItem item;
  final VoidCallback? onToggleComplete;
  final VoidCallback? onSnooze;
  final VoidCallback? onDelete;

  Color _badgeColor() {
    switch (item.source) {
      case 'microsoft':
        return AppTheme.outlookBlue;
      case 'google':
        return AppTheme.googleGreen;
      default:
        return AppTheme.taskAmber;
    }
  }

  IconData _sourceIcon() {
    switch (item.source) {
      case 'microsoft':
        return Icons.mail_outline_rounded;
      case 'google':
        return Icons.calendar_today_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  String _timeLabel() {
    if (item.isAllDay) return 'Sepanjang hari';
    final start = DateFormat('HH:mm').format(item.startAt.toLocal());
    if (item.endAt != null) {
      final end = DateFormat('HH:mm').format(item.endAt!.toLocal());
      return '$start – $end';
    }
    return start;
  }

  String _recurrenceLabel(String? recurrence) {
    switch (recurrence) {
      case 'daily':
        return 'Harian';
      case 'weekly':
        return 'Mingguan';
      case 'monthly':
        return 'Bulanan';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _badgeColor();
    final recurrenceText = _recurrenceLabel(item.recurrence);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: item.hasConflict
              ? AppTheme.conflictCoral.withValues(alpha: 0.75)
              : scheme.outlineVariant.withValues(alpha: 0.35),
          width: item.hasConflict ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.isTask)
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 2),
                child: Checkbox(
                  value: item.isCompleted,
                  shape: const CircleBorder(),
                  onChanged: (_) => onToggleComplete?.call(),
                ),
              )
            else
              Container(
                width: 4,
                height: 54,
                margin: const EdgeInsets.only(right: 12, top: 4),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_sourceIcon(), size: 12, color: accent),
                            const SizedBox(width: 4),
                            Text(
                              item.sourceBadge,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _timeLabel(),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      if (recurrenceText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '↻ $recurrenceText',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      if (item.hasConflict)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.conflictCoral.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 13,
                                color: AppTheme.conflictCoral,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Bentrok Jadwal',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.conflictCoral,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: item.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.isCompleted
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                  ),
                  if (item.description != null &&
                      item.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (item.location != null && item.location!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (item.isTask && !item.isCompleted) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (onSnooze != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: onSnooze,
                            icon: const Icon(Icons.snooze_rounded, size: 16),
                            label: const Text('Tunda 10 mnt'),
                          ),
                        const Spacer(),
                        if (onDelete != null)
                          IconButton(
                            tooltip: 'Hapus tugas',
                            visualDensity: VisualDensity.compact,
                            onPressed: onDelete,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
