import 'dart:convert';
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

  ({LessonEditorSession session, LessonEditorDraft draft})
  applyReferenceDefaults(
    LessonEditorSession session,
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    bool useConfiguredDuration,
  ) {
    final catalog = references.catalog;
    if (catalog == null) {
      final next = session.isEdit
          ? draft
          : applyFundingDefault(draft: draft, references: references);
      return (session: session, draft: next);
    }
    final settlement =
        _catalogItemByKey(catalog.settlementTypes, draft.settlementTypeKey) ??
        catalog.settlementTypes.firstOrNull;
    final legacyMode = session.snapshot?.rawLesson['teacher_compensation_type']
        ?.toString();
    final rule =
        _catalogItemByKey(
          catalog.compensationRules,
          draft.compensationRuleKey,
        ) ??
        catalog.compensationRules
            .where((item) => legacyMode != 'none' && item.mode == legacyMode)
            .firstOrNull ??
        catalog.compensationRules
            .where((item) => item.mode == 'standard')
            .firstOrNull ??
        catalog.compensationRules.firstOrNull;
    final configuredDuration = catalog.defaultDurationMinutes;
    final compensationValue = requiresCompensationValue(rule)
        ? draft.compensationValueMinor ??
              _legacyCompensationValue(session, rule) ??
              rule?.value
        : null;
    var next = draft.copyWith(
      durationMinutes:
          !session.isEdit &&
              useConfiguredDuration &&
              configuredDuration != null &&
              configuredDuration > 0
          ? configuredDuration
          : draft.durationMinutes,
      settlementTypeKey: settlement?.key,
      compensationRuleKey: rule?.key,
      compensationValueMinor: compensationValue,
    );
    if (next.clientDecisions.isEmpty &&
        (!session.isEdit || next.clientChargeType == 'none')) {
      next = applyFundingDefault(draft: next, references: references);
    }
    if (next.client?.type != 'group' &&
        next.client != null &&
        next.clientDecisions.isEmpty) {
      final oldPrice = num.tryParse(
        session.snapshot?.rawLesson['client_charge_value']?.toString() ?? '',
      );
      next = next.copyWith(
        clientDecisions: [
          {
            'clientId': next.client!.id,
            if (next.client!.type == 'student')
              'payerStudentId': next.client!.id,
            'chargeType': next.clientChargeType,
            if (next.subscriptionId != null)
              'subscriptionId': next.subscriptionId,
            if (next.clientChargeType == 'personal_account' && oldPrice != null)
              'basePriceMinor': (oldPrice * 100).round().toString(),
          },
        ],
      );
    }
    if (next.client?.type != 'group' && next.clientDecisions.isNotEmpty) {
      final funding = next.clientDecisions.first;
      next = next.copyWith(
        clientChargeType:
            funding['chargeType']?.toString() ??
            (funding['subscriptionId'] != null
                ? 'subscription'
                : next.clientChargeType),
        subscriptionId: funding['subscriptionId']?.toString(),
      );
    }
    return (
      session: _normalizeCompensationBaseline(
        session: session,
        draft: next,
        rule: rule,
      ),
      draft: next,
    );
  }

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

  ({LessonEditorDraft draft, bool scheduleChanged, String? branchToLoad})
  applyEdit(
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    LessonEditorEdit edit,
  ) => switch (edit) {
    LessonClientDecisionsEdit(:final value) => (
      draft: draft.copyWith(
        clientDecisions: value,
        clientChargeType:
            value.firstOrNull?['chargeType']?.toString() ??
            draft.clientChargeType,
        subscriptionId: value.firstOrNull?['subscriptionId']?.toString(),
      ),
      scheduleChanged: false,
      branchToLoad: null,
    ),
    LessonReferenceEdit(:final target, :final value) => _applyReferenceEdit(
      draft,
      references,
      target,
      value,
    ),
    LessonTextEdit(:final target, :final value) => _applyTextEdit(
      draft,
      references,
      target,
      value,
    ),
    LessonDurationEdit(:final value) => (
      draft: draft.copyWith(durationMinutes: value),
      scheduleChanged: true,
      branchToLoad: null,
    ),
    LessonNotesEdit(:final value) => (
      draft: draft.copyWith(notes: value),
      scheduleChanged: false,
      branchToLoad: null,
    ),
    LessonTrialEdit(:final value) => (
      draft: draft.copyWith(isTrial: value),
      scheduleChanged: false,
      branchToLoad: null,
    ),
  };

  ({LessonEditorDraft draft, bool scheduleChanged, String? branchToLoad})
  _applyReferenceEdit(
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    LessonReferenceTarget target,
    String? value,
  ) => switch (target) {
    LessonReferenceTarget.branch => (
      draft: value == null ? draft : branchSelection(draft, references, value),
      scheduleChanged: true,
      branchToLoad: value,
    ),
    LessonReferenceTarget.room => (
      draft: draft.copyWith(roomId: value),
      scheduleChanged: true,
      branchToLoad: null,
    ),
    LessonReferenceTarget.teacher => (
      draft: draft.copyWith(teacherId: value),
      scheduleChanged: true,
      branchToLoad: null,
    ),
    LessonReferenceTarget.settlement => (
      draft: draft.copyWith(settlementTypeKey: value),
      scheduleChanged: false,
      branchToLoad: null,
    ),
    LessonReferenceTarget.compensationRule => (
      draft: compensationRuleSelection(draft, references, value),
      scheduleChanged: false,
      branchToLoad: null,
    ),
    LessonReferenceTarget.subscription => (
      draft: draft.copyWith(subscriptionId: value),
      scheduleChanged: false,
      branchToLoad: null,
    ),
  };

  ({LessonEditorDraft draft, bool scheduleChanged, String? branchToLoad})
  _applyTextEdit(
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    LessonTextTarget target,
    String value,
  ) => (
    draft: switch (target) {
      LessonTextTarget.completion => draft.copyWith(completionType: value),
      LessonTextTarget.compensationValue => compensationValueChange(
        draft,
        references,
        value,
      ),
      LessonTextTarget.settlementReason => draft.copyWith(
        plannedSettlementReason: value,
      ),
      LessonTextTarget.funding => fundingSelection(draft, references, value),
    },
    scheduleChanged: false,
    branchToLoad: null,
  );

  LessonEditorDraft branchSelection(
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    String branchId,
  ) {
    final keepsTeacher = references.teachers.any(
      (item) =>
          item.id == draft.teacherId &&
          item.status == 'active' &&
          item.assignedBranchIds.contains(branchId),
    );
    return draft.copyWith(
      branchId: branchId,
      teacherId: keepsTeacher ? draft.teacherId : null,
      roomId: null,
      settlementTypeKey: null,
      compensationRuleKey: null,
      compensationValueMinor: null,
    );
  }

  LessonEditorDraft compensationRuleSelection(
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    String? ruleKey,
  ) {
    final rule = _catalogItemByKey(
      references.catalog?.compensationRules,
      ruleKey,
    );
    return draft.copyWith(
      compensationRuleKey: ruleKey,
      compensationValueMinor: requiresCompensationValue(rule)
          ? rule?.value
          : null,
    );
  }

  LessonEditorDraft compensationValueChange(
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    String rawValue,
  ) {
    final rule = _catalogItemByKey(
      references.catalog?.compensationRules,
      draft.compensationRuleKey,
    );
    return draft.copyWith(
      compensationValueMinor: parseCompensationValueMinor(
        mode: rule?.mode,
        rawValue: rawValue,
      ),
    );
  }

  LessonEditorValidation validate({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    final message =
        _requiredFieldsMessage(session: session, draft: draft) ??
        _editMessage(session: session, draft: draft) ??
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
        );
    return message == null
        ? const LessonEditorValidation.valid()
        : LessonEditorValidation.invalid(message);
  }

  LessonEditorDraft applyFundingDefault({
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) {
    if (draft.clientDecisions.isNotEmpty) return draft;
    final settlement = _catalogItemByKey(
      references.catalog?.settlementTypes,
      draft.settlementTypeKey,
    );
    if (isNoCharge(settlement)) {
      return draft.copyWith(clientChargeType: 'none', subscriptionId: null);
    }
    if (draft.client?.type == 'student') {
      final selected = _referenceById(
        references.subscriptions,
        draft.subscriptionId,
      );
      return draft.copyWith(
        clientChargeType: 'subscription',
        subscriptionId: (selected ?? references.subscriptions.firstOrNull)?.id,
      );
    }
    return draft.copyWith(
      clientChargeType: 'personal_account',
      subscriptionId: null,
    );
  }

  LessonEditorDraft fundingSelection(
    LessonEditorDraft draft,
    LessonEditorReferenceState references,
    String value,
  ) => draft.copyWith(
    clientChargeType: value,
    subscriptionId: value == 'subscription'
        ? _referenceById(references.subscriptions, draft.subscriptionId)?.id ??
              references.subscriptions.firstOrNull?.id
        : null,
  );

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
    required bool canManageTeacherCompensation,
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
      if (draft.clientDecisions.isNotEmpty)
        'clientDecisions': lessonClientDecisionsPayload(draft.clientDecisions),
      if (canManageTeacherCompensation) ...{
        'teacherCompensationRuleKey': draft.compensationRuleKey,
        'teacherCompensationValueMinor': ?draft.compensationValueMinor,
      },
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
      if (canManageTeacherCompensation) ...{
        'teacherCompensationType': teacherRate.$1,
        'teacherCompensationValue': teacherRate.$2,
      },
      'financialDecision': financialDecision,
      if (canManageTeacherCompensation &&
          compensationNeedsReason(draft: draft, rule: rule))
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
    return draft.settlementTypeKey !=
            (snapshot.initialSettlementTypeKey ??
                session.draft.settlementTypeKey) ||
        draft.compensationRuleKey != snapshot.initialCompensationRuleKey ||
        draft.compensationValueMinor !=
            snapshot.initialCompensationValueMinor ||
        jsonEncode(draft.clientDecisions) !=
            jsonEncode(session.draft.clientDecisions);
  }

  bool hasNotesChanges({
    required LessonEditorSession session,
    required LessonEditorDraft draft,
  }) =>
      session.snapshot != null &&
      (session.snapshot!.rawLesson['notes']?.toString().trim() ?? '') !=
          draft.notes.trim();

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
    final schedule = schedulePayload(draft);
    final timeChanged = hasLessonScheduleChanges(
      lesson: {
        ...schedule,
        'scheduledAt': snapshot.initialSchedulePayload['scheduledAt'],
        'durationMinutes': snapshot.initialSchedulePayload['durationMinutes'],
      },
      successor: schedule,
    );
    return LessonDecisionRequest(
      operation: timeChanged
          ? LessonDecisionOperation.reschedule
          : _financialEditOperation(snapshot.rawLesson),
      lesson: snapshot.rawLesson,
      successor: timeChanged ? schedule : null,
      resources: scheduleChanged && !timeChanged
          ? {
              'teacherId': draft.teacherId,
              'branchId': draft.branchId,
              'roomId': draft.roomId,
            }
          : null,
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
    for (final decision in draft.clientDecisions) {
      final source = decision['chargeType'];
      if (source == 'none' &&
          !isNoCharge(
            _catalogItemByKey(
              references.catalog?.settlementTypes,
              draft.settlementTypeKey,
            ),
          )) {
        return 'Для платного списания выберите абонемент или личный счёт';
      }
      if (source == 'subscription' &&
          (decision['subscriptionId']?.toString().isEmpty ?? true)) {
        return 'Выберите абонемент плательщика';
      }
      if (source == 'personal_account') {
        if (draft.client?.type == 'lead' &&
            (decision['payerStudentId'] == null ||
                decision['payerStudentId'] == draft.client?.id)) {
          return 'Выберите ученика-плательщика для списания с личного счёта';
        }
        final price = int.tryParse(
          decision['basePriceMinor']?.toString() ?? '',
        );
        if (price == null || price < 0 || price > 999999999999) {
          return 'Введите корректную стоимость занятия';
        }
        for (final key in ['discount', 'surcharge']) {
          final adjustment = decision[key];
          if (adjustment is! Map || adjustment['type'] == 'none') continue;
          if (adjustment['reason']?.toString().trim().isNotEmpty != true) {
            return 'Укажите причину скидки или надбавки';
          }
          final field = adjustment['type'] == 'percent'
              ? 'percentBasisPoints'
              : key == 'discount'
              ? 'fixedMinor'
              : 'amountMinor';
          final amount = int.tryParse(adjustment[field]?.toString() ?? '');
          if (amount == null ||
              amount <= 0 ||
              (field == 'percentBasisPoints' && amount > 10000)) {
            return 'Введите корректную скидку или надбавку';
          }
        }
      }
    }
    if (draft.clientDecisions.isNotEmpty) return null;
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
        hasFinancialChanges(session: session, draft: draft) ||
        hasNotesChanges(session: session, draft: draft);
    return changed ||
            _financialEditOperation(session.snapshot!.rawLesson) ==
                LessonDecisionOperation.settle
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
    final priceMinor = num.tryParse(
      draft.clientDecisions.firstOrNull?['basePriceMinor']?.toString() ?? '',
    );
    if (priceMinor != null) return priceMinor / 100;
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

LessonEditorSession _normalizeCompensationBaseline({
  required LessonEditorSession session,
  required LessonEditorDraft draft,
  required LessonDecisionCatalogItem? rule,
}) {
  final snapshot = session.snapshot;
  if (snapshot == null ||
      rule == null ||
      snapshot.compensationBaselineCaptured) {
    return session;
  }
  return LessonEditorSession(
    draft: draft,
    snapshot: LessonEditorSnapshot(
      lessonId: snapshot.lessonId,
      expectedVersion: snapshot.expectedVersion,
      rawLesson: snapshot.rawLesson,
      clientLocked: snapshot.clientLocked,
      initialSchedulePayload: snapshot.initialSchedulePayload,
      initialCompensationRuleKey: draft.compensationRuleKey,
      initialCompensationValueMinor: draft.compensationValueMinor,
      compensationBaselineCaptured: true,
      initialSettlementTypeKey: draft.settlementTypeKey,
    ),
    seededClient: session.seededClient,
    leadNoteSource: session.leadNoteSource,
  );
}

String? _legacyCompensationValue(
  LessonEditorSession session,
  LessonDecisionCatalogItem? rule,
) {
  if (!session.isEdit || (rule?.mode != 'fixed' && rule?.mode != 'hourly')) {
    return null;
  }
  final value = session.snapshot?.rawLesson['teacher_compensation_value'];
  return value is num && value >= 0 ? (value * 100).round().toString() : null;
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
  if (state == 'settlement_pending') return LessonDecisionOperation.settle;
  return state == 'successfully_completed' ||
          state == 'completed' ||
          state == 'done'
      ? LessonDecisionOperation.correction
      : LessonDecisionOperation.plannedSettlement;
}
