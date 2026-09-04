enum LessonDecisionOperation {
  edit,
  reschedule,
  cancel,
  settle,
  plannedSettlement,
  correction,
}

extension LessonDecisionOperationContract on LessonDecisionOperation {
  String get apiKey => switch (this) {
    LessonDecisionOperation.edit => 'planned-settlement',
    LessonDecisionOperation.reschedule => 'reschedule',
    LessonDecisionOperation.cancel => 'cancel',
    LessonDecisionOperation.settle => 'settle',
    LessonDecisionOperation.plannedSettlement => 'planned-settlement',
    LessonDecisionOperation.correction => 'settlement-correction',
  };

  String get title => switch (this) {
    LessonDecisionOperation.edit => 'Изменение занятия',
    LessonDecisionOperation.reschedule => 'Перенос занятия',
    LessonDecisionOperation.cancel => 'Отмена занятия',
    LessonDecisionOperation.settle => 'Исправление расчёта',
    LessonDecisionOperation.plannedSettlement => 'Изменение расчёта',
    LessonDecisionOperation.correction => 'Корректировка расчёта',
  };

  String get actionLabel => switch (this) {
    LessonDecisionOperation.edit => 'Сохранить изменения',
    LessonDecisionOperation.reschedule => 'Перенести',
    LessonDecisionOperation.cancel => 'Отменить занятие',
    LessonDecisionOperation.settle => 'Исправить расчёт',
    LessonDecisionOperation.plannedSettlement => 'Изменить расчёт',
    LessonDecisionOperation.correction => 'Сохранить корректировку',
  };

  String get catalogContext => switch (this) {
    LessonDecisionOperation.edit ||
    LessonDecisionOperation.plannedSettlement ||
    LessonDecisionOperation.correction => 'settle',
    _ => apiKey,
  };
}

class LessonDecisionCatalogItem {
  const LessonDecisionCatalogItem({
    required this.key,
    required this.label,
    required this.order,
    this.colorToken,
    this.allowedContexts = const [],
    this.mode,
    this.value = '0',
    this.hourShareBasisPoints = 0,
    this.fixedPenaltyMinor = '0',
    this.clientDurationMode,
    this.teacherDurationMode,
    this.defaultTeacherCompensationRuleKey,
  });

  final String key;
  final String label;
  final int order;
  final String? colorToken;
  final List<String> allowedContexts;
  final String? mode;
  final String value;
  final int hourShareBasisPoints;
  final String fixedPenaltyMinor;
  final String? clientDurationMode;
  final String? teacherDurationMode;
  final String? defaultTeacherCompensationRuleKey;

  factory LessonDecisionCatalogItem.fromJson(Map<String, dynamic> json) {
    return LessonDecisionCatalogItem(
      key: json['stableKey']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
      colorToken: json['colorToken']?.toString(),
      allowedContexts: [
        for (final value in json['allowedContexts'] as List? ?? const [])
          value.toString(),
      ],
      mode: json['mode']?.toString(),
      value: json['value']?.toString() ?? '0',
      hourShareBasisPoints:
          (json['hourShareBasisPoints'] as num?)?.toInt() ?? 0,
      fixedPenaltyMinor: json['fixedPenaltyMinor']?.toString() ?? '0',
      clientDurationMode: json['clientDurationMode']?.toString(),
      teacherDurationMode: json['teacherDurationMode']?.toString(),
      defaultTeacherCompensationRuleKey:
          json['defaultTeacherCompensationRuleKey']?.toString(),
    );
  }
}

class LessonDecisionCatalog {
  const LessonDecisionCatalog({
    required this.settlementTypes,
    required this.compensationRules,
    this.defaultDurationMinutes,
  });

  final List<LessonDecisionCatalogItem> settlementTypes;
  final List<LessonDecisionCatalogItem> compensationRules;
  final int? defaultDurationMinutes;

  factory LessonDecisionCatalog.fromJson(
    Map<String, dynamic> json,
    LessonDecisionOperation operation,
  ) {
    List<LessonDecisionCatalogItem> parse(String key) => [
      for (final item in json[key] as List? ?? const [])
        if (item is Map)
          LessonDecisionCatalogItem.fromJson(Map<String, dynamic>.from(item)),
    ]..sort((left, right) => left.order.compareTo(right.order));

    return LessonDecisionCatalog(
      settlementTypes: parse('settlementTypes')
          .where(
            (item) => item.allowedContexts.contains(operation.catalogContext),
          )
          .toList(),
      compensationRules: parse('teacherCompensationRules'),
      defaultDurationMinutes: (json['defaultLessonDurationMinutes'] as num?)
          ?.toInt(),
    );
  }
}

class LessonDecisionPreview {
  const LessonDecisionPreview(this.raw);

  final Map<String, dynamic> raw;

