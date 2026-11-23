import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/storage/local_cache.dart';
import '../core/storage/secure_storage.dart';
import '../services/notification_service.dart';
import '../services/oauth_service.dart';
import '../services/push_service.dart';
import '../services/voice_service.dart';

final localCacheProvider = Provider<LocalCacheService>((ref) {
  throw UnimplementedError('LocalCacheService harus di-override di main.dart');
});

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    secureStorage: ref.watch(secureStorageProvider),
    cache: ref.watch(localCacheProvider),
  );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(service.dispose);
  return service;
});

final pushServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(
    apiClient: ref.watch(apiClientProvider),
    notificationService: ref.watch(notificationServiceProvider),
  );
});

final voiceServiceProvider = Provider<VoiceService>((ref) => VoiceService());

final oauthServiceProvider = Provider<OAuthService>(
  (ref) => OAuthService(ref.watch(apiClientProvider)),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._cache) : super(_parse(_cache.getThemeModeName()));

  final LocalCacheService _cache;

  static ThemeMode _parse(String name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final name = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _cache.saveThemeModeName(name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(localCacheProvider));
});
