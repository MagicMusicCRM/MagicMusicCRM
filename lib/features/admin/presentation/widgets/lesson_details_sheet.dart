import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

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
/// with Complete / Edit / Cancel / Delete actions wired through callbacks.
/// Extracted from _ScheduleWidgetState._showLessonDetails — presentation only,
/// the caller precomputes the display values and supplies the actions.
Future<void> showLessonDetailsSheet(
  BuildContext context, {
  required Map<String, dynamic> lesson,
  required String teacherName,
  required String studentName,
  required String roomName,
  required String timeRange,
  required String currentStatus,
  required List<String> conflicts,
  required String? lessonId,
  required bool completable,
  required VoidCallback onEdit,
  required Future<void> Function() onDelete,
  required Future<void> Function(String status, String message) onUpdateStatus,
}) {
  return
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColor.scrim,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.sheet),
                ),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 2),
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColor.goldSoft,
                            borderRadius: BorderRadius.circular(AppRadius.icon),
                            border: Border.all(color: AppColor.goldLine),
                          ),
                          child: const Icon(
                            Icons.event_note_rounded,
                            size: 20,
                            color: AppColor.gold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  timeRange,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          iconSize: 20,
                          color: cs.onSurfaceVariant,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          detailRow(ctx, Icons.person_rounded, 'Ученик', studentName),
                          const SizedBox(height: 10),
                          detailRow(ctx, 
                            Icons.school_rounded,
                            'Педагог',
                            teacherName,
                          ),
                          const SizedBox(height: 10),
                          detailRow(ctx, Icons.room_rounded, 'Аудитория', roomName),
                          const SizedBox(height: 10),
                          detailRow(ctx, 
                            Icons.access_time_rounded,
                            'Время',
                            timeRange,
                          ),
                          const SizedBox(height: 10),
                          detailRow(ctx, 
                            Icons.info_outline_rounded,
                            'Статус',
                            lessonStatusLabel(currentStatus),
                          ),
                          if (conflicts.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            detailRow(ctx, 
                              Icons.warning_amber_rounded,
                              'Конфликты',
                              conflicts.map(conflictLabel).join(', '),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                    child: Column(
                      children: [
                        if (completable) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: Material(
                              color: AppColor.gold,
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.control,
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onUpdateStatus(
                                    'completed',
                                    'Занятие отмечено проведённым',
                                  );
                                },
                                child: const Center(
                                  child: Text(
                                    'Завершить',
                                    style: TextStyle(
                                      color: AppColor.onGold,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            if (lessonId != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    onEdit();
                                  },
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Изменить'),
                                ),
                              ),
                            if (lessonId != null &&
                                currentStatus != 'cancelled') ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColor.danger,
                                    side: const BorderSide(
                                      color: AppColor.danger,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Отменить занятие?'),
                                        content: const Text(
                                          'Занятие будет помечено как отменённое.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Нет'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: AppColor.danger,
                                            ),
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Отменить занятие'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      await onUpdateStatus(
                                        'cancelled',
                                        'Занятие отменено',
                                      );
                                    }
                                  },
                                  child: const Text('Отменить'),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (lessonId != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColor.danger,
                            ),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Удалить занятие?'),
                                  content: const Text(
                                    'Занятие будет удалено из расписания безвозвратно.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Нет'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColor.danger,
                                      ),
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Удалить'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                if (ctx.mounted) Navigator.pop(ctx);
                                await onDelete();
                              }
                            },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Удалить занятие'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
}