  bool get canConfirm => raw['canConfirm'] == true;
  String? get token => raw['previewToken']?.toString();
  Map<String, dynamic> get source => _map(raw['source']);
  Map<String, dynamic> get successor => _map(raw['successor']);
  Map<String, dynamic> get financial =>
      _map(raw['successorPlannedSettlementPreview'] ?? raw['financialPreview']);
  List<Map<String, dynamic>> get violations => _maps(raw['violations']);
  List<String> get warnings => [
    for (final warning in raw['warnings'] as List? ?? const [])
      warning.toString(),
  ];
}

class LessonDecisionParticipant {
  const LessonDecisionParticipant({
    required this.id,
    required this.name,
    this.isStudent = true,
  });

  final String id;
  final String name;
  final bool isStudent;
}

class LessonDecisionClientDraft {
  const LessonDecisionClientDraft({
    required this.clientId,
    required this.chargeType,
    required this.chargeDurationMinutes,
    this.preferredChargeType,
    this.payerStudentId,
    this.subscriptionId,
    this.retainedFunding = const {},
  });

  final String clientId;
  final String chargeType;
  final int? chargeDurationMinutes;
  final String? preferredChargeType;
  final String? payerStudentId;
  final String? subscriptionId;
  final Map<String, dynamic> retainedFunding;

  Map<String, dynamic> toJson() => {
    ...retainedFunding,
    'clientId': clientId,
    'chargeType': chargeType,
    if (preferredChargeType != null) 'preferredChargeType': preferredChargeType,
    if (payerStudentId != null) 'payerStudentId': payerStudentId,
    if (subscriptionId != null) 'subscriptionId': subscriptionId,
    if (chargeDurationMinutes != null)
      'chargeDurationMinutes': chargeDurationMinutes,
  };
}

class LessonDecisionDraft {
  const LessonDecisionDraft({
    required this.settlementTypeKey,
    required this.teacherCompensationRuleKey,
    required this.clientDecisions,
    required this.teacherCreditedDurationMinutes,
  });

  final String settlementTypeKey;
  final String teacherCompensationRuleKey;
  final List<LessonDecisionClientDraft> clientDecisions;
  final int? teacherCreditedDurationMinutes;

  factory LessonDecisionDraft.forCancel({
    required LessonDecisionCatalog catalog,
    required Map<String, dynamic> lesson,
    required List<LessonDecisionParticipant> clients,
    List<Map<String, dynamic>> existingClientDecisions = const [],
  }) {
    final settlement = catalog.settlementTypes.where(
      (item) => item.key == 'unpaid_miss',
    );
    if (settlement.isEmpty) {
      throw StateError('Не найден тип расчёта для неоплачиваемого пропуска.');
    }
    final policy = settlement.single;
    final durationMinutes =
        lessonDecisionIntegerMinutes(
          lesson['duration_minutes'] ?? lesson['durationMinutes'],
        ) ??
        catalog.defaultDurationMinutes ??
        60;
    final teacherRuleKey = policy.defaultTeacherCompensationRuleKey ?? 'none';
    final existingByClientId = <String, Map<String, dynamic>>{
      for (final decision in existingClientDecisions)
        if (decision['clientId']?.toString() case final String clientId)
          clientId: decision,
    };
    return LessonDecisionDraft(
      settlementTypeKey: policy.key,
      teacherCompensationRuleKey: teacherRuleKey,
      clientDecisions: List.unmodifiable([
        for (final client in clients)
          _cancelClientDraft(
            client,
            existingByClientId[client.id],
            policy.clientDurationMode,
            durationMinutes,
          ),
      ]),
      teacherCreditedDurationMinutes: _recommendedDuration(
        policy.teacherDurationMode,
        durationMinutes,
      ),
    );
  }
}

LessonDecisionClientDraft _cancelClientDraft(
  LessonDecisionParticipant client,
  Map<String, dynamic>? existing,
  String? durationMode,
  int durationMinutes,
) {
  final preferredChargeType = switch (existing?['chargeType']?.toString()) {
    'subscription' => 'subscription',
    'personal_account' => 'personal_account',
    _ => null,
  };
  final retainedFunding = <String, dynamic>{
    for (final key in const ['basePriceMinor', 'discount', 'surcharge'])
      if (existing?[key] != null) key: existing![key],
  };
  return LessonDecisionClientDraft(
    clientId: client.id,
    chargeType: 'none',
    chargeDurationMinutes: _recommendedDuration(durationMode, durationMinutes),
    preferredChargeType: preferredChargeType,
    payerStudentId: existing?['payerStudentId']?.toString(),
    subscriptionId: existing?['subscriptionId']?.toString(),
    retainedFunding: Map.unmodifiable(retainedFunding),
  );
}

int? _recommendedDuration(String? mode, int lessonDurationMinutes) =>
    switch (mode) {
      'zero' => 0,
      'full' => lessonDurationMinutes,
      _ => null,
    };

class LessonDecisionSubscription {
  const LessonDecisionSubscription({required this.id, required this.label});

