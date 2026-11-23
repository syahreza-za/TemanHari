import 'task_item.dart';

class ToolArtifact {
  const ToolArtifact({
    required this.toolName,
    required this.success,
    required this.summary,
    this.createdTask,
    this.completedTaskId,
  });

  final String toolName;
  final bool success;
  final String summary;
  final TaskItem? createdTask;
  final String? completedTaskId;

  factory ToolArtifact.fromJson(Map<String, dynamic> json) {
    return ToolArtifact(
      toolName: (json['toolName'] as String?) ?? '',
      success: json['success'] == true,
      summary: (json['summary'] as String?) ?? '',
      createdTask: json['createdTask'] != null
          ? TaskItem.fromJson(Map<String, dynamic>.from(json['createdTask'] as Map))
          : null,
      completedTaskId: json['completedTaskId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'success': success,
        'summary': summary,
        'createdTask': createdTask?.toJson(),
        'completedTaskId': completedTaskId,
      };
}

class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.moodTag,
    this.toolArtifacts = const [],
    this.isStreaming = false,
  });

  final String id;
  final String role; // user | assistant
  final String content;
  final DateTime createdAt;
  final String? moodTag;
  final List<ToolArtifact> toolArtifacts;
  final bool isStreaming;

  bool get isUser => role == 'user';

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final rawArtifacts = (json['toolArtifacts'] as List<dynamic>?) ?? const [];
    return ChatMessageModel(
      id: (json['id'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'assistant',
      content: (json['content'] as String?) ?? '',
      moodTag: json['moodTag'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      toolArtifacts: rawArtifacts
          .map((e) => ToolArtifact.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'moodTag': moodTag,
        'createdAt': createdAt.toIso8601String(),
        'toolArtifacts': toolArtifacts.map((e) => e.toJson()).toList(),
      };

  ChatMessageModel copyWith({
    String? id,
    String? content,
    List<ToolArtifact>? toolArtifacts,
    bool? isStreaming,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      moodTag: moodTag,
      toolArtifacts: toolArtifacts ?? this.toolArtifacts,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
