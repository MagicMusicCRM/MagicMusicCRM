import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';

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
      return 'Проведено';
    case 'cancelled':
      return 'Отменено';
    case 'scheduled':
    case 'planned':
      return 'Запланировано';
    default:
      return status ?? 'Запланировано';
  }
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
  bool showNewTabAction,
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
  return Semantics(
    button: true,
    link: true,
    label: '${reference.label}: ${reference.value}',
    child: InkWell(
      key: ValueKey('lesson-reference-${reference.label}'),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => onOpen(EntityOpenTarget.current),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(
          children: [
            Icon(reference.icon, size: 18, color: AppColor.gold),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                '${reference.label}: ${reference.value}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (showNewTabAction)
              IconButton(
                tooltip: 'Открыть в новой вкладке',
                onPressed: () => onOpen(EntityOpenTarget.newTab),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
              ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    ),
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
  bool showNewTabAction = false,
  required String timeRange,
  required String currentStatus,
  required List<String> conflicts,
  required String? lessonId,
  required VoidCallback onEdit,
  required Future<void> Function() onCancel,
  Future<void> Function()? onSettle,
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
          }, showNewTabAction),
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
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 10),
          detailRow(
            surfaceContext,
            Icons.warning_amber_rounded,
            'Конфликты',
            conflicts.map(conflictLabel).join(', '),
          ),
        ],
        if (lessonId != null) ...[
          const SizedBox(height: AppSpace.lg),
          if (onSettle != null) ...[
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(surfaceContext);
                await onSettle();
              },
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Зафиксировать результат'),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(surfaceContext);
              onEdit();
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Перенести или изменить'),
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
