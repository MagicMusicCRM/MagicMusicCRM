import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';

import 'recurring_schedule_plan_section.dart';

/// Canonical schedule surface in the client card.
///
/// Students use atomic recurring Schedule Plans. Leads only retain the lesson
/// date tray; the legacy preference-series editor is intentionally not mounted.
class StudentScheduleSection extends StatefulWidget {
  final String clientType;
  final String clientId;
  final List<Map<String, dynamic>> lessons;
  final List<Map<String, dynamic>> branches;
  final String? defaultBranchId;
  final List<Map<String, dynamic>> subscriptions;
  final bool canWrite;
  final VoidCallback onChanged;
  final ValueChanged<Map<String, dynamic>>? onOpenLesson;

  const StudentScheduleSection({
    super.key,
    required this.clientType,
    required this.clientId,
    required this.lessons,
    required this.branches,
    required this.defaultBranchId,
    required this.canWrite,
    this.subscriptions = const [],
    required this.onChanged,
    this.onOpenLesson,
  });

  @override
  State<StudentScheduleSection> createState() => _StudentScheduleSectionState();
}

class _StudentScheduleSectionState extends State<StudentScheduleSection> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.clientType == 'student') {
      return RecurringSchedulePlanSection(
        studentId: widget.clientId,
        fallbackLessons: widget.lessons,
        branches: widget.branches,
        defaultBranchId: widget.defaultBranchId,
        subscriptions: widget.subscriptions,
        canWrite: widget.canWrite,
        onChanged: widget.onChanged,
        onOpenLesson: widget.onOpenLesson,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_lessonStrip(cs), _paidLegend(cs)],
    );
  }

  /// Легенда к зелёному уголку с рублём.
  ///
  /// Показывается, только когда в ленте есть хоть один оплаченный день: иначе
  /// это подпись к тому, чего не видно. И важнее самой легенды — оговорка:
  /// отсутствие метки НЕ означает «не оплачено». Платёж к занятию привязывать
  /// не обязательно, а у импортированных из HolliHop такой связи нет вовсе.
  Widget _paidLegend(ColorScheme cs) {
    final anyPaid = widget.lessons.any((l) => l['paid_amount'] != null);
    if (!anyPaid) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColor.success,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const Text(
              '₽',
              style: TextStyle(
                fontSize: 6,
                height: 1,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '— за день есть платёж. Без метки — платёж к этому дню не '
              'привязан (это не значит «не оплачено»).',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  // ── Лента дат-квадратиков (HolliHop image2) ────────────────────────────────
  Widget _lessonStrip(ColorScheme cs) {
    final now = DateTime.now();
    final sorted =
        widget.lessons
            .map((l) {
              final dt = DateTime.tryParse(l['scheduled_at']?.toString() ?? '');
              return dt == null ? null : (dt, l);
            })
            .whereType<(DateTime, Map<String, dynamic>)>()
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    if (sorted.isEmpty) return const SizedBox.shrink();
    final past = sorted.where((e) => e.$1.isBefore(now)).toList();
    final future = sorted.where((e) => !e.$1.isBefore(now)).toList();
    final window = [
      ...past.skip(past.length > 12 ? past.length - 12 : 0),
      ...future.take(16),
    ];
    return SingleChildScrollView(
      key: const Key('client-lesson-date-tray'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (dt, lesson) in window)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _dateSquare(dt, lesson),
            ),
        ],
      ),
    );
  }

  Widget _dateSquare(DateTime dt, Map<String, dynamic> lesson) {
    final projection = LessonStateProjection.fromMap(lesson);
    final accent = projection.token.accent;
    final isTrial = lesson['is_trial'] == true;
    final notes = (lesson['notes'] ?? '').toString().trim();
    // ✔ Владелец 17.07: «оплаты по дням в расписании». Считает сервер — сумма
    // платежей, привязанных к этому занятию. null означает «за этот день
    // платежа нет», а не «оплачено 0»: привязывать платёж к занятию не
    // обязательно (аванс на счёт, абонемент, импорт из HolliHop), поэтому
    // отсутствие метки НЕ значит «не оплачено».
    final paid = (lesson['paid_amount'] as num?)?.toDouble();
    final tooltip = [
      DateFormat('dd.MM.yyyy HH:mm', 'ru').format(dt.toLocal()),
      projection.label,
      if (isTrial) 'Пробное занятие',
      if (paid != null) 'Оплачено: ${_money(paid)} ₽',
      if (notes.isNotEmpty) notes,
    ].join('\n');
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        key: ValueKey('client-lesson-${lesson['id']}'),
        borderRadius: BorderRadius.circular(4),
        onTap: widget.canWrite && widget.onOpenLesson != null
            ? () => widget.onOpenLesson!(lesson)
            : null,
        child: Stack(
          children: [
            Container(
              width: 46,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: projection.token.soft,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Text(
                DateFormat('d.MM').format(dt.toLocal()),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            if (isTrial)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColor.gold,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'П',
                    style: TextStyle(
                      fontSize: 6,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            // Оплаченный день — уголок с рублём внизу слева: правый верхний уже
            // занят пропуском, а день бывает и пропущенным, и оплаченным.
            if (paid != null)
              Positioned(
                bottom: 0,
                left: 0,
                child: Container(
                  width: 12,
                  height: 10,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColor.success,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                  child: const Text(
                    '₽',
                    style: TextStyle(
                      fontSize: 7,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// «1 500» вместо «1500.0»: сумма в тултипе читается человеком.
  String _money(double value) {
    final rounded = value.roundToDouble() == value ? value.round() : value;
    return NumberFormat.decimalPattern('ru').format(rounded);
  }
}
