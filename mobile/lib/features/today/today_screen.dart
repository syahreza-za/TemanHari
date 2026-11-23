import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/agenda_provider.dart';
import 'widgets/add_item_sheet.dart';
import 'widgets/agenda_card.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agendaState = ref.watch(agendaProvider);
    final agenda = agendaState.agenda;
    final scheme = Theme.of(context).colorScheme;
    final dateTitle =
        DateFormat('EEEE, d MMMM', 'id_ID').format(agendaState.selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hari Ini', style: TextStyle(fontSize: 19)),
            Text(
              dateTitle,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pilih tanggal',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: agendaState.selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 60)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                await ref.read(agendaProvider.notifier).selectDate(picked);
              }
            },
            icon: const Icon(Icons.calendar_month_rounded),
          ),
          IconButton(
            tooltip: 'Sinkronkan Google & Outlook',
            onPressed: agendaState.isSyncing
                ? null
                : () =>
                    ref.read(agendaProvider.notifier).loadAgenda(forceSync: true),
            icon: agendaState.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => AddItemSheet(initialDate: agendaState.selectedDate),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(agendaProvider.notifier).loadAgenda(forceSync: true),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (agenda != null && agenda.demoMode)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Mode Demo aktif: menampilkan simulasi jadwal Outlook & Google Calendar.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (agenda != null && agenda.conflictCount > 0)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.conflictCoral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.conflictCoral.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.conflictCoral,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Terdeteksi ${agenda.conflictCount} jadwal yang saling tumpang tindih hari ini. Cek kartu bertanda merah di bawah ya.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.conflictCoral,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  _FilterPill(
                    label: 'Semua',
                    selected: agendaState.activeFilter == 'all',
                    onTap: () => ref.read(agendaProvider.notifier).setFilter('all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: 'Tugas',
                    selected: agendaState.activeFilter == 'task',
                    onTap: () => ref.read(agendaProvider.notifier).setFilter('task'),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: 'Outlook',
                    selected: agendaState.activeFilter == 'microsoft',
                    onTap: () =>
                        ref.read(agendaProvider.notifier).setFilter('microsoft'),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: 'Google',
                    selected: agendaState.activeFilter == 'google',
                    onTap: () =>
                        ref.read(agendaProvider.notifier).setFilter('google'),
                  ),
                ],
              ),
            ),
            if (agendaState.isLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (agendaState.filteredItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                child: Column(
                  children: [
                    Icon(
                      Icons.spa_rounded,
                      size: 56,
                      color: scheme.primary.withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Belum ada jadwal atau tugas untuk tampilan ini',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tekan tombol Tambah atau cukup ceritakan rencanamu di tab Ngobrol.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              )
            else
              ...agendaState.filteredItems.map((item) {
                return AgendaCard(
                  item: item,
                  onToggleComplete: item.isTask
                      ? () => ref.read(agendaProvider.notifier).completeTask(
                            item.id,
                            notificationId: item.notificationId,
                          )
                      : null,
                  onSnooze: (item.isTask && item.notificationId != null)
                      ? () async {
                          await ref.read(agendaProvider.notifier).snoozeTask(
                                taskId: item.id,
                                title: item.title,
                                notificationId: item.notificationId!,
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Pengingat "${item.title}" ditunda 10 menit.',
                                ),
                              ),
                            );
                          }
                        }
                      : null,
                  onDelete: item.isTask
                      ? () => ref.read(agendaProvider.notifier).deleteTask(
                            item.id,
                            notificationId: item.notificationId,
                          )
                      : null,
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }
}
