import '../lesson_decision/lesson_decision_models.dart';
import '../lesson_form_rules.dart';
import 'lesson_editor_models.dart';

class LessonEditorValidation {
  const LessonEditorValidation.valid() : message = null;

  const LessonEditorValidation.invalid(this.message);

  final String? message;

  bool get isValid => message == null;
}

class LessonEditorDecisionPolicy {
  const LessonEditorDecisionPolicy();

  bool isNoCharge(LessonDecisionCatalogItem? settlement) =>
      settlement?.hourShareBasisPoints == 0 &&
      settlement?.fixedPenaltyMinor == '0';

  bool hasRequiredParticipant({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) => session.isGroupEdit || draft.client != null;

  bool hasRequiredSchedule(LessonEditorDraft draft) =>
      draft.teacherId != null && draft.branchId != null && draft.roomId != null;

  bool requiresSubscription(LessonEditorDraft draft) =>
      draft.clientChargeType == 'subscription';

  bool requiresCompensationValue(LessonDecisionCatalogItem? rule) =>
      switch (rule?.mode) {
        'percent' || 'fixed' || 'hourly' => true,
        _ => false,
      };

  LessonEditorValidation validate({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    final message =
        _requiredFieldsMessage(session: session, draft: draft) ??
        _createFundingMessage(
          session: session,
          draft: draft,
          references: references,
        ) ??
        _createDecisionMessage(session: session, draft: draft) ??
        _compensationMessage(
          session: session,
          draft: draft,
          references: references,
        ) ??
        _editMessage(session: session, draft: draft);
    return message == null
        ? const LessonEditorValidation.valid()
        : LessonEditorValidation.invalid(message);
  }

  LessonEditorDraft applyFundingDefault({
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    final settlement = _catalogItemByKey(
      references.catalog?.settlementTypes,
      draft.settlementTypeKey,
    );
    if (isNoCharge(settlement)) {
      return draft.copyWith(clientChargeType: 'none', subscriptionId: null);
    }
    if (draft.client?.type == 'student' &&
        references.subscriptions.isNotEmpty) {
      final selected = _referenceById(
        references.subscriptions,
        draft.subscriptionId,
      );
      return draft.copyWith(
        clientChargeType: 'subscription',
        subscriptionId: (selected ?? references.subscriptions.first).id,
      );
    }
    return draft.copyWith(
      clientChargeType: 'personal_account',
      subscriptionId: null,
    );
  }

  Map<String, dynamic> schedulePayload(LessonEditorDraft draft) {
    final local = draft.localStart;
    final scheduledAt = DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour - 3,
      local.minute,
    );
    return {
      'teacherId': draft.teacherId,
      'branchId': draft.branchId,
      'roomId': draft.roomId,
      'scheduledAt': scheduledAt.toIso8601String(),
      'durationMinutes': draft.durationMinutes,
    };
  }

  Map<String, dynamic> createPayload({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    final client = draft.client;
    final rule = _catalogItemByKey(
      references.catalog?.compensationRules,
      draft.compensationRuleKey,
    );
    final teacherRate = _compatibilityTeacherRate(
      draft: draft,
      references: references,
    );
    final financialDecision = <String, dynamic>{
      'settlementTypeKey': draft.settlementTypeKey,
      'teacherCompensationRuleKey': draft.compensationRuleKey,
      'teacherCompensationValueMinor': ?draft.compensationValueMinor,
    };
    return {
      ...schedulePayload(draft),
      'clientRef': {'type': client?.type, 'id': client?.id},
      'isTrial': draft.isTrial,
      'completionType': draft.completionType,
      'clientChargeType': draft.clientChargeType,
      'clientChargeValue': _compatibilityClientChargeValue(
        draft: draft,
        references: references,
      ),
      'teacherCompensationType': teacherRate.$1,
      'teacherCompensationValue': teacherRate.$2,
      'financialDecision': financialDecision,
      if (compensationNeedsReason(draft: draft, rule: rule))
        'plannedSettlementReason': draft.plannedSettlementReason.trim(),
      if (requiresSubscription(draft)) 'subscriptionId': draft.subscriptionId,
      'notes': ?_leadNote(session: session, client: client),
    };
  }

  bool hasScheduleChanges({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) {
    final snapshot = session.snapshot;
    if (snapshot == null) return true;
    return hasLessonScheduleChanges(
      lesson: snapshot.initialSchedulePayload,
      successor: schedulePayload(draft),
    );
  }

  bool hasFinancialChanges({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) {
    final snapshot = session.snapshot;
    if (snapshot == null) return true;
    return draft.compensationRuleKey != snapshot.initialCompensationRuleKey ||
        draft.compensationValueMinor != snapshot.initialCompensationValueMinor;
  }

  bool compensationNeedsReason({
    required LessonEditorDraft draft,
    required LessonDecisionCatalogItem? rule,
  }) =>
      rule != null &&
      draft.compensationValueMinor != null &&
      draft.compensationValueMinor != rule.value;

  LessonDecisionRequest editRequest({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) {
    final snapshot = session.snapshot;
    if (snapshot == null) {
      throw StateError('Lesson edit request requires a snapshot');
    }
    final scheduleChanged = hasScheduleChanges(session: session, draft: draft);
    return LessonDecisionRequest(
      operation: scheduleChanged
          ? LessonDecisionOperation.reschedule
          : _financialEditOperation(snapshot.rawLesson),
      lesson: snapshot.rawLesson,
      successor: scheduleChanged ? schedulePayload(draft) : null,
      initialSettlementTypeKey: draft.settlementTypeKey,
      initialCompensationRuleKey: draft.compensationRuleKey,
      initialCompensationValueMinor: draft.compensationValueMinor,
    );
  }

  String clientChargeSnapshotLabel({
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) => formatClientChargeSnapshotLabel(
    clientChargeType: draft.clientChargeType,
    compatibilityValue: _compatibilityClientChargeValue(
      draft: draft,
      references: references,
    ),
  );

  String teacherCompensationSnapshotLabel({
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    final rule = _catalogItemByKey(
      references.catalog?.compensationRules,
      draft.compensationRuleKey,
    );
    final rate = _compatibilityTeacherRate(
      draft: draft,
      references: references,
    );
    return formatTeacherCompensationSnapshotLabel(
      mode: rule?.mode,
      compensationInput: formatCompensationMinorInput(
        draft.compensationValueMinor ?? rule?.value,
      ),
      compatibilityRateType: rate.$1,
      compatibilityRate: rate.$2,
    );
  }

  String? _requiredFieldsMessage({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) {
    if (!hasRequiredParticipant(session: session, draft: draft)) {
      return 'Заполните обязательные поля корректно';
    }
    if (!hasRequiredSchedule(draft)) {
      return 'Заполните обязательные поля корректно';
    }
    return null;
  }

  String? _createFundingMessage({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    if (session.isEdit) return null;
    if (requiresSubscription(draft) && draft.subscriptionId == null) {
      return 'Заполните обязательные поля корректно';
    }
    final settlement = _catalogItemByKey(
      references.catalog?.settlementTypes,
      draft.settlementTypeKey,
    );
    if (draft.clientChargeType == 'none' && !isNoCharge(settlement)) {
      return 'Для платного списания выберите абонемент или личный счёт';
    }
    return null;
  }

  String? _createDecisionMessage({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) {
    if (session.isEdit) return null;
    if (draft.settlementTypeKey == null || draft.compensationRuleKey == null) {
      return 'Заполните обязательные поля корректно';
    }
    return null;
  }

  String? _compensationMessage({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    final rule = _catalogItemByKey(
      references.catalog?.compensationRules,
      draft.compensationRuleKey,
    );
    if (requiresCompensationValue(rule) &&
        draft.compensationValueMinor == null) {
      return 'Введите корректный процент или сумму оплаты преподавателю';
    }
    final reasonMissing = draft.plannedSettlementReason.trim().isEmpty;
    if (!session.isEdit &&
        reasonMissing &&
        compensationNeedsReason(draft: draft, rule: rule)) {
      return 'Укажите причину индивидуального значения оплаты преподавателю';
    }
    return null;
  }

  String? _editMessage({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) {
    if (!session.isEdit) return null;
    if (session.snapshot?.expectedVersion == null) {
      return 'Обновите расписание: версия занятия не получена';
    }
    final changed =
        hasScheduleChanges(session: session, draft: draft) ||
        hasFinancialChanges(session: session, draft: draft);
    return changed
        ? null
        : 'Измените параметры расписания или оплату преподавателю';
  }

  num _compatibilityClientChargeValue({
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    final durationHours = draft.durationMinutes / 60;
    if (draft.clientChargeType == 'subscription') return durationHours;
    if (draft.clientChargeType != 'personal_account') return 0;
    final selected = _referenceById(
      references.subscriptions,
      draft.subscriptionId,
    );
    final source =
        selected ??
        (references.subscriptions.isEmpty
            ? null
            : references.subscriptions.first);
    final price = source?.raw['package_price'];
    final units = source?.raw['lessons_total'];
    if (price is! num || units is! num || units <= 0) return 0;
    return price / units * durationHours;
  }

  (String, num) _compatibilityTeacherRate({
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    final teacher = _referenceById(references.teachers, draft.teacherId);
    final rate = teacher?.raw['current_rate'];
    return rate is num && rate > 0 ? ('hourly', rate) : ('none', 0);
  }
}

String? _leadNote({
  required LessonEditorSession session,
  required LessonClientRef? client,
}) {
  if (client?.type != 'lead') return null;
  final source = session.leadNoteSource?.trim();
  if (source == null || source.isEmpty) return null;
  return 'Занятие по лиду: $source';
}

LessonDecisionCatalogItem? _catalogItemByKey(
  List<LessonDecisionCatalogItem>? items,
  String? key,
) {
  if (key == null) return null;
  for (final item in items ?? const <LessonDecisionCatalogItem>[]) {
    if (item.key == key) return item;
  }
  return null;
}

LessonEditorReferenceItem? _referenceById(
  List<LessonEditorReferenceItem> items,
  String? id,
) {
  if (id == null) return null;
  for (final item in items) {
    if (item.id == id) return item;
  }
  return null;
}

LessonDecisionOperation _financialEditOperation(Map<String, dynamic> lesson) {
  final state =
      (lesson['lifecycle_state'] ??
              lesson['lifecycleState'] ??
              lesson['status'])
          ?.toString()
          .toLowerCase();
  return state == 'successfully_completed' ||
          state == 'completed' ||
          state == 'done'
      ? LessonDecisionOperation.correction
      : LessonDecisionOperation.plannedSettlement;
}
