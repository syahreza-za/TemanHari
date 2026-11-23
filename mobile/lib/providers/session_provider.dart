import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../core/network/api_client.dart';
import '../core/storage/local_cache.dart';
import '../core/storage/secure_storage.dart';
import '../models/user_profile.dart';
import '../services/notification_service.dart';
import '../services/oauth_service.dart';
import '../services/push_service.dart';
import 'app_providers.dart';

class SessionState {
  const SessionState({
    required this.profile,
    this.capabilities = const ServerCapabilities(),
    this.memories = const [],
    this.isBootstrapping = false,
    this.isOnline = false,
    this.todayMood,
    this.statusMessage,
  });

  final UserProfile profile;
  final ServerCapabilities capabilities;
  final List<UserMemoryItem> memories;
  final bool isBootstrapping;
  final bool isOnline;
  final String? todayMood;
  final String? statusMessage;

  SessionState copyWith({
    UserProfile? profile,
    ServerCapabilities? capabilities,
    List<UserMemoryItem>? memories,
    bool? isBootstrapping,
    bool? isOnline,
    String? todayMood,
    String? statusMessage,
    bool clearStatus = false,
  }) {
    return SessionState(
      profile: profile ?? this.profile,
      capabilities: capabilities ?? this.capabilities,
      memories: memories ?? this.memories,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      isOnline: isOnline ?? this.isOnline,
      todayMood: todayMood ?? this.todayMood,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
    );
  }
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier({
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
    required LocalCacheService cache,
    required NotificationService notificationService,
    required PushNotificationService pushService,
    required OAuthService oauthService,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage,
        _cache = cache,
        _notificationService = notificationService,
        _pushService = pushService,
        _oauthService = oauthService,
        super(
          SessionState(
            profile: cache.getProfile() ?? UserProfile.defaultOffline(),
          ),
        );

  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;
  final LocalCacheService _cache;
  final NotificationService _notificationService;
  final PushNotificationService _pushService;
  final OAuthService _oauthService;

  Future<void> bootstrap() async {
    state = state.copyWith(isBootstrapping: true, clearStatus: true);
    await _notificationService.init();

    try {
      final deviceKey = await _secureStorage.getOrCreateDeviceKey();
      String timezone = 'Asia/Jakarta';
      try {
        timezone = await FlutterTimezone.getLocalTimezone();
      } catch (_) {}

      final res = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/bootstrap',
        data: {
          'deviceKey': deviceKey,
          'nickname': state.profile.nickname,
          'timezone': timezone,
        },
      );

      final data = res.data ?? const {};
      final token = data['token'] as String?;
      if (token != null && token.isNotEmpty) {
        await _secureStorage.saveToken(token);
      }

      final profile = UserProfile.fromJson(
        Map<String, dynamic>.from((data['user'] as Map?) ?? const {}),
      );
      final caps = ServerCapabilities.fromJson(
        data['capabilities'] as Map<String, dynamic>?,
      );

      await _cache.saveProfile(profile);
      state = state.copyWith(
        profile: profile,
        capabilities: caps,
        isBootstrapping: false,
        isOnline: true,
      );

      // Inisialisasi FCM push & muat memori pribadi di latar belakang
      await _pushService.initAndRegister();
      await refreshProfileDetails();
    } catch (e) {
      debugPrint('[Session] Berjalan offline / server belum aktif: $e');
      state = state.copyWith(
        isBootstrapping: false,
        isOnline: false,
        statusMessage: 'Mode Offline: pengingat lokal tetap aktif di perangkat.',
      );
    }
  }

  Future<void> refreshProfileDetails() async {
    try {
      final res = await _apiClient.dio.get<Map<String, dynamic>>('/api/auth/me');
      final data = res.data ?? const {};
      final profile = UserProfile.fromJson(
        Map<String, dynamic>.from((data['user'] as Map?) ?? const {}),
      );
      final rawMemories = (data['memories'] as List<dynamic>?) ?? const [];
      final memories = rawMemories
          .map((e) => UserMemoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final latestMood = data['latestMood'] as Map<String, dynamic>?;

      await _cache.saveProfile(profile);
      state = state.copyWith(
        profile: profile,
        memories: memories,
        todayMood: latestMood?['mood'] as String?,
        isOnline: true,
      );
    } catch (_) {}
  }

  Future<void> updateProfile({
    String? nickname,
    String? aiPersona,
    bool? voiceEnabled,
    double? ttsSpeechRate,
    bool? demoMode,
    bool? quietHoursEnabled,
    String? quietStart,
    String? quietEnd,
  }) async {
    final optimistic = state.profile.copyWith(
      nickname: nickname,
      aiPersona: aiPersona,
      voiceEnabled: voiceEnabled,
      ttsSpeechRate: ttsSpeechRate,
      demoMode: demoMode,
      quietHoursEnabled: quietHoursEnabled,
      quietStart: quietStart,
      quietEnd: quietEnd,
    );

    state = state.copyWith(profile: optimistic);
    await _cache.saveProfile(optimistic);

    try {
      final payload = <String, dynamic>{
        if (nickname != null) 'nickname': nickname,
        if (aiPersona != null) 'aiPersona': aiPersona,
        if (voiceEnabled != null) 'voiceEnabled': voiceEnabled,
        if (ttsSpeechRate != null) 'ttsSpeechRate': ttsSpeechRate,
        if (demoMode != null) 'demoMode': demoMode,
        if (quietHoursEnabled != null) 'quietHoursEnabled': quietHoursEnabled,
        if (quietStart != null) 'quietStart': quietStart,
        if (quietEnd != null) 'quietEnd': quietEnd,
      };
      final res = await _apiClient.dio.patch<Map<String, dynamic>>(
        '/api/auth/profile',
        data: payload,
      );
      final updated = UserProfile.fromJson(
        Map<String, dynamic>.from((res.data?['user'] as Map?) ?? const {}),
      );
      await _cache.saveProfile(updated);
      state = state.copyWith(profile: updated, isOnline: true);
    } catch (e) {
      debugPrint('[Session] Gagal sinkronisasi profil ke server: $e');
    }
  }

  Future<void> logMood({
    required String mood,
    required int score,
    String? note,
  }) async {
    state = state.copyWith(todayMood: mood);
    try {
      await _apiClient.dio.post(
        '/api/auth/mood',
        data: {
          'mood': mood,
          'score': score,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
    } catch (_) {}
  }

  Future<void> deleteMemory(String memoryId) async {
    state = state.copyWith(
      memories: state.memories.where((m) => m.id != memoryId).toList(),
    );
    try {
      await _apiClient.dio.delete('/api/auth/memories/$memoryId');
    } catch (_) {}
  }

  Future<OAuthResult> connectCalendar(String provider) async {
    final result = await _oauthService.connectProvider(provider);
    if (result.success) {
      await refreshProfileDetails();
    }
    return result;
  }

  Future<void> disconnectCalendar(String provider) async {
    await _oauthService.disconnectProvider(provider);
    await refreshProfileDetails();
  }

  Future<String> sendTestNotification() async {
    await _notificationService.requestPermissions();
    await _notificationService.showImmediateNotification(
      id: 999001,
      title: 'Hai ${state.profile.nickname}, ini tes pengingat TemanHari 🔔',
      body: 'Notifikasi lokal aktif! Kamu bisa klik Tandai Selesai atau Tunda 10 Menit.',
      payload: '{"taskId":"demo-test","title":"Tes Pengingat TemanHari","notificationId":999001}',
    );
    return 'Notifikasi tes berhasil dikirim ke HP-mu.';
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(
    apiClient: ref.watch(apiClientProvider),
    secureStorage: ref.watch(secureStorageProvider),
    cache: ref.watch(localCacheProvider),
    notificationService: ref.watch(notificationServiceProvider),
    pushService: ref.watch(pushServiceProvider),
    oauthService: ref.watch(oauthServiceProvider),
  );
});
