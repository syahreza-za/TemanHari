import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/network/api_client.dart';
import '../core/storage/local_cache.dart';
import '../models/chat_message.dart';
import '../services/notification_service.dart';
import '../services/voice_service.dart';
import 'agenda_provider.dart';
import 'app_providers.dart';
import 'session_provider.dart';

class ChatState {
  const ChatState({
    this.messages = const [],
    this.proactiveGreeting,
    this.isSending = false,
    this.isListening = false,
    this.voiceDraft = '',
    this.errorMessage,
  });

  final List<ChatMessageModel> messages;
  final String? proactiveGreeting;
  final bool isSending;
  final bool isListening;
  final String voiceDraft;
  final String? errorMessage;

  ChatState copyWith({
    List<ChatMessageModel>? messages,
    String? proactiveGreeting,
    bool? isSending,
    bool? isListening,
    String? voiceDraft,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      proactiveGreeting: proactiveGreeting ?? this.proactiveGreeting,
      isSending: isSending ?? this.isSending,
      isListening: isListening ?? this.isListening,
      voiceDraft: voiceDraft ?? this.voiceDraft,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier({
    required Ref ref,
    required ApiClient apiClient,
    required LocalCacheService cache,
    required NotificationService notificationService,
    required VoiceService voiceService,
  })  : _ref = ref,
        _apiClient = apiClient,
        _cache = cache,
        _notificationService = notificationService,
        _voiceService = voiceService,
        super(ChatState(messages: cache.getCachedChat()));

  final Ref _ref;
  final ApiClient _apiClient;
  final LocalCacheService _cache;
  final NotificationService _notificationService;
  final VoiceService _voiceService;

  Future<void> loadHistoryAndGreeting() async {
    try {
      final results = await Future.wait([
        _apiClient.dio.get<Map<String, dynamic>>('/api/chat/history'),
        _apiClient.dio.get<Map<String, dynamic>>('/api/chat/greeting'),
      ]);

      final rawMsgs = (results[0].data?['messages'] as List<dynamic>?) ?? const [];
      final messages = rawMsgs
          .map((e) =>
              ChatMessageModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final greeting = results[1].data?['greeting'] as String?;

      await _cache.saveCachedChat(messages);
      state = state.copyWith(
        messages: messages,
        proactiveGreeting: greeting,
        clearError: true,
      );
    } catch (e) {
      debugPrint('[Chat] Menggunakan cache riwayat lokal: $e');
      if (state.messages.isEmpty) {
        final nickname = _ref.read(sessionProvider).profile.nickname;
        state = state.copyWith(
          messages: [
            ChatMessageModel(
              id: 'welcome-offline',
              role: 'assistant',
              content:
                  'Halo $nickname! Saat ini kita sedang di mode offline, tapi kamu tetap bisa mencatat tugas & jadwal di tab Hari Ini, atau sambungkan ke backend TemanHari untuk ngobrol denganku.',
              createdAt: DateTime.now(),
            ),
          ],
        );
      }
    }
  }

  Future<void> sendMessage(
    String rawText, {
    String? moodTag,
    bool speakReplyIfEnabled = false,
  }) async {
    final text = rawText.trim();
    if (text.isEmpty || state.isSending) return;

    await _voiceService.stopSpeaking();

    final userMsg = ChatMessageModel(
      id: 'u-${const Uuid().v4()}',
      role: 'user',
      content: text,
      moodTag: moodTag,
      createdAt: DateTime.now(),
    );
    final assistantPlaceholderId = 'a-${const Uuid().v4()}';
    final assistantPlaceholder = ChatMessageModel(
      id: assistantPlaceholderId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, assistantPlaceholder],
      isSending: true,
      voiceDraft: '',
      clearError: true,
    );

    final buffer = StringBuffer();
    final artifacts = <ToolArtifact>[];
    bool agendaNeedsRefresh = false;

    try {
      await for (final sse in _apiClient.streamChat(
        message: text,
        moodTag: moodTag,
      )) {
        if (sse.event == 'delta') {
          final chunk = (sse.data['text'] as String?) ?? '';
          buffer.write(chunk);
          _updateAssistantMessage(
            assistantPlaceholderId,
            content: buffer.toString(),
            artifacts: List.unmodifiable(artifacts),
            isStreaming: true,
          );
        } else if (sse.event == 'tool') {
          final artifact = ToolArtifact.fromJson(sse.data);
          artifacts.add(artifact);

          // Jika Gemini membuat tugas baru, langsung jadwalkan notifikasi lokal tepat waktu di HP!
          if (artifact.createdTask != null) {
            await _notificationService.requestPermissions();
            await _notificationService.scheduleTaskReminder(artifact.createdTask!);
            agendaNeedsRefresh = true;
          }
          if (artifact.completedTaskId != null ||
              artifact.toolName == 'create_calendar_event') {
            agendaNeedsRefresh = true;
          }

          _updateAssistantMessage(
            assistantPlaceholderId,
            content: buffer.toString(),
            artifacts: List.unmodifiable(artifacts),
            isStreaming: true,
          );
        } else if (sse.event == 'done') {
          final finalText =
              (sse.data['fullText'] as String?) ?? buffer.toString();
          final finalId =
              (sse.data['messageId'] as String?) ?? assistantPlaceholderId;

          _updateAssistantMessage(
            assistantPlaceholderId,
            newId: finalId,
            content: finalText,
            artifacts: List.unmodifiable(artifacts),
            isStreaming: false,
          );

          final profile = _ref.read(sessionProvider).profile;
          if (speakReplyIfEnabled && profile.voiceEnabled) {
            await _voiceService.speak(
              finalText,
              speechRate: profile.ttsSpeechRate,
            );
          }
        } else if (sse.event == 'error') {
          final errMsg =
              (sse.data['message'] as String?) ?? 'Terjadi kendala pada AI.';
          throw Exception(errMsg);
        }
      }

      if (agendaNeedsRefresh) {
        await _ref.read(agendaProvider.notifier).loadAgenda();
      }
      await _cache.saveCachedChat(state.messages);
      state = state.copyWith(isSending: false);
    } catch (e) {
      final fallbackMsg =
          'Maaf ya, koneksiku ke server lagi terputus sebentar ($e). Pastikan backend TemanHari aktif atau coba kirim lagi ya.';
      _updateAssistantMessage(
        assistantPlaceholderId,
        content: buffer.isNotEmpty ? buffer.toString() : fallbackMsg,
        artifacts: List.unmodifiable(artifacts),
        isStreaming: false,
      );
      state = state.copyWith(
        isSending: false,
        errorMessage: 'Koneksi obrolan terganggu.',
      );
    }
  }

  void _updateAssistantMessage(
    String targetId, {
    String? newId,
    required String content,
    required List<ToolArtifact> artifacts,
    required bool isStreaming,
  }) {
    final updated = state.messages.map((m) {
      if (m.id == targetId) {
        return m.copyWith(
          id: newId ?? m.id,
          content: content,
          toolArtifacts: artifacts,
          isStreaming: isStreaming,
        );
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  Future<void> toggleVoiceInput() async {
    if (state.isListening) {
      await _voiceService.stopListening();
      final draft = state.voiceDraft.trim();
      state = state.copyWith(isListening: false);
      if (draft.isNotEmpty) {
        await sendMessage(draft, speakReplyIfEnabled: true);
      }
      return;
    }

    state = state.copyWith(isListening: true, voiceDraft: '', clearError: true);
    final started = await _voiceService.startListening(
      onResult: (recognized, isFinal) {
        state = state.copyWith(voiceDraft: recognized);
        if (isFinal && recognized.trim().isNotEmpty) {
          state = state.copyWith(isListening: false);
          sendMessage(recognized, speakReplyIfEnabled: true);
        }
      },
      onStatus: (status) {
        if (status == 'done' ||
            status == 'notListening' ||
            status.startsWith('error:')) {
          state = state.copyWith(isListening: false);
        }
      },
    );

    if (!started) {
      state = state.copyWith(
        isListening: false,
        errorMessage: 'Izin mikrofon belum aktif atau perangkat tidak mendukung pengenalan suara.',
      );
    }
  }

  Future<void> speakMessage(String text) async {
    final rate = _ref.read(sessionProvider).profile.ttsSpeechRate;
    await _voiceService.speak(text, speechRate: rate);
  }

  Future<void> stopSpeaking() => _voiceService.stopSpeaking();

  Future<void> clearChat() async {
    state = state.copyWith(messages: const []);
    await _cache.saveCachedChat(const []);
    try {
      await _apiClient.dio.delete('/api/chat/history');
    } catch (_) {}
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(
    ref: ref,
    apiClient: ref.watch(apiClientProvider),
    cache: ref.watch(localCacheProvider),
    notificationService: ref.watch(notificationServiceProvider),
    voiceService: ref.watch(voiceServiceProvider),
  );
});
