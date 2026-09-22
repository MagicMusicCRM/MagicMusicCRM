import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Canonical settlement-type surface. Lifecycle is shown by an icon, while
/// payment warnings remain secondary cues and never replace this background.
class LessonSettlementCorner extends StatelessWidget {
  const LessonSettlementCorner({
    super.key,
    required this.settlementTypeKey,
    required this.child,
    this.timeline = false,
    this.expand = true,
    this.surfaceOwnedByParent = false,
  });

  final String? settlementTypeKey;
  final Widget child;
  final bool timeline;
  final bool expand;

  /// Calendar/timeline tiles already own their outline and full tooltip.
  final bool surfaceOwnedByParent;

  static String? labelFor(String? key) => switch (key) {
    null || '' => null,
    'lesson' => 'Занятие',
    'trial_lesson' => 'Пробный урок — бесплатно для клиента',
    'partially_paid_lesson' => 'Частично оплачиваемое занятие',
    'free_lesson' => 'Бесплатное занятие',
    'paid_miss' => 'Оплачиваемый пропуск',
    'partially_paid_miss' => 'Частично оплачиваемый пропуск',
    'unpaid_miss' => 'Неоплачиваемый пропуск',
    'penalty_lesson' => 'Занятие со штрафом',
    _ => 'Другой тип списания',
  };

  static Color? colorFor(String? key) => switch (key) {
    null || '' => null,
    'lesson' => AppColor.actionBlue,
    'trial_lesson' => AppColor.settlementTrial,
    'partially_paid_lesson' ||
    'partially_paid_miss' => AppColor.settlementPartial,
    'free_lesson' => AppColor.settlementFree,
    'paid_miss' || 'penalty_lesson' => AppColor.settlementPaidMiss,
    _ => AppColor.settlementUnpaid,
  };

  static String effectiveKey(String? key, {bool isTrial = false}) {
    final normalized = key?.trim();
    if (normalized?.isNotEmpty == true) return normalized!;
    return isTrial ? 'trial_lesson' : 'lesson';
  }

  static Color backgroundFor(String? key, {bool isTrial = false}) =>
      switch (effectiveKey(key, isTrial: isTrial)) {
        'lesson' => AppColor.settlementLessonFill,
        'trial_lesson' => AppColor.settlementTrialFill,
        'partially_paid_lesson' => AppColor.settlementPartialFill,
        'free_lesson' => AppColor.settlementFreeFill,
        'paid_miss' => AppColor.settlementPaidMissFill,
        'partially_paid_miss' => AppColor.settlementPartialMissFill,
        'penalty_lesson' => AppColor.settlementPenaltyFill,
        _ => AppColor.settlementUnpaidFill,
      };

  @override
  Widget build(BuildContext context) {
    if (surfaceOwnedByParent) {
      return KeyedSubtree(
        key: ValueKey('settlement-background-$settlementTypeKey'),
        child: child,
      );
    }
    final color = colorFor(settlementTypeKey);
    if (color == null) return child;
    final label = labelFor(settlementTypeKey)!;
    return Semantics(
      label: 'Тип списания: $label',
      child: Tooltip(
        message: label,
        child: DecoratedBox(
          key: ValueKey('settlement-background-$settlementTypeKey'),
          decoration: BoxDecoration(
            color: backgroundFor(settlementTypeKey),
            border: Border.all(color: color.withValues(alpha: 0.42)),
            borderRadius: BorderRadius.circular(timeline ? 3 : 6),
          ),
          child: child,
        ),
      ),
    );
  }
}
