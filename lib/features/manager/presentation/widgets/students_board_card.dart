import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/utils/client_custom_field_display.dart';
import 'package:magic_music_crm/core/widgets/no_open_tasks_highlight.dart';

import 'students_board_drag_feedback.dart';

class StudentBoardCard extends StatelessWidget {
  const StudentBoardCard({
    super.key,
    required this.student,
    required this.isPending,
    required this.onTap,
    required this.onOpenChat,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Map<String, dynamic> student;
  final bool isPending;
  final VoidCallback onTap;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final firstName = student['first_name']?.toString() ?? '';
    final lastName = student['last_name']?.toString() ?? '';
    final displayName = '$firstName $lastName'.trim();
    final name = displayName.isEmpty ? 'Без имени' : displayName;
    final phone = student['phone']?.toString() ?? '';
    final child = Opacity(
      opacity: isPending ? .62 : 1,
      child: AbsorbPointer(
        absorbing: isPending,
        child: GestureDetector(
          onTap: onTap,
          child: _CardBody(
            student: student,
            isPending: isPending,
            onOpenChat: onOpenChat,
          ),
        ),
      ),
    );
    final feedback = StudentBoardDragFeedback(name: name, phone: phone);
    final placeholder = Opacity(
      opacity: .3,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: AppTheme.primaryGold.withAlpha(120)),
        ),
        child: const SizedBox(height: 64, width: double.infinity),
      ),
    );
    final desktop = {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(Theme.of(context).platform);
    if (desktop) {
      return Draggable<Map<String, dynamic>>(
        data: student,
        maxSimultaneousDrags: isPending ? 0 : null,
        onDragUpdate: (details) => onDragUpdate(details.globalPosition),
        onDragEnd: (_) => onDragEnd(),
        onDraggableCanceled: (_, _) => onDragEnd(),
        onDragCompleted: onDragEnd,
        feedback: feedback,
        childWhenDragging: placeholder,
        child: child,
      );
    }
    return LongPressDraggable<Map<String, dynamic>>(
      data: student,
      maxSimultaneousDrags: isPending ? 0 : null,
      delay: const Duration(milliseconds: 250),
      hapticFeedbackOnStart: true,
      onDragUpdate: (details) => onDragUpdate(details.globalPosition),
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (_, _) => onDragEnd(),
      onDragCompleted: onDragEnd,
      feedback: feedback,
      childWhenDragging: placeholder,
      child: child,
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.student,
    required this.isPending,
    required this.onOpenChat,
  });

  final Map<String, dynamic> student;
  final bool isPending;
  final ValueChanged<String> onOpenChat;

  @override
  Widget build(BuildContext context) {
    final name = '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'
        .trim();
    final phone = student['phone']?.toString() ?? '';
    final linkedUserId = student['is_app_account'] == true
        ? student['linked_user_id']?.toString() ?? ''
        : '';
    final customData = student['custom_data'];
    final discipline = customData is Map
        ? customData['discipline']?.toString() ?? ''
        : '';
    final openTasks = _intValue(student['open_tasks_count']);
    final lessons = _intValue(student['lessons_count']);
    final groups = _intValue(student['groups_count']);
    final fields = (student['table_custom_fields'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    final forgotten = hasNoOpenTasks(openTasks);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: forgotten
          ? noOpenTasksSurface(context)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: forgotten
            ? noOpenTasksBorder()
            : BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name.isEmpty ? 'Без имени' : name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (linkedUserId.isNotEmpty)
                  IconButton(
                    tooltip: 'Написать в чат',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => onOpenChat(linkedUserId),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: AppColor.gold,
                    ),
                  ),
                if (isPending)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  phone,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (discipline.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withAlpha(51),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  discipline,
                  style: const TextStyle(
                    color: AppTheme.primaryGold,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (fields.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final field in fields)
                      KeyedSubtree(
                        key: ValueKey('student-table-field-${field['key']}'),
                        child: _Badge(
                          icon: Icons.tune_rounded,
                          text: clientTableFieldText(field),
                        ),
                      ),
                  ],
                ),
              ),
            if ((student['branch_name']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _Badge(
                  icon: Icons.location_on_outlined,
                  text: student['branch_name'].toString(),
                ),
              ),
            if (openTasks > 0 || lessons > 0 || groups > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (openTasks > 0)
                      _MetricBadge(
                        icon: Icons.task_alt_rounded,
                        text: '$openTasks',
                      ),
                    if (lessons > 0)
                      _MetricBadge(icon: Icons.event_rounded, text: '$lessons'),
                    if (groups > 0)
                      _MetricBadge(icon: Icons.group_rounded, text: '$groups'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _intValue(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: AppTheme.primaryGold.withAlpha(36),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.primaryGold),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: AppTheme.primaryGold,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
