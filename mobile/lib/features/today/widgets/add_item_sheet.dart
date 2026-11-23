import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/agenda_provider.dart';

class AddItemSheet extends ConsumerStatefulWidget {
  const AddItemSheet({super.key, required this.initialDate});

  final DateTime initialDate;

  @override
  ConsumerState<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<AddItemSheet> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _locationController = TextEditingController();

  String _mode = 'task'; // task | event
  String _calendarProvider = 'google';
  String _priority = 'medium';
  String _category = 'pribadi';
  String _recurrence = 'none';
  late DateTime _selectedDate;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    final nextHour = DateTime.now().add(const Duration(hours: 1));
    _selectedTime = TimeOfDay(hour: nextHour.hour, minute: 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  DateTime _combineDateTime() {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final start = _combineDateTime();
      if (_mode == 'task') {
        await ref.read(agendaProvider.notifier).createTask(
              title: title,
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
              dueAt: start,
              priority: _priority,
              category: _category,
              recurrence: _recurrence,
            );
      } else {
        await ref.read(agendaProvider.notifier).createCalendarEvent(
              provider: _calendarProvider,
              title: title,
              description: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
              location: _locationController.text.trim().isEmpty
                  ? null
                  : _locationController.text.trim(),
              startAt: start,
              endAt: start.add(const Duration(hours: 1)),
            );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tambah Agenda Baru',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'task',
                  icon: Icon(Icons.alarm_add_rounded),
                  label: Text('Tugas & Pengingat'),
                ),
                ButtonSegment(
                  value: 'event',
                  icon: Icon(Icons.event_rounded),
                  label: Text('Acara Kalender'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _mode == 'task' ? 'Judul tugas / pengingat' : 'Judul acara',
                hintText: _mode == 'task'
                    ? 'Contoh: Minum vitamin malam'
                    : 'Contoh: Diskusi desain produk',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
            if (_mode == 'event') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Lokasi / Tautan rapat (opsional)',
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'google', label: Text('Google Calendar')),
                  ButtonSegment(value: 'microsoft', label: Text('Microsoft Outlook')),
                ],
                selected: {_calendarProvider},
                onSelectionChanged: (v) =>
                    setState(() => _calendarProvider = v.first),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null) setState(() => _selectedTime = picked);
                    },
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(_selectedTime.format(context)),
                  ),
                ),
              ],
            ),
            if (_mode == 'task') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _priority,
                      decoration: const InputDecoration(labelText: 'Prioritas'),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Rendah')),
                        DropdownMenuItem(value: 'medium', child: Text('Sedang')),
                        DropdownMenuItem(value: 'high', child: Text('Tinggi')),
                      ],
                      onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _recurrence,
                      decoration: const InputDecoration(labelText: 'Pengulangan'),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('Sekali')),
                        DropdownMenuItem(value: 'daily', child: Text('Harian')),
                        DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
                        DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
                      ],
                      onChanged: (v) => setState(() => _recurrence = v ?? 'none'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: const [
                  DropdownMenuItem(value: 'pribadi', child: Text('Pribadi')),
                  DropdownMenuItem(value: 'kerja', child: Text('Pekerjaan')),
                  DropdownMenuItem(value: 'kesehatan', child: Text('Kesehatan')),
                  DropdownMenuItem(value: 'belanja', child: Text('Belanja')),
                  DropdownMenuItem(value: 'lainnya', child: Text('Lainnya')),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'pribadi'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _mode == 'task'
                    ? 'Simpan & Pasang Pengingat'
                    : 'Simpan ke Kalender',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
