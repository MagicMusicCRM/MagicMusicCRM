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
      name: _requiredString(json, 'name', 'actor'),
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
      type: _requiredString(json, 'type', 'target'),
      id: _nullableString(json['id']),
      label: _requiredString(json, 'label', 'target'),
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
      key: _requiredString(json, 'key', 'change'),
      label: _requiredString(json, 'label', 'change'),
      before: _nullableString(json['before']),
      after: _nullableString(json['after']),
    );
  }
}

class AuditPresentationEvent {
  AuditPresentationEvent({
    required this.id,
    required this.actionKey,
    required this.title,
    required this.summary,
    required this.reason,
    required this.actor,
    required this.target,
    required List<AuditPresentationChange> changes,
    required this.occurredAt,
  }) : changes = List.unmodifiable(changes);

  final String id;
  final String actionKey;
  final String title;
  final String? summary;
  final String? reason;
  final AuditPresentationActor actor;
  final AuditPresentationTarget target;
  final List<AuditPresentationChange> changes;
  final DateTime occurredAt;

  factory AuditPresentationEvent.fromJson(Map<String, dynamic> json) {
    final actor = _requiredMap(json, 'actor');
    final target = _requiredMap(json, 'target');
    final changes = _requiredList(json, 'changes');

    return AuditPresentationEvent(
      id: _requiredString(json, 'id', 'event'),
      actionKey: _requiredString(json, 'actionKey', 'event'),
      title: _requiredString(json, 'title', 'event'),
      summary: _nullableString(json['summary']),
      reason: _nullableString(json['reason']),
      actor: AuditPresentationActor.fromJson(actor),
      target: AuditPresentationTarget.fromJson(target),
      changes: changes.indexed
          .map((entry) {
            final change = entry.$2;
            if (change is! Map) {
              throw FormatException(
                'Invalid audit change at index ${entry.$1}.',
              );
            }
            try {
              return AuditPresentationChange.fromJson(
                Map<String, dynamic>.from(change),
              );
            } on TypeError {
              throw FormatException(
                'Invalid audit change at index ${entry.$1}.',
              );
            }
          })
          .toList(growable: false),
      occurredAt: _requiredDateTime(json, 'occurredAt'),
    );
  }
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  final parsed = value is DateTime
      ? value
      : value is String
      ? DateTime.tryParse(value)
      : null;
  if (parsed == null) throw FormatException('Invalid audit field: $key.');
  return parsed;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('Invalid audit field: $key.');
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw FormatException('Invalid audit field: $key.');
  }
}

List<dynamic> _requiredList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('Invalid audit field: $key.');
  return value;
}

String _requiredString(Map<String, dynamic> json, String key, String context) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid audit $context field: $key.');
  }
  return value;
}

String? _nullableString(Object? value) => value is String ? value : null;
