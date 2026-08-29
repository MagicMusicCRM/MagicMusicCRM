import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface_kind.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_form.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

export 'lesson_decision/lesson_decision_controller.dart';
export 'lesson_decision/lesson_decision_models.dart';

Future<bool?> showLessonDecisionFlow(
  BuildContext context, {
  required MagicCrmService crm,
  required LessonDecisionOperation operation,
  required Map<String, dynamic> lesson,
  required bool canManageTeacherCompensation,
  Map<String, dynamic>? successor,
  String? initialSettlementTypeKey,
  String? initialCompensationRuleKey,
  String? initialCompensationValueMinor,
}) {
  final controller = LessonDecisionController(
    crm: crm,
    operation: operation,
    lesson: lesson,
    canManageTeacherCompensation: canManageTeacherCompensation,
    successor: successor,
    initialSettlementTypeKey: initialSettlementTypeKey,
    initialCompensationRuleKey: initialCompensationRuleKey,
    initialCompensationValueMinor: initialCompensationValueMinor,
  );
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.quickView,
    title: operation.title,
    subtitle: 'Сначала расчёт, затем подтверждение',
    icon: Icons.rule_rounded,
    builder: (_) => LessonDecisionForm(controller: controller),
  );
}
