import '../lesson_decision/lesson_decision_models.dart';

const _lessonEditorAbsent = Object();

class LessonClientRef {
  const LessonClientRef({
    required this.type,
    required this.id,
    required this.label,
    this.branchId,
  });

  final String type;
  final String id;
  final String label;
  final String? branchId;

  String get key => '$type:$id';

  @override
  bool operator ==(Object other) =>
      other is LessonClientRef &&
      other.type == type &&
      other.id == id &&
      other.label == label &&
      other.branchId == branchId;

  @override
  int get hashCode => Object.hash(type, id, label, branchId);
}

class LessonEditorDraft {
  const LessonEditorDraft({
    required this.localStart,
    required this.durationMinutes,
    required this.isTrial,
    required this.completionType,
    required this.clientChargeType,
    this.client,
    this.teacherId,
    this.branchId,
    this.roomId,
    this.subscriptionId,
    this.settlementTypeKey,
    this.compensationRuleKey,
    this.compensationValueMinor,
    this.plannedSettlementReason = '',
  });

  final DateTime localStart;
  final int durationMinutes;
  final bool isTrial;
  final String completionType;
  final String clientChargeType;
  final LessonClientRef? client;
  final String? teacherId;
  final String? branchId;
  final String? roomId;
  final String? subscriptionId;
  final String? settlementTypeKey;
  final String? compensationRuleKey;
  final String? compensationValueMinor;
  final String plannedSettlementReason;

  LessonEditorDraft copyWith({
    DateTime? localStart,
    int? durationMinutes,
    bool? isTrial,
    String? completionType,
    String? clientChargeType,
    Object? client = _lessonEditorAbsent,
    Object? teacherId = _lessonEditorAbsent,
    Object? branchId = _lessonEditorAbsent,
    Object? roomId = _lessonEditorAbsent,
    Object? subscriptionId = _lessonEditorAbsent,
    Object? settlementTypeKey = _lessonEditorAbsent,
    Object? compensationRuleKey = _lessonEditorAbsent,
    Object? compensationValueMinor = _lessonEditorAbsent,
    String? plannedSettlementReason,
  }) => LessonEditorDraft(
    localStart: localStart ?? this.localStart,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    isTrial: isTrial ?? this.isTrial,
    completionType: completionType ?? this.completionType,
    clientChargeType: clientChargeType ?? this.clientChargeType,
    client: identical(client, _lessonEditorAbsent)
        ? this.client
        : client as LessonClientRef?,
    teacherId: identical(teacherId, _lessonEditorAbsent)
        ? this.teacherId
        : teacherId as String?,
    branchId: identical(branchId, _lessonEditorAbsent)
        ? this.branchId
        : branchId as String?,
    roomId: identical(roomId, _lessonEditorAbsent)
        ? this.roomId
        : roomId as String?,
    subscriptionId: identical(subscriptionId, _lessonEditorAbsent)
        ? this.subscriptionId
        : subscriptionId as String?,
    settlementTypeKey: identical(settlementTypeKey, _lessonEditorAbsent)
        ? this.settlementTypeKey
        : settlementTypeKey as String?,
    compensationRuleKey: identical(compensationRuleKey, _lessonEditorAbsent)
        ? this.compensationRuleKey
        : compensationRuleKey as String?,
    compensationValueMinor:
        identical(compensationValueMinor, _lessonEditorAbsent)
        ? this.compensationValueMinor
        : compensationValueMinor as String?,
    plannedSettlementReason:
        plannedSettlementReason ?? this.plannedSettlementReason,
  );
}

class LessonEditorSnapshot {
  const LessonEditorSnapshot({
    required this.lessonId,
    required this.expectedVersion,
    required this.rawLesson,
    required this.clientLocked,
    required this.initialSchedulePayload,
    required this.initialCompensationRuleKey,
    required this.initialCompensationValueMinor,
  });

  final String lessonId;
  final int? expectedVersion;
  final Map<String, dynamic> rawLesson;
  final bool clientLocked;
  final Map<String, dynamic> initialSchedulePayload;
  final String? initialCompensationRuleKey;
  final String? initialCompensationValueMinor;
}

class LessonEditorInitialInput {
  const LessonEditorInitialInput({
    required this.initialDate,
    required this.initialRoomId,
    required this.initialBranchId,
    required this.initialDurationMinutes,
    required this.lesson,
    required this.initialIsTrial,
    this.leadId,
    this.leadName,
    this.clientType,
    this.clientId,
    this.clientName,
  });

