import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/task_item.dart';

const String kReminderChannelId = 'temanhari_reminders';
const String kReminderChannelName = 'Pengingat Tugas & Jadwal TemanHari';
const String kReminderChannelDesc =
    'Pengingat penting tugas harian dan agenda agar tetap berbunyi walau layar HP mati.';

const String kActionMarkDone = 'ACTION_MARK_DONE';
const String kActionSnooze10 = 'ACTION_SNOOZE_10';

/// Handler top-level agar tombol aksi notifikasi (Tandai Selesai / Tunda 10 Menit)
/// tetap berjalan meskipun aplikasi sedang tertutup atau di latar belakang.
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final title = (data['title'] as String?) ?? 'Pengingat TemanHari';
    final notificationId = (data['notificationId'] as num?)?.toInt() ?? 1001;

    if (response.actionId == kActionSnooze10) {
      tz.initializeTimeZones();
      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      final snoozedTime =
          tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
      await plugin.zonedSchedule(
        notificationId,
        '⏰ Tunda 10 menit: $title',
        'Yuk kita mulai pelan-pelan sekarang ya!',
        snoozedTime,
        NotificationService.buildNotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  } catch (e) {
    debugPrint('[NotificationBg] Gagal menangani aksi latar belakang: $e');
  }
}

class NotificationActionEvent {
  const NotificationActionEvent({
    required this.actionId,
    required this.taskId,
    required this.title,
    required this.notificationId,
  });

  final String actionId;
  final String taskId;
  final String title;
  final int notificationId;
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<NotificationActionEvent> _actionStream =
      StreamController<NotificationActionEvent>.broadcast();

  bool _initialized = false;

  Stream<NotificationActionEvent> get onAction => _actionStream.stream;

  static NotificationDetails buildNotificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      kReminderChannelId,
      kReminderChannelName,
      channelDescription: kReminderChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.alarm,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kActionMarkDone,
          'Tandai Selesai',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          kActionSnooze10,
          'Tunda 10 Menit',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'temanhari_task_category',
    );

    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'temanhari_task_category',
          actions: [
            DarwinNotificationAction.plain(kActionMarkDone, 'Tandai Selesai'),
            DarwinNotificationAction.plain(kActionSnooze10, 'Tunda 10 Menit'),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _handleForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Buat channel Android berprioritas tinggi agar berbunyi walau layar mati
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        kReminderChannelId,
        kReminderChannelName,
        description: kReminderChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    _initialized = true;
  }

  /// Meminta izin notifikasi Android 13+ (`POST_NOTIFICATIONS`),
  /// Exact Alarm (`SCHEDULE_EXACT_ALARM`), serta izin notifikasi iOS.
  Future<bool> requestPermissions() async {
    await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final notifGranted =
          await androidImpl.requestNotificationsPermission() ?? true;
      await androidImpl.requestExactAlarmsPermission();
      return notifGranted;
    }

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final granted = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return granted;
    }
    return true;
  }

  void _handleForegroundResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final taskId = (data['taskId'] as String?) ?? '';
      final title = (data['title'] as String?) ?? '';
      final notificationId = (data['notificationId'] as num?)?.toInt() ?? 0;

      if (response.actionId != null && response.actionId!.isNotEmpty) {
        _actionStream.add(
          NotificationActionEvent(
            actionId: response.actionId!,
            taskId: taskId,
            title: title,
            notificationId: notificationId,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Notification] Gagal membaca payload: $e');
    }
  }

  /// Menjadwalkan pengingat tepat waktu dengan `exactAllowWhileIdle`
  /// agar tetap berbunyi meski HP dalam kondisi Doze / layar mati.
  Future<void> scheduleTaskReminder(TaskItem task) async {
    await init();
    final targetTime = task.remindAt ?? task.dueAt;
    if (task.isCompleted || targetTime == null) {
      await cancelReminder(task.notificationId);
      return;
    }

    final now = DateTime.now();
    if (!targetTime.isAfter(now)) {
      return;
    }

    final scheduled = tz.TZDateTime.from(targetTime, tz.local);
    final payload = jsonEncode({
      'taskId': task.id,
      'title': task.title,
      'notificationId': task.notificationId,
    });

    final bodyText = (task.notes != null && task.notes!.trim().isNotEmpty)
        ? task.notes!.trim()
        : 'Waktunya "${task.title}". Semangat ya, kamu pasti bisa!';

    DateTimeComponents? matchComponents;
    if (task.recurrence == 'daily') {
      matchComponents = DateTimeComponents.time;
    } else if (task.recurrence == 'weekly') {
      matchComponents = DateTimeComponents.dayOfWeekAndTime;
    } else if (task.recurrence == 'monthly') {
      matchComponents = DateTimeComponents.dayOfMonthAndTime;
    }

    await _plugin.zonedSchedule(
      task.notificationId,
      '🔔 ${task.title}',
      bodyText,
      scheduled,
      buildNotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchComponents,
      payload: payload,
    );
  }

  Future<void> snoozeTaskReminder({
    required String taskId,
    required String title,
    required int notificationId,
    int minutes = 10,
  }) async {
    await init();
    final scheduled =
        tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    final payload = jsonEncode({
      'taskId': taskId,
      'title': title,
      'notificationId': notificationId,
    });

    await _plugin.zonedSchedule(
      notificationId,
      '⏰ Pengingat Tunda: $title',
      'Ditunda $minutes menit tadi — yuk kita bereskan sekarang ya!',
      scheduled,
      buildNotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      buildNotificationDetails(),
      payload: payload,
    );
  }

  Future<void> cancelReminder(int notificationId) async {
    await init();
    await _plugin.cancel(notificationId);
  }

  void dispose() {
    _actionStream.close();
  }
}
