import 'dart:collection';

const _unset = Object();

Object? _deepFreeze(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<String, dynamic>({
      for (final entry in value.entries)
        entry.key.toString(): _deepFreeze(entry.value),
    });
  }
  if (value is List) {
    return UnmodifiableListView<dynamic>(
      value.map(_deepFreeze).toList(growable: false),
    );
  }
  return value;
}

Map<String, dynamic> _deepFreezeMap(Map<String, dynamic> value) =>
    _deepFreeze(value)! as Map<String, dynamic>;

class ReferenceCatalogLifecycleState {
  ReferenceCatalogLifecycleState({
    required this.entityType,
    required Map<String, dynamic> entity,
    required this.loading,
    required this.saving,
    this.entitySyncRevision = 0,
    Map<String, dynamic>? preview,
    List<Map<String, dynamic>> history = const [],
    this.error,
  }) : entity = _deepFreezeMap(entity),
       preview = preview == null ? null : _deepFreezeMap(preview),
       history = UnmodifiableListView(
         history.map(_deepFreezeMap).toList(growable: false),
       );

  factory ReferenceCatalogLifecycleState.initial({
    required String entityType,
    required Map<String, dynamic> item,
  }) => ReferenceCatalogLifecycleState(
    entityType: entityType,
    entity: item,
    loading: true,
    saving: false,
  );

  final String entityType;
  final Map<String, dynamic> entity;
  final bool loading;
  final bool saving;
  final int entitySyncRevision;
  final Map<String, dynamic>? preview;
  final List<Map<String, dynamic>> history;
  final String? error;

  String get id => entity['id']?.toString() ?? '';
  bool get archived =>
      (entity['lifecycleState'] ?? entity['lifecycle_state']) == 'archived';
  bool get branchLink => entityType == 'branch_discipline';
  bool get canRename => preview?['canRename'] == true && !branchLink;
  bool get canCommit => archived
      ? (preview?['canRestore'] == true)
      : (preview?['canArchive'] == true);
  int get version {
    final raw = entity['version'];
    return raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1;
  }

  String get entityLabel => switch (entityType) {
    'discipline' => 'Дисциплина',
    'loss_reason' => 'Причина отказа',
    _ => 'Дисциплина филиала',
  };

  List<Map<String, dynamic>> get blockers {
    final raw = preview?['blockers'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<MapEntry<dynamic, dynamic>> get impactValues {
    final raw = preview?['impact'];
    if (raw is! Map) return const [];
    return raw.entries
        .where((entry) => entry.value is num && (entry.value as num) > 0)
        .toList(growable: false);
  }

  String historyTitle(Map<String, dynamic> item) => switch (item['operation']) {
    'rename' => 'Название изменено',
    'restore' => 'Запись восстановлена',
    'unassign' => 'Дисциплина отвязана',
    _ => 'Запись архивирована',
  };

  ReferenceCatalogLifecycleState copyWith({
    Map<String, dynamic>? entity,
    bool? loading,
    bool? saving,
    int? entitySyncRevision,
    Object? preview = _unset,
    List<Map<String, dynamic>>? history,
    Object? error = _unset,
  }) => ReferenceCatalogLifecycleState(
    entityType: entityType,
    entity: entity ?? this.entity,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    entitySyncRevision: entitySyncRevision ?? this.entitySyncRevision,
    preview: identical(preview, _unset)
        ? this.preview
        : preview as Map<String, dynamic>?,
    history: history ?? this.history,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}
