import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.onSpeakTap,
  });

  final ChatMessageModel message;
  final VoidCallback onSpeakTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final timeLabel = DateFormat('HH:mm').format(message.createdAt.toLocal());

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 10),
          decoration: BoxDecoration(
            color: isUser ? scheme.primary : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isUser ? 20 : 6),
              bottomRight: Radius.circular(isUser ? 6 : 20),
            ),
            border: isUser
                ? null
                : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser && message.toolArtifacts.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: message.toolArtifacts.map((artifact) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: artifact.success
                            ? scheme.primary.withValues(alpha: 0.12)
                            : scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            artifact.toolName == 'create_task'
                                ? Icons.alarm_add_rounded
                                : artifact.toolName == 'create_calendar_event'
                                    ? Icons.event_available_rounded
                                    : Icons.auto_awesome_rounded,
                            size: 14,
                            color: artifact.success
                                ? scheme.primary
                                : scheme.onErrorContainer,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              artifact.summary,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: artifact.success
                                        ? scheme.primary
                                        : scheme.onErrorContainer,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
              if (message.content.isEmpty && message.isStreaming)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'TemanHari sedang mengetik...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                )
              else
                SelectableText(
                  message.content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.48,
                        color: isUser ? scheme.onPrimary : scheme.onSurface,
                      ),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isUser
                              ? scheme.onPrimary.withValues(alpha: 0.78)
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                  if (!isUser && !message.isStreaming && message.content.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onSpeakTap,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
