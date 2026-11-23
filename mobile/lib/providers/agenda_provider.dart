import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/network/api_client.dart';
import '../core/storage/local_cache.dart';
import '../models/agenda_item.dart';
import '../models/task_item.dart';
import '../models/user_profile.dart';
import '../services/notification_service.dart';
import 'app_providers.dart';

class AgendaState {
  const AgendaState({
    required this.selectedDate,
    this.agenda,
    this.isLoading = false,
    this.isSyncing = false,
    this.errorMessage,
    this.activeFilter = 'all', // all | google | microsoft | task
  });

  final DateTime selectedDate;
  final UnifiedAgendaResponse? agenda;
  final bool isLoading;
  final bool isSyncing;
  final String? errorMessage;
  final String activeFilter;

  List<UnifiedAgendaItem> get filteredItems {
    final items = agenda?.items ?? const [];
    if (activeFilter == 'all') return items;
    return items.where((i) => i.source == activeFilter).toList();
  }

  AgendaState copyWith({
    DateTime? selectedDate,
    UnifiedAgendaResponse? agenda,
    bool? isLoading,
    bool? isSyncing,
    String? errorMessage,
    bool clearError = false,
    String? activeFilter,
  }) {
    return AgendaState(
      selectedDate: selectedDate ?? this.selectedDate,
      agenda: agenda ?? this.agenda,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activeFilter: activeFilter ?? this.activeFilter,
    );
  }
}

class AgendaNotifier extends StateNotifier<AgendaState> {
  AgendaNotifier({
    required ApiClient apiClient,
    required LocalCacheService cache,
    required NotificationService notificationService,
  })  : _apiClient = apiClient,
        _cache = cache,
        _notificationService = notificationService,
        super(
          AgendaState(
            selectedDate: DateTime.now(),
            agenda: cache.getCachedAgenda(),
          ),
        ) {
    _actionSub = _notificationService.onAction.listen(_handleNotificationAction);
  }

  final ApiClient _apiClient;
  final LocalCacheService _cache;
  final NotificationService _notificationService;
  StreamSubscription<NotificationActionEvent>? _actionSub;

