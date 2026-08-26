import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'lesson_editor_decision_policy.dart';
import 'lesson_editor_models.dart';

String lessonEditorTitle(LessonEditorSession session, bool hasLeadPreset) =>
    session.isEdit
    ? 'Перенести или изменить занятие'
    : hasLeadPreset
    ? 'Пробное занятие'
    : 'Новое занятие';

String? lessonLoadErrorMessage(Object? error) => error == null
    ? null
    : userErrorMessage(error, fallback: 'Не удалось загрузить данные занятия.');

String? lessonScheduleErrorMessage(Object? error) => error == null
    ? null
    : error is StateError
    ? 'Выберите клиента, филиал, преподавателя и аудиторию.'
    : userErrorMessage(error, fallback: 'Не удалось проверить расписание.');

String lessonEditorErrorMessage(Object error, String fallback) =>
    userErrorMessage(error, fallback: fallback);

abstract interface class LessonEditorActions {
  Future<List<LessonClientRef>> searchClients(String query);

  void selectClient(LessonClientRef? value);

  void selectBranch(String? value);

  void selectRoom(String? value);

  void selectTeacher(String? value);

  void selectDate(DateTime value);

  void selectTime(TimeOfDay value);

  void selectDuration(int value);

  void selectTrial(bool value);

  void selectCompletion(String value);

  void selectSettlement(String? value);

  void selectCompensationRule(String? value);

  void changeCompensationValue(String value);

  void changePlannedSettlementReason(String value);

  void selectFunding(String value);

  void selectSubscription(String? value);

  Future<void> analyzeSchedule();

  Future<void> applySuggestion(ScheduleSuggestion value);

  Future<void> save();

  void cancel();

  void openConstraint(LessonConstraintViolation value);
}

mixin LessonEditorDraftActions implements LessonEditorActions {
  LessonEditorDraft get actionDraft;
  LessonEditorReferenceState get actionReferences;
  LessonEditorDecisionPolicy get actionPolicy;

  void updateActionDraft(
    LessonEditorDraft value, {
    bool scheduleChanged = false,
  });

  void loadActionBranch(String branchId);
  LessonEditorDraft applyActionSuggestion(ScheduleSuggestion value);
  void focusActionConstraint(String lessonId);

  @override
  void selectBranch(String? value) {
    if (value == null) return;
    updateActionDraft(
      actionPolicy.branchSelection(actionDraft, actionReferences, value),
      scheduleChanged: true,
    );
    loadActionBranch(value);
  }

  @override
  void selectRoom(String? value) => updateActionDraft(
    actionDraft.copyWith(roomId: value),
    scheduleChanged: true,
  );

  @override
  void selectTeacher(String? value) => updateActionDraft(
    actionDraft.copyWith(teacherId: value),
    scheduleChanged: true,
  );

  @override
  void selectDate(DateTime value) =>
      updateActionDraft(actionDraft.withDate(value), scheduleChanged: true);

  @override
  void selectTime(TimeOfDay value) => updateActionDraft(
    actionDraft.withTime(value.hour, value.minute),
    scheduleChanged: true,
  );

  @override
  void selectDuration(int value) => updateActionDraft(
    actionDraft.copyWith(durationMinutes: value),
    scheduleChanged: true,
  );

  @override
  void selectTrial(bool value) =>
      updateActionDraft(actionDraft.copyWith(isTrial: value));

  @override
  void selectCompletion(String value) =>
      updateActionDraft(actionDraft.copyWith(completionType: value));

  @override
  void selectSettlement(String? value) => updateActionDraft(
    actionPolicy.applyFundingDefault(
      draft: actionDraft.copyWith(settlementTypeKey: value),
      references: actionReferences,
    ),
  );

  @override
  void selectCompensationRule(String? value) => updateActionDraft(
    actionPolicy.compensationRuleSelection(
      actionDraft,
      actionReferences,
      value,
    ),
  );

  @override
  void changeCompensationValue(String value) => updateActionDraft(
    actionPolicy.compensationValueChange(actionDraft, actionReferences, value),
  );

  @override
  void changePlannedSettlementReason(String value) =>
      updateActionDraft(actionDraft.copyWith(plannedSettlementReason: value));

  @override
  void selectFunding(String value) => updateActionDraft(
    actionDraft.copyWith(
      clientChargeType: value,
      subscriptionId: value == 'subscription'
          ? actionDraft.subscriptionId
          : null,
    ),
  );

  @override
  void selectSubscription(String? value) =>
      updateActionDraft(actionDraft.copyWith(subscriptionId: value));

  @override
  Future<void> applySuggestion(ScheduleSuggestion value) async {
    updateActionDraft(applyActionSuggestion(value), scheduleChanged: true);
    await analyzeSchedule();
  }

  @override
  void openConstraint(LessonConstraintViolation value) {
    final lessonId = value.conflictingLessonIds.firstOrNull;
    if (lessonId != null) focusActionConstraint(lessonId);
  }
}

