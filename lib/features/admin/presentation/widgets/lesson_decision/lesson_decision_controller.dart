import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'lesson_decision_models.dart';

class LessonDecisionController implements LessonDecisionFormLifecycle {
  LessonDecisionController({
    required MagicCrmService crm,
    required this.operation,
    required this.lesson,
    this.successor,
    this.initialSettlementTypeKey,
    this.initialCompensationRuleKey,
    this.initialCompensationValueMinor,
  }) : _crm = crm,
       _expectedVersion = (lesson['version'] as num?)?.toInt();

  final MagicCrmService _crm;
  @override
  final LessonDecisionOperation operation;
  @override
  final Map<String, dynamic> lesson;
  @override
  final Map<String, dynamic>? successor;
  @override
  final String? initialSettlementTypeKey;
  @override
  final String? initialCompensationRuleKey;
  @override
  final String? initialCompensationValueMinor;

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
  Map<String, String> get participantNames => {
    for (final participant in groupParticipants)
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
    final effectiveBranchId =
        successor?['branchId'] ??
        successor?['branch_id'] ??
        lesson['branch_id'] ??
        lesson['branchId'];
    final response = await _crm.getLessonDecisionCatalog(
      branchId: effectiveBranchId?.toString(),
    );
    return LessonDecisionCatalog.fromJson(response, operation);
  }

  @override
  Future<LessonDecisionPreview> preview({
    required String reason,
    required String settlementTypeKey,
    required String compensationRuleKey,
    String? compensationValueMinor,
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
          'clientDecisions': [
            for (final decision in clientDecisions)
              Map<String, dynamic>.from(decision),
          ],
        'teacherCompensationRuleKey': compensationRuleKey,
        'teacherCompensationValueMinor': ?compensationValueMinor,
      },
      if (operation == LessonDecisionOperation.reschedule)
        'successor': successor ?? const <String, dynamic>{},
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
  Future<Map<String, dynamic>> commit(LessonDecisionPreview preview) {
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
    return _crm.commitLessonDecision(
      lessonId: lesson['id'].toString(),
      operationKey: operation.apiKey,
      data: data,
      identity: identity,
      usePut: operation == LessonDecisionOperation.plannedSettlement,
    );
  }
}
