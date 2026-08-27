import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';

import 'students_board_card.dart';
import 'students_board_models.dart';

class StudentStatusColumn extends StatelessWidget {
  const StudentStatusColumn({
    super.key,
    required this.column,
    required this.transitions,
    required this.pendingStudentIds,
    required this.onTap,
    required this.onMove,
    required this.onOpenChat,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.nextCursor,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final StudentsBoardColumnData column;
  final Map<String, Set<String>> transitions;
  final Set<String> pendingStudentIds;
  final ValueChanged<Map<String, dynamic>> onTap;
  final Future<void> Function(Map<String, dynamic>, String) onMove;
  final ValueChanged<String> onOpenChat;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final String? nextCursor;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  bool _canAccept(Map<String, dynamic> student) {
    if (column.status == null) return false;
    final current = student['status']?.toString().trim().toLowerCase() ?? '';
    if (current == column.status) return false;
    final allowed = transitions[current];
    return allowed == null || allowed.contains(column.status);
  }

  @override
  Widget build(BuildContext context) => DragTarget<Map<String, dynamic>>(
    onWillAcceptWithDetails: (details) => _canAccept(details.data),
    onAcceptWithDetails: (details) {
      onDragEnd();
      if (column.status != null) onMove(details.data, column.status!);
    },
    builder: (context, accepted, rejected) {
      final hovering = accepted.whereType<Map<String, dynamic>>().any(
        _canAccept,
      );
      final denied = rejected.whereType<Map<String, dynamic>>().any(
        (student) => !_canAccept(student),
      );
      final accent = denied ? AppColor.danger : _stageColor(column.style);
      final screenWidth = MediaQuery.sizeOf(context).width;
      final width = screenWidth < 360
          ? (screenWidth - 24).clamp(220.0, 300.0)
          : 300.0;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: hovering
              ? accent.withAlpha(30)
              : Theme.of(context).colorScheme.surface.withAlpha(127),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: hovering ? accent : accent.withAlpha(65),
            width: hovering ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            _ColumnHeader(column: column, accent: accent),
            _DropHint(
              visible: hovering || denied,
              denied: denied,
              accent: accent,
            ),
            Expanded(child: _cards()),
          ],
        ),
      );
    },
  );

  Widget _cards() {
    if (column.students.isEmpty) {
      return _EmptyColumn(droppable: column.status != null);
    }
    return MagicDesktopScrollbar(
      axis: Axis.vertical,
      builder: (context, controller) => ListView.builder(
        controller: controller,
        key: PageStorageKey('students_col_${column.status ?? 'other'}'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount:
            column.students.length + (nextCursor?.isNotEmpty == true ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= column.students.length) {
            return _AutomaticPageLoader(
              cursor: nextCursor!,
              loading: loadingMore,
              onLoad: onLoadMore,
            );
          }
          final student = column.students[index];
          return StudentBoardCard(
            student: student,
            isPending: pendingStudentIds.contains(
              student['id']?.toString() ?? '',
            ),
            onTap: () => onTap(student),
            onOpenChat: onOpenChat,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
          );
        },
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.column, required this.accent});

  final StudentsBoardColumnData column;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Icon(Icons.school_rounded, size: 14, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            column.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: accent.withAlpha(90)),
          ),
          child: Text(
            '${column.students.length}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DropHint extends StatelessWidget {
  const _DropHint({
    required this.visible,
    required this.denied,
    required this.accent,
  });

  final bool visible;
  final bool denied;
  final Color accent;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    child: visible
        ? Container(
            height: 40,
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            decoration: BoxDecoration(
              border: Border.all(color: accent),
              borderRadius: BorderRadius.circular(AppRadius.control),
              color: accent.withAlpha(25),
            ),
            child: Center(
              child: Text(
                denied
                    ? 'Переход запрещён настройками'
                    : 'Отпустите, чтобы перенести',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}

class _AutomaticPageLoader extends StatefulWidget {
  const _AutomaticPageLoader({
    required this.cursor,
    required this.loading,
    required this.onLoad,
  });

  final String cursor;
  final bool loading;
  final VoidCallback onLoad;

  @override
  State<_AutomaticPageLoader> createState() => _AutomaticPageLoaderState();
}

class _AutomaticPageLoaderState extends State<_AutomaticPageLoader> {
  String? _requestedCursor;

  @override
  Widget build(BuildContext context) {
    if (!widget.loading && _requestedCursor != widget.cursor) {
      _requestedCursor = widget.cursor;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoad();
      });
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _EmptyColumn extends StatelessWidget {
  const _EmptyColumn({required this.droppable});

  final bool droppable;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 28,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withAlpha(140),
          ),
          const SizedBox(height: AppSpace.sm),
          const Text(
            'Нет учеников',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (droppable)
            const Text(
              'Перетащите карточку сюда',
              style: TextStyle(fontSize: 11),
            ),
        ],
      ),
    ),
  );
}

Color _stageColor(String style) => switch (style) {
  'cyan' => AppColor.transferCyan,
  'green' => AppColor.success,
  'amber' => AppColor.warning,
  'red' => AppColor.danger,
  'slate' => AppColor.text2,
  _ => AppColor.gold,
};
