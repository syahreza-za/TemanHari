import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/agenda_item.dart';
import '../../models/chat_message.dart';
import '../../models/task_item.dart';
import '../../models/user_profile.dart';

/// Cache offline-first berbasis Hive agar tugas, jadwal hari ini,
/// riwayat obrolan, dan preferensi tetap tersedia walau tanpa internet.
class LocalCacheService {
  static const _boxName = 'temanhari_offline_cache';
  static const _profileKey = 'profile';
  static const _agendaKey = 'unified_agenda';
  static const _tasksKey = 'offline_tasks';
  static const _chatKey = 'chat_messages';
  static const _themeKey = 'theme_mode';
  static const _apiUrlKey = 'custom_api_base_url';

  late Box<String> _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    _initialized = true;
  }

  UserProfile? getProfile() {
    if (!_initialized) return null;
    final raw = _box.get(_profileKey);
    if (raw == null) return null;
    return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveProfile(UserProfile profile) async {
    if (!_initialized) return;
    await _box.put(_profileKey, jsonEncode(profile.toJson()));
  }

  UnifiedAgendaResponse? getCachedAgenda() {
    if (!_initialized) return null;
    final raw = _box.get(_agendaKey);
    if (raw == null) return null;
    return UnifiedAgendaResponse.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> saveCachedAgenda(UnifiedAgendaResponse agenda) async {
    if (!_initialized) return;
    await _box.put(_agendaKey, jsonEncode(agenda.toJson()));
  }

  List<TaskItem> getOfflineTasks() {
    if (!_initialized) return const [];
    final raw = _box.get(_tasksKey);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveOfflineTasks(List<TaskItem> tasks) async {
    if (!_initialized) return;
    await _box.put(
      _tasksKey,
      jsonEncode(tasks.map((e) => e.toJson()).toList()),
    );
  }

  List<ChatMessageModel> getCachedChat() {
    if (!_initialized) return const [];
    final raw = _box.get(_chatKey);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) =>
            ChatMessageModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveCachedChat(List<ChatMessageModel> messages) async {
    if (!_initialized) return;
    final limited =
        messages.length > 60 ? messages.sublist(messages.length - 60) : messages;
    await _box.put(
      _chatKey,
      jsonEncode(limited.map((e) => e.toJson()).toList()),
    );
  }

  String getThemeModeName() {
    if (!_initialized) return 'system';
    return _box.get(_themeKey) ?? 'system';
  }

  Future<void> saveThemeModeName(String modeName) async {
    if (!_initialized) return;
    await _box.put(_themeKey, modeName);
  }

  String? getCustomApiBaseUrl() {
    if (!_initialized) return null;
    return _box.get(_apiUrlKey);
  }

  Future<void> saveCustomApiBaseUrl(String? url) async {
    if (!_initialized) return;
    if (url == null || url.trim().isEmpty) {
      await _box.delete(_apiUrlKey);
    } else {
      await _box.put(_apiUrlKey, url.trim());
    }
  }
}
