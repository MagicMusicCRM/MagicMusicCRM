/// Typed, user-safe representation of an audit event returned by the API.
class AuditPresentationActor {
  const AuditPresentationActor({
    required this.id,
    required this.name,
    required this.role,
  });

  final String? id;
  final String name;
  final String? role;

  factory AuditPresentationActor.fromJson(Map<String, dynamic> json) {
    return AuditPresentationActor(
      id: _nullableString(json['id']),
      name: _nullableString(json['name']) ?? 'Неизвестный пользователь',
      role: _nullableString(json['role']),
    );
  }
}

class AuditPresentationTarget {
  const AuditPresentationTarget({
    required this.type,
    required this.id,
    required this.label,
    required this.displayName,
    required this.routeType,
  });

  final String type;
  final String? id;
  final String label;
  final String? displayName;
  final String? routeType;

  factory AuditPresentationTarget.fromJson(Map<String, dynamic> json) {
    return AuditPresentationTarget(
      type: _nullableString(json['type']) ?? '',
      id: _nullableString(json['id']),
      label: _nullableString(json['label']) ?? '',
      displayName: _nullableString(json['displayName']),
      routeType: _nullableString(json['routeType']),
    );
  }
}

class AuditPresentationChange {
  const AuditPresentationChange({
    required this.key,
    required this.label,
    required this.before,
    required this.after,
  });

  final String key;
  final String label;
  final String? before;
  final String? after;

  factory AuditPresentationChange.fromJson(Map<String, dynamic> json) {
    return AuditPresentationChange(
      key: _nullableString(json['key']) ?? '',
      label: _nullableString(json['label']) ?? '',
      before: _nullableString(json['before']),
      after: _nullableString(json['after']),
    );
  }
}

class AuditPresentationEvent {
  const AuditPresentationEvent({
    required this.id,
    required this.actionKey,
    required this.title,
    required this.summary,
    required this.reason,
    required this.actor,
    required this.target,
    required this.changes,
    required this.occurredAt,
  });

  final String id;
  final String actionKey;
  final String title;
  final String? summary;
  final String? reason;
  final AuditPresentationActor actor;
  final AuditPresentationTarget target;
  final List<AuditPresentationChange> changes;
  final DateTime? occurredAt;

  factory AuditPresentationEvent.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    final target = json['target'];
    final changes = json['changes'];

    return AuditPresentationEvent(
      id: _nullableString(json['id']) ?? '',
      actionKey: _nullableString(json['actionKey']) ?? '',
      title: _nullableString(json['title']) ?? '',
      summary: _nullableString(json['summary']),
      reason: _nullableString(json['reason']),
      actor: AuditPresentationActor.fromJson(_jsonMap(actor)),
      target: AuditPresentationTarget.fromJson(_jsonMap(target)),
      changes: changes is List
          ? changes
                .whereType<Map>()
                .map(
                  (change) => AuditPresentationChange.fromJson(
                    Map<String, dynamic>.from(change),
                  ),
                )
                .toList(growable: false)
          : const [],
      occurredAt: _dateTime(json['occurredAt']),
    );
  }
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is! String) return null;
  return DateTime.tryParse(value);
}

Map<String, dynamic> _jsonMap(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

String? _nullableString(Object? value) => value is String ? value : null;
