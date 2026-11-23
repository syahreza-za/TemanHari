class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.notes,
    this.dueAt,
    this.remindAt,
    this.priority = 'medium',
    this.category = 'pribadi',
    this.recurrence = 'none',
    this.isCompleted = false,
    required this.notificationId,
    this.pendingSync = false,
  });

  final String id;
  final String title;
  final String? notes;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final String priority; // low | medium | high
  final String category; // pribadi | kerja | kesehatan | belanja | lainnya
  final String recurrence; // none | daily | weekly | monthly
  final bool isCompleted;
  final int notificationId;
  final bool pendingSync;

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      notes: json['notes'] as String?,
      dueAt: json['dueAt'] != null ? DateTime.tryParse(json['dueAt'].toString()) : null,
      remindAt: json['remindAt'] != null
          ? DateTime.tryParse(json['remindAt'].toString())
          : null,
      priority: (json['priority'] as String?) ?? 'medium',
      category: (json['category'] as String?) ?? 'pribadi',
      recurrence: (json['recurrence'] as String?) ?? 'none',
      isCompleted: json['isCompleted'] == true,
      notificationId: (json['notificationId'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch.remainder(2000000000),
      pendingSync: json['pendingSync'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'dueAt': dueAt?.toIso8601String(),
        'remindAt': remindAt?.toIso8601String(),
        'priority': priority,
        'category': category,
        'recurrence': recurrence,
        'isCompleted': isCompleted,
        'notificationId': notificationId,
        'pendingSync': pendingSync,
      };

  TaskItem copyWith({
    String? id,
    String? title,
    String? notes,
    DateTime? dueAt,
    DateTime? remindAt,
    String? priority,
    String? category,
    String? recurrence,
    bool? isCompleted,
    int? notificationId,
    bool? pendingSync,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      dueAt: dueAt ?? this.dueAt,
      remindAt: remindAt ?? this.remindAt,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      recurrence: recurrence ?? this.recurrence,
      isCompleted: isCompleted ?? this.isCompleted,
      notificationId: notificationId ?? this.notificationId,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}
