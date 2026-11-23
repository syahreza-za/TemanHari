class ProviderStatus {
  const ProviderStatus({required this.connected, this.email});

  final bool connected;
  final String? email;

  factory ProviderStatus.fromJson(Map<String, dynamic> json) {
    return ProviderStatus(
      connected: json['connected'] == true,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'connected': connected, 'email': email};
}

class ConnectedProviders {
  const ConnectedProviders({
    required this.google,
    required this.microsoft,
  });

  final ProviderStatus google;
  final ProviderStatus microsoft;

  factory ConnectedProviders.empty() => const ConnectedProviders(
        google: ProviderStatus(connected: false),
        microsoft: ProviderStatus(connected: false),
      );

  factory ConnectedProviders.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ConnectedProviders.empty();
    return ConnectedProviders(
      google: ProviderStatus.fromJson(
        (json['google'] as Map<String, dynamic>?) ?? const {},
      ),
      microsoft: ProviderStatus.fromJson(
        (json['microsoft'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'google': google.toJson(),
        'microsoft': microsoft.toJson(),
      };
}

class ServerCapabilities {
  const ServerCapabilities({
    this.gemini = false,
    this.googleOAuth = false,
    this.microsoftOAuth = false,
    this.firebase = false,
  });

  final bool gemini;
  final bool googleOAuth;
  final bool microsoftOAuth;
  final bool firebase;

  factory ServerCapabilities.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ServerCapabilities();
    return ServerCapabilities(
      gemini: json['gemini'] == true,
      googleOAuth: json['googleOAuth'] == true,
      microsoftOAuth: json['microsoftOAuth'] == true,
      firebase: json['firebase'] == true,
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.nickname,
    required this.aiPersona,
    required this.voiceEnabled,
    required this.ttsSpeechRate,
    required this.demoMode,
    required this.quietHoursEnabled,
    required this.quietStart,
    required this.quietEnd,
    required this.timezone,
    required this.connectedProviders,
  });

  final String id;
  final String nickname;
  final String aiPersona; // santai | tenang | ceria
  final bool voiceEnabled;
  final double ttsSpeechRate;
  final bool demoMode;
  final bool quietHoursEnabled;
  final String quietStart;
  final String quietEnd;
  final String timezone;
  final ConnectedProviders connectedProviders;

  factory UserProfile.defaultOffline() => UserProfile(
        id: 'offline-local',
        nickname: 'Teman',
        aiPersona: 'santai',
        voiceEnabled: true,
        ttsSpeechRate: 0.48,
        demoMode: true,
        quietHoursEnabled: true,
        quietStart: '22:00',
        quietEnd: '06:30',
        timezone: 'Asia/Jakarta',
        connectedProviders: ConnectedProviders.empty(),
      );

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] as String?) ?? 'local',
      nickname: (json['nickname'] as String?) ?? 'Teman',
      aiPersona: (json['aiPersona'] as String?) ?? 'santai',
      voiceEnabled: json['voiceEnabled'] != false,
      ttsSpeechRate: (json['ttsSpeechRate'] as num?)?.toDouble() ?? 0.48,
      demoMode: json['demoMode'] != false,
      quietHoursEnabled: json['quietHoursEnabled'] != false,
      quietStart: (json['quietStart'] as String?) ?? '22:00',
      quietEnd: (json['quietEnd'] as String?) ?? '06:30',
      timezone: (json['timezone'] as String?) ?? 'Asia/Jakarta',
      connectedProviders: ConnectedProviders.fromJson(
        json['connectedProviders'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'aiPersona': aiPersona,
        'voiceEnabled': voiceEnabled,
        'ttsSpeechRate': ttsSpeechRate,
        'demoMode': demoMode,
        'quietHoursEnabled': quietHoursEnabled,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'timezone': timezone,
        'connectedProviders': connectedProviders.toJson(),
      };

  UserProfile copyWith({
    String? nickname,
    String? aiPersona,
    bool? voiceEnabled,
    double? ttsSpeechRate,
    bool? demoMode,
    bool? quietHoursEnabled,
    String? quietStart,
    String? quietEnd,
    String? timezone,
    ConnectedProviders? connectedProviders,
  }) {
    return UserProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      aiPersona: aiPersona ?? this.aiPersona,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      ttsSpeechRate: ttsSpeechRate ?? this.ttsSpeechRate,
      demoMode: demoMode ?? this.demoMode,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
      timezone: timezone ?? this.timezone,
      connectedProviders: connectedProviders ?? this.connectedProviders,
    );
  }
}

class UserMemoryItem {
  const UserMemoryItem({
    required this.id,
    required this.category,
    required this.content,
  });

  final String id;
  final String category;
  final String content;

  factory UserMemoryItem.fromJson(Map<String, dynamic> json) {
    return UserMemoryItem(
      id: (json['id'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'fact',
      content: (json['content'] as String?) ?? '',
    );
  }
}
