import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';

/// One icon+label+value row inside the lesson details sheet. Pure.
Widget detailRow(
  BuildContext context,
  IconData icon,
  String label,
  String value,
) {
  return Row(
    children: [
      Icon(icon, size: 18, color: AppColor.gold),
      SizedBox(width: 8),
      Text(
        '$label: ',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

/// Human-readable RU label for a lesson status. Pure.
String lessonStatusLabel(String? status) {
  switch (status) {
    case 'completed':
    case 'done':
    case 'successfully_completed':
      return 'Завершено';
    case 'settlement_pending':
      return 'Конфликт';
    case 'cancelled':
      return 'Отменено';
    case 'scheduled':
    case 'planned':
      return 'Забронировано';
    default:
      return status ?? 'Забронировано';
  }
}

/// Safe staff-facing explanation for an automatic settlement failure.
/// Backend failure identifiers and exception messages must never be rendered
/// verbatim: they may contain implementation details and are not actionable.
String lessonSettlementIssueLabel(String? failureCode) {
  return switch (failureCode) {
    'LESSON_SETTLEMENT_PLAN_MISSING' =>
      'Не найден план списания и оплаты преподавателю.',
    'LESSON_SNAPSHOT_INCOMPLETE' =>
      'В занятии не хватает данных для автоматического расчёта.',
    'CLIENT_FUNDING_SOURCE_REQUIRED' => 'Не выбран источник оплаты клиента.',
    'TEACHER_COMPENSATION_RULE_NOT_FOUND' =>
      'Не найдено правило оплаты преподавателю.',
    _ =>
      'Автоматический расчёт не завершён. Проверьте списание и оплату преподавателю.',
  };
}

/// Human-readable RU label for a schedule conflict type. Pure.
String conflictLabel(String type) {
  return switch (type) {
    'room_overlap' => 'пересечение аудитории',
    'teacher_overlap' => 'пересечение педагога',
    'missing_teacher' => 'не назначен педагог',
    'branch_mismatch' => 'филиал не совпадает',
    _ => type,
  };
}

class LessonEntityReference {
  const LessonEntityReference({
    required this.icon,
    required this.label,
    required this.value,
    this.link,
    this.available = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final EntityLink? link;
  final bool available;
}

Widget _referenceRow(
  BuildContext context,
  LessonEntityReference reference,
  ValueChanged<EntityOpenTarget> onOpen,
) {
  final canOpen = reference.link != null && reference.available;
  if (!canOpen) {
    return detailRow(
      context,
      reference.icon,
      reference.label,
      reference.available ? reference.value : 'Связанная запись недоступна',
    );
  }
  return Row(
    children: [
      Icon(reference.icon, size: 18, color: AppColor.gold),
      const SizedBox(width: AppSpace.sm),
      Text(
        '${reference.label}: ',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      Expanded(
        child: EntityLinkText(
          key: ValueKey('lesson-reference-${reference.label}'),
          text: reference.value,
          onPressed: () => onOpen(EntityOpenTarget.current),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

/// Lesson details bottom sheet: student/teacher/room/time/status + conflicts,
/// with read-only lifecycle state plus unified edit/cancel/settle actions.
/// Extracted from _ScheduleWidgetState._showLessonDetails — presentation only,
/// the caller precomputes the display values and supplies the actions.
Future<void> showLessonDetailsSheet(
  BuildContext context, {
  required String teacherName,
  required String studentName,
  required String roomName,
  List<LessonEntityReference>? references,
  void Function(EntityLink link, EntityOpenTarget target)? onOpenReference,
  required String timeRange,
  required String currentStatus,
  required List<String> conflicts,
  required String? lessonId,
  required VoidCallback onEdit,
  required Future<void> Function() onCancel,
  String? settlementIssue,
  List<Map<String, dynamic>> settlementHistory = const [],
}) {
  return showMagicAdaptiveSurface<void>(
    context,
    kind: AppSurfaceKind.quickView,
    title: studentName,
    subtitle: timeRange,
    icon: Icons.event_note_rounded,
    builder: (surfaceContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final reference
            in references ??
                [
                  LessonEntityReference(
                    icon: Icons.person_rounded,
                    label: 'Ученик',
                    value: studentName,
                  ),
                  LessonEntityReference(
                    icon: Icons.school_rounded,
                    label: 'Педагог',
                    value: teacherName,
                  ),
                  LessonEntityReference(
                    icon: Icons.room_rounded,
                    label: 'Аудитория',
                    value: roomName,
                  ),
                ]) ...[
          _referenceRow(surfaceContext, reference, (target) {
            Navigator.pop(surfaceContext);
            onOpenReference?.call(reference.link!, target);
          }),
          const SizedBox(height: 10),
        ],
        detailRow(
          surfaceContext,
          Icons.access_time_rounded,
          'Время',
          timeRange,
        ),
        const SizedBox(height: 10),
        detailRow(
          surfaceContext,
          Icons.info_outline_rounded,
          'Статус',
          lessonStatusLabel(currentStatus),
        ),
        if (settlementIssue?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 10),
          detailRow(
            surfaceContext,
            Icons.warning_amber_rounded,
            'Причина конфликта',
            settlementIssue!.trim(),
          ),
        ],
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 10),
          detailRow(
            surfaceContext,
            Icons.warning_amber_rounded,
            'Конфликты',
            conflicts.map(conflictLabel).join(', '),
          ),
        ],
        if (settlementHistory.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          ExpansionTile(
            key: const Key('lesson-settlement-history'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSpace.sm),
            title: const Text(
              'История расчёта',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            children: [
              for (final item in settlementHistory)
                _SettlementHistoryEntry(item: item),
            ],
          ),
        ],
        if (lessonId != null) ...[
          const SizedBox(height: AppSpace.lg),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(surfaceContext);
              onEdit();
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Изменить занятие'),
          ),
          const SizedBox(height: AppSpace.sm),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColor.danger),
            onPressed: () async {
              Navigator.pop(surfaceContext);
              await onCancel();
            },
            icon: const Icon(Icons.event_busy_outlined, size: 18),
            label: const Text('Отменить занятие'),
          ),
        ],
      ],
    ),
  );
}

class _SettlementHistoryEntry extends StatelessWidget {
  const _SettlementHistoryEntry({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final effective = item['effective'] == true;
    final reason = item['reason']?.toString().trim();
    final kind = switch (item['kind']) {
      'correction' => 'Корректировка',
      'transition' => 'Расчёт занятия',
      _ => 'План расчёта',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: effective
            ? AppColor.success.withValues(alpha: 0.12)
            : AppColor.input,
        border: Border.all(
          color: effective ? AppColor.success : AppColor.divider,
        ),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$kind · ${effective ? 'действующий' : 'заменён'}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Списание: ${item['settlementTypeLabel'] ?? 'Тип из справочника'} · '
            'преподаватель: ${item['teacherCompensationRuleLabel'] ?? 'Правило из справочника'}',
            style: const TextStyle(fontSize: 12),
          ),
          if (reason?.isNotEmpty == true)
            Text('Причина: $reason', style: const TextStyle(fontSize: 12)),
          Text(
            '${item['actorName'] ?? 'Сотрудник'} · ${_historyDate(item['createdAt'])}',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _historyDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (date == null) return 'Не указано';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}