  @override
  void dispose() {
    _actionSub?.cancel();
    super.dispose();
  }

  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }

  Future<void> selectDate(DateTime date) async {
    state = state.copyWith(selectedDate: date);
    await loadAgenda();
  }

  Future<void> _handleNotificationAction(NotificationActionEvent event) async {
    if (event.taskId.isEmpty || event.taskId == 'demo-test') return;
    if (event.actionId == kActionMarkDone) {
      await completeTask(event.taskId);
    } else if (event.actionId == kActionSnooze10) {
      await snoozeTask(
        taskId: event.taskId,
        title: event.title,
        notificationId: event.notificationId,
      );
    }
  }

  Future<void> loadAgenda({bool forceSync = false}) async {
    state = state.copyWith(
      isLoading: state.agenda == null,
      isSyncing: forceSync,
      clearError: true,
    );

    final dateStr = state.selectedDate.toIso8601String().substring(0, 10);

    try {
      // Sinkronkan terlebih dahulu tugas yang dibuat saat offline
      await _syncPendingOfflineTasks();

      final res = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/calendar/agenda',
        queryParameters: {
          'date': dateStr,
          if (forceSync) 'sync': 'true',
        },
      );

      final parsed = UnifiedAgendaResponse.fromJson(res.data ?? const {});
      await _cache.saveCachedAgenda(parsed);

      // Pastikan semua tugas aktif terjadwal di AlarmManager lokal HP
      for (final item in parsed.items) {
        if (item.isTask && !item.isCompleted && item.notificationId != null) {
          await _notificationService.scheduleTaskReminder(
            TaskItem(
              id: item.id,
              title: item.title,
              notes: item.description,
              dueAt: item.isAllDay ? null : item.startAt,
              remindAt: item.isAllDay ? null : item.startAt,
              priority: item.priority ?? 'medium',
              category: item.category ?? 'pribadi',
              recurrence: item.recurrence ?? 'none',
              isCompleted: item.isCompleted,
              notificationId: item.notificationId!,
            ),
          );
        }
      }

      state = state.copyWith(
        agenda: parsed,
        isLoading: false,
        isSyncing: false,
      );
    } catch (e) {
      debugPrint('[Agenda] Menggunakan cache offline: $e');
      final fallback = _buildOfflineFallbackAgenda(dateStr);
      state = state.copyWith(
        agenda: state.agenda ?? fallback,
        isLoading: false,
        isSyncing: false,
        errorMessage: 'Menampilkan data offline. Tarik ke bawah untuk sinkronisasi ulang.',
      );
    }
  }

  UnifiedAgendaResponse _buildOfflineFallbackAgenda(String dateStr) {
    final offlineTasks = _cache.getOfflineTasks();
    final items = offlineTasks
        .map(
          (t) => UnifiedAgendaItem(
            id: t.id,
            kind: 'task',
            source: 'task',
            sourceBadge: 'Tugas Harian',
            title: t.title,
            description: t.notes,
            startAt: t.dueAt ?? DateTime.now(),
            isAllDay: t.dueAt == null,
            isCompleted: t.isCompleted,
            priority: t.priority,
            category: t.category,
            recurrence: t.recurrence,
            notificationId: t.notificationId,
          ),
        )
        .toList();

    return UnifiedAgendaResponse(
      date: dateStr,
      demoMode: true,
      connectedProviders: ConnectedProviders.empty(),
      conflictCount: 0,
      items: items,
    );
  }

  Future<void> _syncPendingOfflineTasks() async {
    final offline = _cache.getOfflineTasks();
    final pending = offline.where((t) => t.pendingSync).toList();
    if (pending.isEmpty) return;

    final remaining = <TaskItem>[];
    for (final task in offline) {
      if (!task.pendingSync) {
        remaining.add(task);
        continue;
      }
      try {
        await _apiClient.dio.post(
          '/api/tasks',
          data: {
            'title': task.title,
            'notes': task.notes,
            'dueAt': task.dueAt?.toIso8601String(),
            'remindAt': task.remindAt?.toIso8601String(),
            'priority': task.priority,
            'category': task.category,
            'recurrence': task.recurrence,
          },
        );
      } catch (_) {
        remaining.add(task);
      }
    }
    await _cache.saveOfflineTasks(remaining);
  }

  Future<TaskItem> createTask({
    required String title,
    String? notes,
    DateTime? dueAt,
    String priority = 'medium',
    String category = 'pribadi',
    String recurrence = 'none',
  }) async {
    await _notificationService.requestPermissions();

    try {
      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/tasks',
        data: {
          'title': title,
          'notes': notes,
          'dueAt': dueAt?.toUtc().toIso8601String(),
          'remindAt': dueAt?.toUtc().toIso8601String(),
          'priority': priority,
          'category': category,
          'recurrence': recurrence,
        },
      );
      final task = TaskItem.fromJson(
        Map<String, dynamic>.from((res.data?['task'] as Map?) ?? const {}),
      );
      await _notificationService.scheduleTaskReminder(task);
      await loadAgenda();
      return task;
    } catch (_) {
      // Offline-first: simpan secara lokal & tetap pasang alarm di HP
      final localTask = TaskItem(
        id: 'local-${const Uuid().v4()}',
        title: title,
        notes: notes,
        dueAt: dueAt,
        remindAt: dueAt,
        priority: priority,
        category: category,
        recurrence: recurrence,
        notificationId: Random().nextInt(1999999999) + 10000,
        pendingSync: true,
      );
      final updatedList = [..._cache.getOfflineTasks(), localTask];
      await _cache.saveOfflineTasks(updatedList);
      await _notificationService.scheduleTaskReminder(localTask);

      final currentAgenda = state.agenda ??
          _buildOfflineFallbackAgenda(
            state.selectedDate.toIso8601String().substring(0, 10),
          );
      final newAgendaItem = UnifiedAgendaItem(
        id: localTask.id,
        kind: 'task',
        source: 'task',
        sourceBadge: 'Tugas Harian',
        title: localTask.title,
        description: localTask.notes,
        startAt: localTask.dueAt ?? DateTime.now(),
        isAllDay: localTask.dueAt == null,
        priority: localTask.priority,
        category: localTask.category,
        recurrence: localTask.recurrence,
        notificationId: localTask.notificationId,
      );
      final updatedAgenda = UnifiedAgendaResponse(
        date: currentAgenda.date,
        demoMode: currentAgenda.demoMode,
        connectedProviders: currentAgenda.connectedProviders,
        conflictCount: currentAgenda.conflictCount,
        items: [...currentAgenda.items, newAgendaItem],
      );
      await _cache.saveCachedAgenda(updatedAgenda);
      state = state.copyWith(agenda: updatedAgenda);
      return localTask;
    }
  }

  Future<void> createCalendarEvent({
    required String provider,
    required String title,
    String? description,
    String? location,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    await _apiClient.dio.post(
      '/api/calendar/events',
      data: {
        'provider': provider,
        'title': title,
        'description': description,
        'location': location,
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt.toUtc().toIso8601String(),
      },
    );
    await loadAgenda();
  }

  Future<void> completeTask(String taskId, {int? notificationId}) async {
    if (notificationId != null) {
      await _notificationService.cancelReminder(notificationId);
    }

    // Pembaruan optimistik di UI
    final current = state.agenda;
    if (current != null) {
      final updatedItems = current.items.map((item) {
        if (item.id == taskId) {
          return item.copyWith(isCompleted: !item.isCompleted);
        }
        return item;
      }).toList();
      state = state.copyWith(
        agenda: UnifiedAgendaResponse(
          date: current.date,
          demoMode: current.demoMode,
          connectedProviders: current.connectedProviders,
          conflictCount: current.conflictCount,
          items: updatedItems,
        ),
      );
    }

    try {
      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/tasks/$taskId/complete',
      );
      final nextRaw = res.data?['nextRecurringTask'];
      if (nextRaw is Map) {
        final nextTask = TaskItem.fromJson(Map<String, dynamic>.from(nextRaw));
        await _notificationService.scheduleTaskReminder(nextTask);
      }
      await loadAgenda();
    } catch (_) {}
  }

  Future<void> snoozeTask({
    required String taskId,
    required String title,
    required int notificationId,
    int minutes = 10,
  }) async {
    await _notificationService.snoozeTaskReminder(
      taskId: taskId,
      title: title,
      notificationId: notificationId,
      minutes: minutes,
    );
    try {
      await _apiClient.dio.post(
        '/api/tasks/$taskId/snooze',
        data: {'minutes': minutes},
      );
      await loadAgenda();
    } catch (_) {}
  }

  Future<void> deleteTask(String taskId, {int? notificationId}) async {
    if (notificationId != null) {
      await _notificationService.cancelReminder(notificationId);
    }
    try {
      await _apiClient.dio.delete('/api/tasks/$taskId');
    } catch (_) {}
    await loadAgenda();
  }
}

final agendaProvider =
    StateNotifierProvider<AgendaNotifier, AgendaState>((ref) {
  return AgendaNotifier(
    apiClient: ref.watch(apiClientProvider),
    cache: ref.watch(localCacheProvider),
    notificationService: ref.watch(notificationServiceProvider),
  );
});
