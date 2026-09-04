import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'lesson_decision_models.dart';

typedef LessonDecisionCommitted =
    Future<void> Function(Map<String, dynamic> result);

class LessonDecisionController implements LessonDecisionFormLifecycle {
  LessonDecisionController({
    required MagicCrmService crm,
    required this.operation,
    required this.lesson,
    required this.canManageTeacherCompensation,
    this.successor,
    this.resources,
    String? initialSettlementTypeKey,
    String? initialCompensationRuleKey,
    String? initialCompensationValueMinor,
    this.afterCommit,
  }) : _crm = crm,
       _initialSettlementTypeKey = initialSettlementTypeKey,
       _initialCompensationRuleKey = initialCompensationRuleKey,
       _initialCompensationValueMinor = initialCompensationValueMinor,
       _expectedVersion = (lesson['version'] as num?)?.toInt();

  final MagicCrmService _crm;
  @override
  final LessonDecisionOperation operation;
  @override
  final Map<String, dynamic> lesson;
  @override
  final bool canManageTeacherCompensation;
  @override
  final Map<String, dynamic>? successor;
  final String? _initialSettlementTypeKey;
  final String? _initialCompensationRuleKey;
  final String? _initialCompensationValueMinor;
  final LessonDecisionCommitted? afterCommit;
  final Map<String, dynamic>? resources;

