import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// A secondary settlement cue; the existing lifecycle background stays intact.
class LessonSettlementCorner extends StatelessWidget {
  const LessonSettlementCorner({
    super.key,
    required this.settlementTypeKey,
    required this.child,
    this.timeline = false,
    this.expand = true,
  });

  final String? settlementTypeKey;
  final Widget child;
  final bool timeline;
  final bool expand;

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
    null || '' || 'lesson' => null,
    'trial_lesson' => AppColor.settlementTrial,
    'partially_paid_lesson' ||
    'partially_paid_miss' => AppColor.settlementPartial,
    'free_lesson' => AppColor.settlementFree,
    'paid_miss' || 'penalty_lesson' => AppColor.settlementPaidMiss,
    _ => AppColor.settlementUnpaid,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(settlementTypeKey);
    if (color == null) return child;
    final label = labelFor(settlementTypeKey)!;
    return Semantics(
      label: 'Тип списания: $label',
      child: Stack(
        fit: expand ? StackFit.expand : StackFit.loose,
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(right: timeline ? 0 : 12),
            child: child,
          ),
          Positioned(
            top: timeline ? -1 : 0,
            right: timeline ? -1 : 0,
            child: Tooltip(
              message: label,
              child: CustomPaint(
                key: ValueKey('settlement-corner-$settlementTypeKey'),
                size: const Size(11, 11),
                painter: _CornerPainter(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - 3, 0)
      ..quadraticBezierTo(size.width, 0, size.width, 3)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => oldDelegate.color != color;
}