  final DateTime? initialDate;
  final String? initialRoomId;
  final String? initialBranchId;
  final int? initialDurationMinutes;
  final Map<String, dynamic>? lesson;
  final bool initialIsTrial;
  final String? leadId;
  final String? leadName;
  final String? clientType;
  final String? clientId;
  final String? clientName;
}

class LessonEditorSession {
  const LessonEditorSession({
    required this.draft,
    required this.snapshot,
    required this.seededClient,
    this.leadNoteSource,
  });

  final LessonEditorDraft draft;
  final LessonEditorSnapshot? snapshot;
  final LessonClientRef? seededClient;
  final String? leadNoteSource;

  bool get isEdit => snapshot != null;
  bool get isGroupEdit => isEdit && draft.client?.type == 'group';
}

class LessonEditorReferenceItem {
  const LessonEditorReferenceItem({
    required this.id,
    required this.label,
    required this.raw,
    this.branchId,
    this.status,
    this.assignedBranchIds = const {},
  });

  final String id;
  final String label;
  final Map<String, dynamic> raw;
  final String? branchId;
  final String? status;
  final Set<String> assignedBranchIds;
}

class LessonEditorReferenceState {
  LessonEditorReferenceState({
    required List<LessonEditorReferenceItem> teachers,
    required List<LessonEditorReferenceItem> clients,
    required List<LessonEditorReferenceItem> branches,
    required List<LessonEditorReferenceItem> rooms,
    required List<LessonEditorReferenceItem> subscriptions,
    required LessonDecisionCatalog? catalog,
  }) : teachers = _frozenReferenceItems(teachers),
       clients = _frozenReferenceItems(clients),
       branches = _frozenReferenceItems(branches),
       rooms = _frozenReferenceItems(rooms),
       subscriptions = _frozenReferenceItems(subscriptions),
       catalog = _frozenCatalog(catalog);

  const LessonEditorReferenceState.empty()
    : teachers = const [],
      clients = const [],
      branches = const [],
      rooms = const [],
      subscriptions = const [],
      catalog = null;

  final List<LessonEditorReferenceItem> teachers;
  final List<LessonEditorReferenceItem> clients;
  final List<LessonEditorReferenceItem> branches;
  final List<LessonEditorReferenceItem> rooms;
  final List<LessonEditorReferenceItem> subscriptions;
  final LessonDecisionCatalog? catalog;
}

List<LessonEditorReferenceItem> _frozenReferenceItems(
  Iterable<LessonEditorReferenceItem> items,
) => List.unmodifiable([
  for (final item in items)
    LessonEditorReferenceItem(
      id: item.id,
      label: item.label,
      raw: _frozenRaw(item.raw),
      branchId: item.branchId,
      status: item.status,
      assignedBranchIds: Set.unmodifiable(item.assignedBranchIds),
    ),
]);

LessonDecisionCatalog? _frozenCatalog(LessonDecisionCatalog? catalog) =>
    catalog == null
    ? null
    : LessonDecisionCatalog(
        settlementTypes: List.unmodifiable([
          for (final item in catalog.settlementTypes) _frozenCatalogItem(item),
        ]),
        compensationRules: List.unmodifiable([
          for (final item in catalog.compensationRules)
            _frozenCatalogItem(item),
        ]),
      );

LessonDecisionCatalogItem _frozenCatalogItem(LessonDecisionCatalogItem item) =>
    LessonDecisionCatalogItem(
      key: item.key,
      label: item.label,
      order: item.order,
      colorToken: item.colorToken,
      allowedContexts: List.unmodifiable(item.allowedContexts),
      mode: item.mode,
      value: item.value,
      hourShareBasisPoints: item.hourShareBasisPoints,
      fixedPenaltyMinor: item.fixedPenaltyMinor,
    );

Map<String, dynamic> _frozenRaw(Map<String, dynamic> row) => Map.unmodifiable({
  for (final entry in row.entries) entry.key: _frozenRawValue(entry.value),
});

Object? _frozenRawValue(Object? value) {
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries)
        entry.key: _frozenRawValue(entry.value),
    });
  }
  if (value is List) {
    return List.unmodifiable([for (final item in value) _frozenRawValue(item)]);
  }
  if (value is Set) {
    return Set.unmodifiable({for (final item in value) _frozenRawValue(item)});
  }
  return value;
}
