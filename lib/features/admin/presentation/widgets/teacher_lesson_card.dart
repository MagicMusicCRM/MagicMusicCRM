import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// A single lesson row in the by-teacher day column: time, student, room, and a
/// conflict/status marker. Extracted from _ScheduleWidgetState — pure display;
/// the caller resolves names/colours and supplies onTap.
class TeacherLessonCard extends StatelessWidget {
  final String timeStr;
  final String studentName;
  final String roomName;
  final Color roomColor;
  final Color statusColor;
  final bool hasConflict;
  final VoidCallback onTap;

  const TeacherLessonCard({
    super.key,
    required this.timeStr,
    required this.studentName,
    required this.roomName,
    required this.roomColor,
    required this.statusColor,
    required this.hasConflict,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: !hasConflict
              ? Theme.of(context).colorScheme.surface
              : AppColor.danger.withAlpha(24),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: !hasConflict ? roomColor : AppColor.danger,
              width: 4,
            ),
          ),
        ),
        child: Row(
          children: [
            // Time
            Column(
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    color: roomColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    studentName,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    roomName,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withAlpha(180),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Status indicator
            if (hasConflict)
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColor.danger,
                size: 18,
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
