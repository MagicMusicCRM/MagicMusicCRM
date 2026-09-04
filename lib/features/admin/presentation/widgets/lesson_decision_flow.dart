import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface_kind.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_form.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'lesson_editor/lesson_editor_feedback.dart';
import 'lesson_editor/lesson_editor_models.dart';

export 'lesson_decision/lesson_decision_controller.dart';
export 'lesson_decision/lesson_decision_models.dart';
export 'lesson_editor/lesson_editor_view.dart' show LessonEditorDismissGuard;

Future<bool?> showLessonEditorSurface(
  BuildContext context, {
  required String title,
  required Widget Function(bool embeddedSurface) editor,
}) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.quickView,
    title: title,
    subtitle: 'Расписание и расчёт занятия',
    icon: Icons.event_note_rounded,
    routeSettings: const RouteSettings(name: 'lesson-editor'),
    builder: (_) => editor(true),
  );
}

void finishLessonEditor(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  Navigator.pop(context, true);
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

Future<void> showLessonEditorConstraints(
  BuildContext context,
  List<LessonConstraintViolation> violations, {
  required ValueChanged<String> onOpen,
}) => showMagicDialog<void>(
  context: context,
  builder: (dialogContext) => LessonConstraintDialog(
    violations: violations,
    onOpen: (lessonId) {
      Navigator.pop(dialogContext);
      onOpen(lessonId);
    },
    onFix: () => Navigator.pop(dialogContext),
  ),
);

Future<bool?> showLessonDecisionFlow(
  BuildContext context, {
  required MagicCrmService crm,
  required LessonDecisionOperation operation,
  required Map<String, dynamic> lesson,
  required bool canManageTeacherCompensation,
  Map<String, dynamic>? successor,
  Map<String, dynamic>? resources,
  String? initialSettlementTypeKey,
  String? initialCompensationRuleKey,
  String? initialCompensationValueMinor,
  LessonDecisionCommitted? afterCommit,
}) {
  final controller = LessonDecisionController(
    crm: crm,
    operation: operation,
    lesson: lesson,
    canManageTeacherCompensation: canManageTeacherCompensation,
    successor: successor,
    resources: resources,
    initialSettlementTypeKey: initialSettlementTypeKey,
    initialCompensationRuleKey: initialCompensationRuleKey,
    initialCompensationValueMinor: initialCompensationValueMinor,
    afterCommit: afterCommit,
  );
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.quickView,
    title: operation.title,
    subtitle: 'Сначала расчёт, затем подтверждение',
    icon: Icons.rule_rounded,
    builder: (_) => GuardedLessonDecisionForm(controller: controller),
  );
}