  Map<String, dynamic>? get _initialFinancialDecision {
    final value = lesson['financial_decision'] ?? lesson['financialDecision'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  String? get initialSettlementTypeKey =>
      operation == LessonDecisionOperation.cancel
      ? 'unpaid_miss'
      : _initialSettlementTypeKey ??
            _initialFinancialDecision?['settlementTypeKey']?.toString();

  @override
  String? get initialCompensationRuleKey =>
      operation == LessonDecisionOperation.cancel
      ? 'none'
      : _initialCompensationRuleKey ??
            _initialFinancialDecision?['teacherCompensationRuleKey']
                ?.toString();

  @override
  String? get initialCompensationValueMinor =>
      operation == LessonDecisionOperation.cancel
      ? null
      : _initialCompensationValueMinor ??
            _initialFinancialDecision?['teacherCompensationValueMinor']
                ?.toString();

  @override
  int? get initialTeacherCreditedDurationMinutes =>
      operation == LessonDecisionOperation.cancel
      ? 0
      : lessonDecisionIntegerMinutes(
          _initialFinancialDecision?['teacherCreditedDurationMinutes'],
        );

  @override
  String? get initialTeacherCompensationSource =>
      operation == LessonDecisionOperation.cancel
      ? 'automatic'
      : _initialFinancialDecision?['teacherCompensationSource']?.toString();

  @override
  List<Map<String, dynamic>> get initialClientDecisions {
    final stored = [
      for (final item
          in _initialFinancialDecision?['clientDecisions'] as List? ?? const [])
        if (item is Map)
          Map<String, dynamic>.unmodifiable(
            normalizeLessonClientDecision(Map<String, dynamic>.from(item)),
          ),
    ];
    if (stored.isNotEmpty) return List.unmodifiable(stored);
    return List.unmodifiable([
      for (final participant in settlementClients)
        if (!participant.isStudent)
          Map<String, dynamic>.unmodifiable({
            'clientId': participant.id,
            'chargeType': 'none',
          }),
    ]);
  }

  @override
  bool get isGroupLesson {
    final groupId = lesson['group_id'] ?? lesson['groupId'];
    return groupId?.toString().isNotEmpty == true;
  }

  @override
  List<LessonDecisionParticipant> get groupParticipants {
    final raw = lesson['group_participants'] ?? lesson['groupParticipants'];
    final result = <LessonDecisionParticipant>[];
    final seen = <String>{};
    for (final item in raw as List? ?? const []) {
      if (item is! Map) continue;
      final participant = Map<String, dynamic>.from(item);
      final id =
          (participant['clientId'] ??
                  participant['client_id'] ??
                  participant['studentId'] ??
                  participant['student_id'])
              ?.toString();
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      final name =
          (participant['clientName'] ??
                  participant['client_name'] ??
                  participant['studentName'] ??
                  participant['student_name'])
              ?.toString()
              .trim();
      result.add(
        LessonDecisionParticipant(
          id: id,
          name: name?.isNotEmpty == true
              ? name!
              : 'Ученик ${result.length + 1}',
        ),
      );
    }
    return result;
  }

  @override
  List<LessonDecisionParticipant> get settlementClients {
    if (isGroupLesson) return groupParticipants;
    final clientType = (lesson['client_type'] ?? lesson['clientType'])
        ?.toString()
        .trim()
        .toLowerCase();
    final leadId = (lesson['lead_id'] ?? lesson['leadId'])?.toString();
    final isLead =
        clientType == 'lead' ||
        (clientType == null && leadId?.isNotEmpty == true);
    if (clientType != null && clientType != 'student' && !isLead) {
      return const [];
    }
    final id = isLead
        ? (leadId ?? lesson['client_id'] ?? lesson['clientId'])?.toString()
        : (lesson['student_id'] ??
                  lesson['studentId'] ??
                  lesson['client_id'] ??
                  lesson['clientId'])
              ?.toString();
    if (id == null || id.isEmpty) return const [];
    final name =
        (isLead
                ? (lesson['lead_name'] ??
                      lesson['leadName'] ??
                      lesson['client_name'] ??
                      lesson['clientName'])
                : (lesson['student_name'] ??
                      lesson['studentName'] ??
                      lesson['client_name'] ??
                      lesson['clientName']))
            ?.toString()
            .trim();
    return [
      LessonDecisionParticipant(
        id: id,
        name: name?.isNotEmpty == true
            ? name!
            : isLead
            ? 'Лид'
            : 'Ученик',
        isStudent: !isLead,
      ),
    ];
  }

  @override
  Map<String, String> get participantNames => {
    for (final participant in settlementClients)
      participant.id: participant.name,
  };

  @override
  bool get isCompletedReschedule {
    if (operation != LessonDecisionOperation.reschedule) return false;
    final state =
        (lesson['lifecycle_state'] ??
                lesson['lifecycleState'] ??
                lesson['status'])
            ?.toString()
            .toLowerCase();
    return state == 'successfully_completed' ||
        state == 'completed' ||
        state == 'done';
  }

  Map<String, dynamic>? _previewPayload;
  MagicMutationIdentity? _commitIdentity;
  int? _expectedVersion;

  @override
  MagicApiException? recoverStaleCommit(Object error) {
    if (error is! MagicApiException || error.details is! Map) return null;
    final details = Map<String, dynamic>.from(error.details! as Map);
    final code = details['code']?.toString();
    if (code != 'STALE_LESSON_VERSION' &&
        code != 'LESSON_TRANSITION_PREVIEW_STALE') {
      return null;
    }
    if (code == 'STALE_LESSON_VERSION') {
      final rawVersion = details['currentVersion'];
      final currentVersion = rawVersion is num
          ? rawVersion.toInt()
          : int.tryParse(rawVersion?.toString() ?? '');
      if (currentVersion != null && currentVersion > 0) {
        _expectedVersion = currentVersion;
      }
    }
    _previewPayload = null;
    _commitIdentity = null;
    return MagicApiException(
      statusCode: error.statusCode,
      details: details,
      message: code == 'STALE_LESSON_VERSION'
          ? 'Версия обновлена другим сотрудником. Проверьте параметры и '
                'нажмите «Рассчитать» ещё раз.'
          : 'Условия расчёта изменились после предварительного просмотра. '
                'Проверьте параметры и нажмите «Рассчитать» ещё раз.',
    );
  }

  @override
  Future<LessonDecisionCatalog> loadCatalog() async {
    final response = await _crm.getLessonDecisionCatalog(
      branchId: _effectiveBranchId,
    );
    return LessonDecisionCatalog.fromJson(response, operation);
  }

  @override
  Future<List<LessonDecisionParticipant>> searchPayers(String query) async {
    final seen = <String>{};
    final result = <LessonDecisionParticipant>[];
    for (final row in await _crm.searchClientRefs(
      q: query,
      type: 'student',
      limit: 50,
    )) {
      final ref = row['ref'];
      final id = ref is Map ? ref['id']?.toString() : null;
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      final name = row['label']?.toString().trim() ?? '';
      result.add(
        LessonDecisionParticipant(id: id, name: name.isEmpty ? 'Ученик' : name),
      );
    }
    result.sort((left, right) => left.name.compareTo(right.name));
    return List.unmodifiable(result);
  }

  @override
  Future<List<LessonDecisionSubscription>> loadSubscriptions(
    String payerId,
  ) async {
    final result = <LessonDecisionSubscription>[];
    final financial =
        lesson['financial_decision'] ?? lesson['financialDecision'];
    final current = <String>{
      if (lesson['subscription_id'] != null)
        lesson['subscription_id'].toString(),
      if (financial is Map)
        for (final item in financial['clientDecisions'] as List? ?? const [])
          if (item is Map && item['subscriptionId'] != null)
            item['subscriptionId'].toString(),
    };
    for (final row in await _crm.listSubscriptions(
      studentId: payerId,
      limit: 50,
    )) {
      final id = row['id']?.toString();
      final remaining = num.tryParse(
        (row['lessons_remaining'] ?? row['lessonsRemaining'])?.toString() ?? '',
      );
      if (id == null ||
          id.isEmpty ||
          remaining == null ||
          (!current.contains(id) &&
              (row['status']?.toString() != 'active' || remaining <= 0))) {
        continue;
      }
      final name = (row['package_name'] ?? row['packageName'])
          ?.toString()
          .trim();
      result.add(
        LessonDecisionSubscription(
          id: id,
          label:
              '${name?.isNotEmpty == true ? name : 'Абонемент'} · остаток ${_formatUnits(remaining)}',
        ),
      );
    }
    return List.unmodifiable(result);
  }

  String? get _effectiveBranchId {
    final value =
        resources?['branchId'] ??
        successor?['branchId'] ??
        successor?['branch_id'] ??
        lesson['branch_id'] ??
        lesson['branchId'];
    final id = value?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  @override
  Future<LessonDecisionPreview> preview({
    required String reason,
    required String settlementTypeKey,
    required String compensationRuleKey,
    String? compensationValueMinor,
    int? teacherCreditedDurationMinutes,
    String? teacherCompensationSource,
    List<Map<String, dynamic>> clientDecisions = const [],
  }) async {
    final expectedVersion = _expectedVersion;
    if (expectedVersion == null || expectedVersion < 1) {
      throw StateError('Обновите расписание: версия занятия не получена.');
    }
    final payload = <String, dynamic>{
      'expectedVersion': expectedVersion,
      if (operation != LessonDecisionOperation.plannedSettlement &&
          operation != LessonDecisionOperation.correction)
        'reasonCode': 'manual',
      'reasonText': reason.trim(),
      'financialDecision': {
        'settlementTypeKey': settlementTypeKey,
        if (clientDecisions.isNotEmpty)
          'clientDecisions': lessonClientDecisionsPayload(clientDecisions),
        if (canManageTeacherCompensation) ...{
          'teacherCompensationRuleKey': compensationRuleKey,
          'teacherCompensationValueMinor': ?compensationValueMinor,
          'teacherCreditedDurationMinutes': ?teacherCreditedDurationMinutes,
          'teacherCompensationSource': ?teacherCompensationSource,
        },
      },
      if (operation == LessonDecisionOperation.reschedule)
        'successor': successor ?? const <String, dynamic>{},
      if (resources != null) 'resources': resources,
    };
    final response = await _crm.previewLessonDecision(
      lessonId: lesson['id'].toString(),
      operationKey: operation.apiKey,
      data: payload,
    );
    _previewPayload = payload;
    _commitIdentity = MagicMutationIdentity.create(
      'lesson-${operation.apiKey}-${lesson['id']}',
    );
    return LessonDecisionPreview(response);
  }

  @override
  Future<Map<String, dynamic>> commit(LessonDecisionPreview preview) async {
    final payload = _previewPayload;
    final identity = _commitIdentity;
    final token = preview.token;
    if (payload == null ||
        identity == null ||
        token == null ||
        !preview.canConfirm) {
      throw StateError('Сначала получите актуальный расчёт.');
    }
    final data = {...payload, 'previewToken': token, 'confirm': true};
    final result = await _crm.commitLessonDecision(
      lessonId: lesson['id'].toString(),
      operationKey: operation.apiKey,
      data: data,
      identity: identity,
      usePut: operation == LessonDecisionOperation.plannedSettlement,
    );
    await afterCommit?.call(result);
    return result;
  }
}

String _formatUnits(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();