  final String id;
  final String label;
}

class LessonDecisionRequest {
  const LessonDecisionRequest({
    required this.operation,
    required this.lesson,
    this.successor,
    this.successorFinancialDecision,
    this.initialSettlementTypeKey,
    this.resources,
    this.initialCompensationRuleKey,
    this.initialCompensationValueMinor,
  });

  final LessonDecisionOperation operation;
  final Map<String, dynamic> lesson;
  final Map<String, dynamic>? successor;
  final Map<String, dynamic>? successorFinancialDecision;
  final String? initialSettlementTypeKey;
  final Map<String, dynamic>? resources;
  final String? initialCompensationRuleKey;
  final String? initialCompensationValueMinor;
}

abstract interface class LessonDecisionFormLifecycle {
  LessonDecisionOperation get operation;
  Map<String, dynamic> get lesson;
  Map<String, dynamic>? get successor;
  String? get initialSettlementTypeKey;
  String? get initialCompensationRuleKey;
  String? get initialCompensationValueMinor;
  int? get initialTeacherCreditedDurationMinutes;
  String? get initialTeacherCompensationSource;
  List<Map<String, dynamic>> get initialClientDecisions;
  bool get isGroupLesson;
  List<LessonDecisionParticipant> get groupParticipants;
  List<LessonDecisionParticipant> get settlementClients;
  Map<String, String> get participantNames;
  bool get isCompletedReschedule;
  bool get canManageTeacherCompensation;

  Future<LessonDecisionCatalog> loadCatalog();
  Future<List<LessonDecisionParticipant>> searchPayers(String query);
  Future<List<LessonDecisionSubscription>> loadSubscriptions(String payerId);

  Future<LessonDecisionPreview> preview({
    required String reason,
    required String settlementTypeKey,
    required String compensationRuleKey,
    String? compensationValueMinor,
    int? teacherCreditedDurationMinutes,
    String? teacherCompensationSource,
    List<Map<String, dynamic>> clientDecisions = const [],
  });

  Future<Map<String, dynamic>> commit(LessonDecisionPreview preview);

  Future<Object?> recoverStaleCommit(Object error);
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _maps(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is Map) Map<String, dynamic>.from(item),
];

/// Keep the editor's integer basis points separate from the existing HTTP DTO.
Map<String, dynamic> normalizeLessonClientDecision(Map<String, dynamic> value) {
  final discount = value['discount'];
  final surcharge = value['surcharge'];
  return {
    ...value,
    if (discount is Map)
      'discount': {
        ...discount,
        if (discount['type'] == 'percent' && discount['percent'] is num)
          'percentBasisPoints': ((discount['percent'] as num) * 100).round(),
      }..remove('percent'),
    if (surcharge is Map)
      'surcharge': {
        if (surcharge['amountMinor'] != null) 'type': 'fixed',
        ...surcharge,
      },
  };
}

List<Map<String, dynamic>> lessonClientDecisionsPayload(
  List<Map<String, dynamic>> decisions,
) => [
  for (final row in decisions)
    {
      'clientId': row['clientId'],
      if (row['settlementTypeKey'] != null)
        'settlementTypeKey': row['settlementTypeKey'],
      if (lessonDecisionIntegerMinutes(row['chargeDurationMinutes'])
          case final int minutes)
        'chargeDurationMinutes': minutes,
      if (row['chargeType'] != null) 'chargeType': row['chargeType'],
      if (row['chargeType'] != 'none' && row['payerStudentId'] != null)
        'payerStudentId': row['payerStudentId'],
      if (row['chargeType'] != 'personal_account' &&
          row['chargeType'] != 'none' &&
          row['subscriptionId'] != null)
        'subscriptionId': row['subscriptionId'],
      if (row['chargeType'] == 'personal_account') ...{
        if (row['basePriceMinor'] != null)
          'basePriceMinor': row['basePriceMinor'],
        if (row['discount'] case final Map discount
            when discount['type'] == 'percent' || discount['type'] == 'fixed')
          'discount': {
            'type': discount['type'],
            'reason': discount['reason'],
            if (discount['type'] == 'percent')
              'percent': discount['percentBasisPoints'] is num
                  ? (discount['percentBasisPoints'] as num) / 100
                  : discount['percent'],
            if (discount['type'] == 'fixed')
              'fixedMinor': discount['fixedMinor'],
          },
        if (row['surcharge'] case final Map surcharge
            when surcharge['type'] != 'none' &&
                surcharge['amountMinor'] != null)
          'surcharge': {
            'amountMinor': surcharge['amountMinor'],
            'reason': surcharge['reason'],
          },
      },
    },
];

int? lessonDecisionIntegerMinutes(Object? value) => switch (value) {
  int value => value,
  num value when value.isFinite && value == value.roundToDouble() =>
    value.toInt(),
  String value => int.tryParse(value),
  _ => null,
};
