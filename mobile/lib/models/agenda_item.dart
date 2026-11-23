import 'user_profile.dart';

class UnifiedAgendaItem {
  const UnifiedAgendaItem({
    required this.id,
    required this.kind,
    required this.source,
    required this.sourceBadge,
    required this.title,
    this.description,
    this.location,
    required this.startAt,
    this.endAt,
    this.isAllDay = false,
    this.isCompleted = false,
    this.priority,
    this.category,
    this.recurrence,
    this.notificationId,
    this.meetingLink,
    this.hasConflict = false,
    this.conflictWithIds = const [],
  });

  final String id;
  final String kind; // event | task
  final String source; // google | microsoft | task
  final String sourceBadge;
  final String title;
  final String? description;
  final String? location;
  final DateTime startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final bool isCompleted;
  final String? priority;
  final String? category;
  final String? recurrence;
  final int? notificationId;
  final String? meetingLink;
  final bool hasConflict;
  final List<String> conflictWithIds;

  bool get isTask => kind == 'task';

  factory UnifiedAgendaItem.fromJson(Map<String, dynamic> json) {
    return UnifiedAgendaItem(
      id: (json['id'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'task',
      source: (json['source'] as String?) ?? 'task',
      sourceBadge: (json['sourceBadge'] as String?) ?? 'Tugas Harian',
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      location: json['location'] as String?,
      startAt:
          DateTime.tryParse(json['startAt']?.toString() ?? '') ?? DateTime.now(),
      endAt: json['endAt'] != null
          ? DateTime.tryParse(json['endAt'].toString())
          : null,
      isAllDay: json['isAllDay'] == true,
      isCompleted: json['isCompleted'] == true,
      priority: json['priority'] as String?,
      category: json['category'] as String?,
      recurrence: json['recurrence'] as String?,
      notificationId: (json['notificationId'] as num?)?.toInt(),
      meetingLink: json['meetingLink'] as String?,
      hasConflict: json['hasConflict'] == true,
      conflictWithIds: (json['conflictWithIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'source': source,
        'sourceBadge': sourceBadge,
        'title': title,
        'description': description,
        'location': location,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
        'isAllDay': isAllDay,
        'isCompleted': isCompleted,
        'priority': priority,
        'category': category,
        'recurrence': recurrence,
        'notificationId': notificationId,
        'meetingLink': meetingLink,
        'hasConflict': hasConflict,
        'conflictWithIds': conflictWithIds,
      };

  UnifiedAgendaItem copyWith({
    bool? isCompleted,
    DateTime? startAt,
  }) {
    return UnifiedAgendaItem(
      id: id,
      kind: kind,
      source: source,
      sourceBadge: sourceBadge,
      title: title,
      description: description,
      location: location,
      startAt: startAt ?? this.startAt,
      endAt: endAt,
      isAllDay: isAllDay,
      isCompleted: isCompleted ?? this.isCompleted,
      priority: priority,
      category: category,
      recurrence: recurrence,
      notificationId: notificationId,
      meetingLink: meetingLink,
      hasConflict: hasConflict,
      conflictWithIds: conflictWithIds,
    );
  }
}

class UnifiedAgendaResponse {
  const UnifiedAgendaResponse({
    required this.date,
    required this.demoMode,
    required this.connectedProviders,
    required this.conflictCount,
    required this.items,
  });

  final String date;
  final bool demoMode;
  final ConnectedProviders connectedProviders;
  final int conflictCount;
  final List<UnifiedAgendaItem> items;

  factory UnifiedAgendaResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>?) ?? const [];
    return UnifiedAgendaResponse(
      date: (json['date'] as String?) ?? DateTime.now().toIso8601String().substring(0, 10),
      demoMode: json['demoMode'] == true,
      connectedProviders: ConnectedProviders.fromJson(
        json['connectedProviders'] as Map<String, dynamic>?,
      ),
      conflictCount: (json['conflictCount'] as num?)?.toInt() ?? 0,
      items: rawItems
          .map((e) => UnifiedAgendaItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'demoMode': demoMode,
        'connectedProviders': connectedProviders.toJson(),
        'conflictCount': conflictCount,
        'items': items.map((e) => e.toJson()).toList(),
      };
}
