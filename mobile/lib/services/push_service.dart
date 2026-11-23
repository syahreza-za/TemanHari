import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../core/network/api_client.dart';
import 'notification_service.dart';

/// Handler pesan FCM saat aplikasi ditutup (terminated) atau di latar belakang.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    debugPrint('[FCM Background] Pesan diterima: ${message.messageId}');
  } catch (e) {
    debugPrint('[FCM Background] Firebase belum dikonfigurasi: $e');
  }
}

class PushNotificationService {
  PushNotificationService({
    required ApiClient apiClient,
    required NotificationService notificationService,
  })  : _apiClient = apiClient,
        _notificationService = notificationService;

  final ApiClient _apiClient;
  final NotificationService _notificationService;
  bool _available = false;

  bool get isAvailable => _available;

  /// Menginisialisasi Firebase & FCM secara aman.
  /// Jika file `google-services.json` / `GoogleService-Info.plist` belum dipasang,
  /// aplikasi tetap berjalan normal dalam Mode Lokal/Demo tanpa crash.
  Future<void> initAndRegister() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      _available = true;

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerTokenOnBackend(token);
      }

      messaging.onTokenRefresh.listen(_registerTokenOnBackend);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notif = message.notification;
        if (notif != null) {
          _notificationService.showImmediateNotification(
            id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
            title: notif.title ?? 'Sapaan dari TemanHari',
            body: notif.body ?? '',
          );
        }
      });
    } catch (e) {
      _available = false;
      debugPrint(
        '[FCM] Dilewati (Firebase config belum dipasang di perangkat): $e',
      );
    }
  }

  Future<void> _registerTokenOnBackend(String fcmToken) async {
    try {
      await _apiClient.dio.post(
        '/api/notifications/register-device',
        data: {
          'fcmToken': fcmToken,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (e) {
      debugPrint('[FCM] Gagal mendaftarkan FCM token ke backend: $e');
    }
  }
}
