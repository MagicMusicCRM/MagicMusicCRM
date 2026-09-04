import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';

import '../lesson_decision_flow.dart';
import 'lesson_editor_decision_policy.dart';
import 'lesson_editor_models.dart';
import 'lesson_editor_save_flow.dart';
import 'lesson_editor_view.dart';

Future<DateTime?> pickLessonEditorDate(
  BuildContext context,
  LessonDatePickerRequest request,
) => showMagicDatePicker(
  context: context,
  initialDate: request.initialDate,
  firstDate: request.firstDate,
  lastDate: request.lastDate,
);

Future<TimeOfDay?> pickLessonEditorTime(
  BuildContext context,
  LessonTimePickerRequest request,
) => showMagicTimePicker(
  context: context,
  initialTime: TimeOfDay(hour: request.hour, minute: request.minute),
  builder: lessonTimePicker24HourBuilder,
);

Future<void> presentLessonEditorSaveOutcome(
  BuildContext context,
  LessonSaveOutcome outcome, {
  required ScrollController scrollController,
  required ValueChanged<LessonEditorValidation> onInvalid,
  required ValueChanged<LessonScheduleAnalysis> onViolations,
  required ValueChanged<LessonEditorSession> onSessionReloaded,
  required ValueChanged<String> onOpenConstraint,
}) async {
  switch (outcome) {
    case LessonSaveCreated():
      finishLessonEditor(context, 'Занятие создано');
    case LessonSaveNotes():
      finishLessonEditor(context, 'Заметка сохранена');
    case LessonSaveConfirmed():
      finishLessonEditor(context, 'Изменения занятия применены');
    case LessonSavePreview():
      scrollToLessonPreview(context, scrollController);
    case LessonSaveInvalid(:final validation):
      onInvalid(validation);
    case LessonSaveViolations(:final violations):
      onViolations(LessonScheduleAnalysis.fromViolations(violations));
      await showLessonEditorConstraints(
        context,
        violations,
        onOpen: onOpenConstraint,
      );
    case LessonSaveDecision():
      throw StateError('Предварительный расчёт занятия не получен.');
    case LessonSaveFailure(:final error, :final reloadedSession):
      if (reloadedSession != null) onSessionReloaded(reloadedSession);
      showLessonEditorError(context, error, 'Не удалось сохранить занятие.');
    case LessonSaveBusy():
      break;
  }
}

bool completedMoveWarning(
  LessonEditorSession session,
  LessonEditorDraft draft,
  bool focusDateTime,
  LessonEditorDecisionPolicy policy,
) {
  final raw = session.snapshot?.rawLesson;
  final lifecycle =
      (raw?['lifecycle_state'] ?? raw?['lifecycleState'] ?? raw?['status'])
          ?.toString()
          .toLowerCase();
  final completed =
      lifecycle == 'successfully_completed' ||
      lifecycle == 'completed' ||
      lifecycle == 'done';
  if (!completed) return false;
  if (focusDateTime) return true;
  try {
    return policy.editRequest(session: session, draft: draft).operation ==
        LessonDecisionOperation.reschedule;
  } catch (_) {
    return false;
  }
}
