enum LessonDecisionOperation {
  reschedule,
  cancel,
  settle,
  plannedSettlement,
  correction,
}

extension LessonDecisionOperationContract on LessonDecisionOperation {
  String get apiKey => switch (this) {
    LessonDecisionOperation.reschedule => 'reschedule',
    LessonDecisionOperation.cancel => 'cancel',
    LessonDecisionOperation.settle => 'settle',
    LessonDecisionOperation.plannedSettlement => 'planned-settlement',
    LessonDecisionOperation.correction => 'settlement-correction',
  };

  String get title => switch (this) {
    LessonDecisionOperation.reschedule => 'Перенос занятия',
    LessonDecisionOperation.cancel => 'Отмена занятия',
    LessonDecisionOperation.settle => 'Исправление расчёта',
    LessonDecisionOperation.plannedSettlement => 'Изменение расчёта',
    LessonDecisionOperation.correction => 'Корректировка расчёта',
  };

  String get actionLabel => switch (this) {
    LessonDecisionOperation.reschedule => 'Перенести',
    LessonDecisionOperation.cancel => 'Отменить занятие',
    LessonDecisionOperation.settle => 'Исправить расчёт',
    LessonDecisionOperation.plannedSettlement => 'Изменить расчёт',
    LessonDecisionOperation.correction => 'Сохранить корректировку',
  };

  String get catalogContext => switch (this) {
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
    );
  }
}

class LessonDecisionCatalog {
  const LessonDecisionCatalog({
    required this.settlementTypes,
    required this.compensationRules,
  });

  final List<LessonDecisionCatalogItem> settlementTypes;
  final List<LessonDecisionCatalogItem> compensationRules;

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
  Map<String, dynamic> get financial => _map(raw['financialPreview']);
  List<Map<String, dynamic>> get violations => _maps(raw['violations']);
  List<String> get warnings => [
    for (final warning in raw['warnings'] as List? ?? const [])
      warning.toString(),
  ];
}

class LessonDecisionParticipant {
  const LessonDecisionParticipant({required this.id, required this.name});

  final String id;
  final String name;
}

class LessonDecisionRequest {
  const LessonDecisionRequest({
    required this.operation,
    required this.lesson,
    this.successor,
    this.initialSettlementTypeKey,
    this.initialCompensationRuleKey,
    this.initialCompensationValueMinor,
  });

  final LessonDecisionOperation operation;
  final Map<String, dynamic> lesson;
  final Map<String, dynamic>? successor;
  final String? initialSettlementTypeKey;
  final String? initialCompensationRuleKey;
  final String? initialCompensationValueMinor;
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _maps(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is Map) Map<String, dynamic>.from(item),
];
