import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'lesson_editor_models.dart';

String lessonEditorTitle(LessonEditorSession session, bool hasLeadPreset) =>
    session.isEdit
    ? 'Изменить занятие'
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

Widget lessonTimePicker24HourBuilder(BuildContext context, Widget? child) =>
    MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    );

void showLessonEditorError(
  BuildContext context,
  Object error,
  String fallback,
) => ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text(lessonEditorErrorMessage(error, fallback))),
);

void scrollToLessonPreview(BuildContext context, ScrollController scroll) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted && scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });
}

abstract interface class LessonEditorActions {
  Future<List<LessonClientRef>> searchClients(String query);

  void selectClient(LessonClientRef? value);

  void edit(LessonEditorEdit edit);

  Future<void> selectDate(LessonDatePickerRequest request);

  Future<void> selectTime(LessonTimePickerRequest request);

  Future<void> analyzeSchedule();

  Future<void> applySuggestion(ScheduleSuggestion value);

  Future<void> save();

  void cancel();

  void openConstraint(LessonConstraintViolation value);
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
    required this.canManageTeacherCompensation,
  });

  final LessonEditorSession session;
  final LessonEditorDraft draft;
  final String? validationMessage;
  final String settlementLabel;
  final String clientSnapshotValue;
  final String compensationLabel;
  final String teacherSnapshotValue;
  final bool canManageTeacherCompensation;
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
            'Параметры и расчёты изменятся после подтверждения.',
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
    this.confirming = false,
    this.canSave = true,
    super.key,
  });

  final bool isEdit;
  final bool confirming;
  final bool isSaving;
  final bool canSave;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: actions.cancel, child: const Text('Отмена')),
        const SizedBox(width: AppSpace.sm),
        FilledButton(
          onPressed: isSaving || !canSave ? null : actions.save,
          child: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  confirming
                      ? 'Подтвердить изменения'
                      : isEdit
                      ? 'Рассчитать'
                      : 'Создать',
                ),
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
            'Итоговые суммы проверяются сервером при сохранении.',
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
          if (model.canManageTeacherCompensation)
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