class LessonConstraintDialog extends StatelessWidget {
  const LessonConstraintDialog({
    required this.violations,
    required this.onOpen,
    required this.onFix,
    super.key,
  });

  final List<LessonConstraintViolation> violations;
  final ValueChanged<String> onOpen;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final seenLessonIds = <String>{};
    return AlertDialog(
      title: const Text('Занятие не сохранено'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Исправьте все ограничения расписания перед сохранением:',
            ),
            for (final (violationIndex, violation) in violations.indexed) ...[
              const SizedBox(height: 12),
              Text(violation.title),
              Text(violation.resourceLabel),
              for (final (linkIndex, lessonId)
                  in violation.conflictingLessonIds.indexed)
                TextButton(
                  key: ValueKey(
                    seenLessonIds.add(lessonId)
                        ? 'conflict-lesson-$lessonId'
                        : 'conflict-lesson-$lessonId-$violationIndex-$linkIndex',
                  ),
                  onPressed: () => onOpen(lessonId),
                  child: Text('Открыть занятие ${linkIndex + 1}'),
                ),
            ],
          ],
        ),
      ),
      actions: [FilledButton(onPressed: onFix, child: const Text('Исправить'))],
    );
  }
}

class LessonEditorFeedbackModel {
  const LessonEditorFeedbackModel({
    required this.session,
    required this.draft,
    required this.validationMessage,
    required this.settlementLabel,
    required this.clientSnapshotValue,
    required this.compensationLabel,
    required this.teacherSnapshotValue,
  });

  final LessonEditorSession session;
  final LessonEditorDraft draft;
  final String? validationMessage;
  final String settlementLabel;
  final String clientSnapshotValue;
  final String compensationLabel;
  final String teacherSnapshotValue;
}

class LessonEditorFeedback extends StatelessWidget {
  const LessonEditorFeedback({required this.model, super.key});

  final LessonEditorFeedbackModel model;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!model.session.isEdit) ...[
          const SizedBox(height: 16),
          _SnapshotPreview(model: model),
        ],
        if (model.session.isEdit) ...[
          const SizedBox(height: 10),
          Text(
            'Клиент и списание уже зафиксированы. Остальные данные '
            'можно изменить после подтверждения.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (model.validationMessage case final message?) ...[
          const SizedBox(height: AppSpace.md),
          Container(
            key: const ValueKey('lesson-form-validation-error'),
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColor.dangerSoft,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: AppColor.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

class LessonEditorActionsRow extends StatelessWidget {
  const LessonEditorActionsRow({
    required this.isEdit,
    required this.isSaving,
    required this.actions,
    super.key,
  });

  final bool isEdit;
  final bool isSaving;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: actions.cancel, child: const Text('Отмена')),
        const SizedBox(width: AppSpace.sm),
        FilledButton(
          onPressed: isSaving ? null : actions.save,
          child: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Перейти к расчёту' : 'Создать'),
        ),
      ],
    );
  }
}

class _SnapshotPreview extends StatelessWidget {
  const _SnapshotPreview({required this.model});

  final LessonEditorFeedbackModel model;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('lesson-snapshot-preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.gold.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Расчёты перед созданием',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Проверьте расчёты. При переносе они не изменятся.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.md),
          _SnapshotRow(
            key: const ValueKey('lesson-snapshot-trial'),
            label: 'Тип занятия',
            value: model.draft.isTrial ? 'Пробное' : 'Обычное',
          ),
          _SnapshotRow(
            key: const ValueKey('lesson-snapshot-client-charge'),
            label: 'Списание клиента',
            value: '${model.settlementLabel} · ${model.clientSnapshotValue}',
          ),
          _SnapshotRow(
            key: const ValueKey('lesson-snapshot-teacher-compensation'),
            label: 'Оплата преподавателю',
            value:
                '${model.compensationLabel} · '
                '${model.teacherSnapshotValue}',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    required super.key,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
