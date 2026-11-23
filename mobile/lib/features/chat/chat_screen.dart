import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_provider.dart';
import '../../providers/session_provider.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/mood_checkin_bar.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const _quickPrompts = <String>[
    'Tolong ingetin besok jam 8 pagi kirim laporan dan jam 7 malam minum vitamin ya',
    'Ada jadwal apa aja aku hari ini?',
    'Hari ini rasanya lumayan capek, temenin ngobrol dong',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendCurrentText({bool speakReply = false}) async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await ref.read(chatProvider.notifier).sendMessage(
          text,
          speakReplyIfEnabled: speakReply,
        );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final chat = ref.watch(chatProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<ChatState>(chatProvider, (previous, next) {
      if ((previous?.messages.length ?? 0) != next.messages.length ||
          next.isSending) {
        _scrollToBottom();
      }
    });

    final personaLabel = switch (session.profile.aiPersona) {
      'tenang' => 'Tenang & Pendengar Baik',
      'ceria' => 'Ceria & Menyemangati',
      _ => 'Santai & Akrab',
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primary.withValues(alpha: 0.16),
              child: Icon(Icons.wb_sunny_rounded, color: scheme.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TemanHari', style: TextStyle(fontSize: 17)),
                  Text(
                    personaLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Hentikan suara',
            onPressed: () => ref.read(chatProvider.notifier).stopSpeaking(),
            icon: const Icon(Icons.volume_off_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear') {
                await ref.read(chatProvider.notifier).clearChat();
              } else if (value == 'refresh') {
                await ref.read(chatProvider.notifier).loadHistoryAndGreeting();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'refresh',
                child: Text('Muat ulang obrolan'),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text('Bersihkan riwayat chat'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (chat.proactiveGreeting != null && chat.proactiveGreeting!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                chat.proactiveGreeting!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
              ),
            ),
          MoodCheckinBar(
            selectedMood: session.todayMood,
            onMoodSelected: (mood) async {
              await ref.read(sessionProvider.notifier).logMood(
                    mood: mood.key,
                    score: mood.score,
                  );
              await ref.read(chatProvider.notifier).sendMessage(
                    'Hari ini suasana hatiku lagi ${mood.label.toLowerCase()} ${mood.emoji}',
                    moodTag: mood.key,
                  );
            },
          ),
          if (chat.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Material(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: scheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          chat.errorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 6, bottom: 16),
              itemCount: chat.messages.length,
              itemBuilder: (context, index) {
                final msg = chat.messages[index];
                return ChatBubble(
                  message: msg,
                  onSpeakTap: () =>
                      ref.read(chatProvider.notifier).speakMessage(msg.content),
                );
              },
            ),
          ),
          if (chat.messages.length <= 2 && !chat.isSending)
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final prompt = _quickPrompts[index];
                  return ActionChip(
                    label: Text(
                      prompt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      ref.read(chatProvider.notifier).sendMessage(prompt);
                    },
                  );
                },
              ),
            ),
          if (chat.isListening)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.graphic_eq_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      chat.voiceDraft.isEmpty
                          ? 'Mendengarkan suaramu (Bahasa Indonesia)...'
                          : chat.voiceDraft,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: chat.isListening ? 'Berhenti rekam' : 'Ngobrol pakai suara',
                    style: IconButton.styleFrom(
                      backgroundColor: chat.isListening
                          ? scheme.error
                          : scheme.surfaceContainerLow,
                      foregroundColor:
                          chat.isListening ? scheme.onError : scheme.primary,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: chat.isSending
                        ? null
                        : () => ref.read(chatProvider.notifier).toggleVoiceInput(),
                    icon: Icon(
                      chat.isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendCurrentText(),
                      decoration: const InputDecoration(
                        hintText: 'Cerita atau minta diingatkan sesuatu...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Kirim pesan',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: chat.isSending ? null : () => _sendCurrentText(),
                    icon: chat.isSending
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
