import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
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

/// Lesson details bottom sheet: student/teacher/room/time/status + conflicts,
/// with read-only lifecycle state plus Edit / Delete actions.
/// Extracted from _ScheduleWidgetState._showLessonDetails — presentation only,
/// the caller precomputes the display values and supplies the actions.
Future<void> showLessonDetailsSheet(
  BuildContext context, {
  required String teacherName,
  required String studentName,
  required String roomName,
  required String timeRange,
  required String currentStatus,
  required List<String> conflicts,
  required String? lessonId,
  required VoidCallback onEdit,
  required Future<void> Function() onDelete,
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
        detailRow(surfaceContext, Icons.person_rounded, 'Ученик', studentName),
        const SizedBox(height: 10),
        detailRow(surfaceContext, Icons.school_rounded, 'Педагог', teacherName),
        const SizedBox(height: 10),
        detailRow(surfaceContext, Icons.room_rounded, 'Аудитория', roomName),
        const SizedBox(height: 10),
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
              final confirmed = await _confirmLessonDelete(surfaceContext);
              if (confirmed != true) return;
              if (surfaceContext.mounted) Navigator.pop(surfaceContext);
              await onDelete();
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Удалить занятие'),
          ),
        ],
      ],
    ),
  );
}

Future<bool?> _confirmLessonDelete(BuildContext context) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.confirmation,
    title: 'Удалить занятие?',
    builder: (_) =>
        const Text('Занятие будет удалено из расписания безвозвратно.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Оставить'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: AppColor.danger),
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Удалить'),
      ),
    ],
  );
}
