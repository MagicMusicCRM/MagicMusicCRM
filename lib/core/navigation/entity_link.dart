import 'dart:collection';

enum EntityLinkType {
  client,
  lesson,
  task,
  subscription,
  payment,
  user,
  homework,
  chat,
  report,
  teacher,
  group,
  room,
  branch,
  scheduleSeries,
  comment,
  clientSource,
  clientStatus,
  subscriptionPackage,
  unknown,
}

class EntityLinkFocus {
  EntityLinkFocus({this.focus, Map<String, dynamic> filter = const {}})
    : filter = UnmodifiableMapView(Map<String, dynamic>.from(filter));

  factory EntityLinkFocus.fromJson(Map<String, dynamic> json) {
    final rawFilter = json['filter'];
    return EntityLinkFocus(
      focus: json['focus']?.toString(),
      filter: rawFilter is Map
          ? rawFilter.map((key, value) => MapEntry(key.toString(), value))
          : const {},
    );
  }

  final String? focus;
  final Map<String, dynamic> filter;

  Map<String, dynamic> toJson() => {
    if (focus != null && focus!.isNotEmpty) 'focus': focus,
    if (filter.isNotEmpty) 'filter': filter,
  };
}

class EntityLink {
  const EntityLink({
    required this.entityType,
    required this.entityId,
    required this.rawEntityType,
    this.optionalFocus,
    this.version = schemaVersion,
  });

  factory EntityLink.typed({
    required EntityLinkType entityType,
    required String entityId,
    EntityLinkFocus? optionalFocus,
    String? variant,
  }) {
    return EntityLink(
      entityType: entityType,
      entityId: entityId.trim(),
      rawEntityType: variant ?? _canonicalType(entityType),
      optionalFocus: optionalFocus,
    );
  }

  factory EntityLink.fromJson(Map<String, dynamic> json) {
    final rawType = json['entityType']?.toString().trim() ?? '';
    final rawFocus = json['optionalFocus'];
    return EntityLink(
      version: (json['version'] as num?)?.toInt() ?? schemaVersion,
      entityType: _parseType(rawType),
      rawEntityType: rawType,
      entityId: json['entityId']?.toString().trim() ?? '',
      optionalFocus: rawFocus is Map
          ? EntityLinkFocus.fromJson(
              rawFocus.map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
    );
  }

  static const schemaVersion = 1;

  final int version;
  final EntityLinkType entityType;
  final String rawEntityType;
  final String entityId;
  final EntityLinkFocus? optionalFocus;

  bool get isSupported =>
      version == schemaVersion &&
      entityType != EntityLinkType.unknown &&
      entityId.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'version': version,
    'entityType': rawEntityType,
    'entityId': entityId,
    if (optionalFocus != null) 'optionalFocus': optionalFocus!.toJson(),
  };

  static EntityLinkType _parseType(String value) {
    return switch (value) {
      'client' || 'lead' || 'student' => EntityLinkType.client,
      'lesson' => EntityLinkType.lesson,
      'task' => EntityLinkType.task,
      'subscription' => EntityLinkType.subscription,
      'payment' => EntityLinkType.payment,
      'user' || 'profile' || 'staff' => EntityLinkType.user,
      'homework' => EntityLinkType.homework,
      'chat' => EntityLinkType.chat,
      'report' ||
      'overview' ||
      'client_status_list' ||
      'lesson_list' ||
      'school_finance_month' => EntityLinkType.report,
      'configuration' => EntityLinkType.report,
      'teacher' => EntityLinkType.teacher,
      'group' => EntityLinkType.group,
      'room' => EntityLinkType.room,
      'branch' => EntityLinkType.branch,
      'schedule_series' => EntityLinkType.scheduleSeries,
      'comment' => EntityLinkType.comment,
      'client_source' => EntityLinkType.clientSource,
      'client_status' => EntityLinkType.clientStatus,
      'subscription_package' => EntityLinkType.subscriptionPackage,
      _ => EntityLinkType.unknown,
    };
  }

  static String _canonicalType(EntityLinkType type) {
    return switch (type) {
      EntityLinkType.client => 'client',
      EntityLinkType.lesson => 'lesson',
      EntityLinkType.task => 'task',
      EntityLinkType.subscription => 'subscription',
      EntityLinkType.payment => 'payment',
      EntityLinkType.user => 'user',
      EntityLinkType.homework => 'homework',
      EntityLinkType.chat => 'chat',
      EntityLinkType.report => 'report',
      EntityLinkType.teacher => 'teacher',
      EntityLinkType.group => 'group',
      EntityLinkType.room => 'room',
      EntityLinkType.branch => 'branch',
      EntityLinkType.scheduleSeries => 'schedule_series',
      EntityLinkType.comment => 'comment',
      EntityLinkType.clientSource => 'client_source',
      EntityLinkType.clientStatus => 'client_status',
      EntityLinkType.subscriptionPackage => 'subscription_package',
      EntityLinkType.unknown => 'unknown',
    };
  }
}
