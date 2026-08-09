part of 'students_board_widget.dart';

// ── Column data ────────────────────────────────────────────────────────────

class _StatusColumnData {
  final String? status; // null → «Прочие», non-droppable
  final String name;
  final String style;
  final Set<String> allowedTransitions;
  final List<Map<String, dynamic>> students;

  _StatusColumnData({
    required this.status,
    required this.name,
    required this.style,
    required this.allowedTransitions,
    required this.students,
  });
}

// ── Column ───────────────────────────────────────────────────────────────────

class _StatusColumn extends StatelessWidget {
  final _StatusColumnData column;
  final Map<String, Set<String>> transitions;
  final Set<String> pendingStudentIds;
  final ValueChanged<Map<String, dynamic>> onTap;
  final Future<void> Function(Map<String, dynamic>, String) onMove;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _StatusColumn({
    required this.column,
    required this.transitions,
    required this.pendingStudentIds,
    required this.onTap,
    required this.onMove,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  bool get _droppable => column.status != null;

  bool _canAccept(Map<String, dynamic> student) {
    if (!_droppable) return false;
    final current = student['status']?.toString().trim().toLowerCase() ?? '';
    if (current == column.status) return false;
    final allowed = transitions[current];
    return allowed == null || allowed.contains(column.status);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) => _canAccept(details.data),
      onAcceptWithDetails: (details) {
        onDragEnd();
        if (column.status != null) {
          onMove(details.data, column.status!);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.whereType<Map<String, dynamic>>().any(
          _canAccept,
        );
        final denied = rejectedData.whereType<Map<String, dynamic>>().any(
          (student) => !_canAccept(student),
        );
        final accent = denied
            ? AppColor.danger
            : _studentStageColor(column.style);
        final screenWidth = MediaQuery.of(context).size.width;
        final columnWidth = screenWidth < 360
            ? (screenWidth - 24).clamp(220.0, 300.0)
            : 300.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: columnWidth,
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
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.school_rounded, size: 14, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        column.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(
                          color: accent.withAlpha(90),
                          width: 1,
                        ),
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
              ),
              // ── Drop hint ─────────────────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: hovering || denied
                    ? Container(
                        height: 40,
                        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: accent),
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
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
              ),
              // ── Cards ─────────────────────────────────────────────────────
              Expanded(
                child: column.students.isEmpty
                    ? _buildEmptyColumn(context)
                    : MagicDesktopScrollbar(
                        axis: Axis.vertical,
                        builder: (context, controller) => ListView.builder(
                          controller: controller,
                          key: PageStorageKey(
                            'students_col_${column.status ?? 'other'}',
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: column.students.length,
                          itemBuilder: (context, index) {
                            final student = column.students[index];
                            final id = student['id']?.toString() ?? '';
                            return _StudentCard(
                              student: student,
                              isPending: pendingStudentIds.contains(id),
                              onTap: () => onTap(student),
                              onDragUpdate: onDragUpdate,
                              onDragEnd: onDragEnd,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyColumn(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 28,
              color: cs.onSurfaceVariant.withAlpha(140),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Нет учеников',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_droppable) ...[
              const SizedBox(height: 2),
              Text(
                'Перетащите карточку сюда',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withAlpha(160),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _studentStageColor(String style) => switch (style) {
  'cyan' => AppColor.transferCyan,
  'green' => AppColor.success,
  'amber' => AppColor.warning,
  'red' => AppColor.danger,
  'slate' => AppColor.text2,
  _ => AppColor.gold,
};

// ── Card ─────────────────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final bool isPending;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _StudentCard({
    required this.student,
    required this.isPending,
    required this.onTap,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = student['first_name']?.toString() ?? '';
    final lastName = student['last_name']?.toString() ?? '';
    final displayName = '$firstName $lastName'.trim();
    final name = displayName.isEmpty ? 'Без имени' : displayName;
    final phone = student['phone']?.toString() ?? '';

    final Widget feedback = Transform.rotate(
      angle: 0.03,
      child: Material(
        color: Colors.transparent,
        child: Builder(
          builder: (context) {
            final screenWidth = MediaQuery.of(context).size.width;
            final feedbackWidth = screenWidth < 360
                ? (screenWidth - 24).clamp(220.0, 300.0) - 24
                : 276.0;
            return Container(
              width: feedbackWidth,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: AppTheme.primaryGold, width: 2),
                boxShadow: AppShadow.shLift,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.school_rounded,
                    size: 14,
                    color: AppTheme.primaryGold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (phone.isNotEmpty)
                          Text(
                            phone,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.drag_indicator_rounded, size: 18),
                ],
              ),
            );
          },
        ),
      ),
    );
    // Faded placeholder gap in the source column while dragging.
    final Widget childWhenDragging = Opacity(
      opacity: 0.3,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: AppTheme.primaryGold.withAlpha(120)),
        ),
        child: const SizedBox(height: 64, width: double.infinity),
      ),
    );
    final Widget cardChild = Opacity(
      opacity: isPending ? 0.62 : 1,
      child: AbsorbPointer(
        absorbing: isPending,
        child: GestureDetector(
          onTap: onTap,
          child: _CardBody(student: student, isPending: isPending),
        ),
      ),
    );

    final platform = Theme.of(context).platform;
    final desktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    // Desktop (mouse): an immediate Draggable so a plain click-drag moves the
    // card — press-and-hold is a touch idiom. A motionless click still falls
    // through to onTap (same pattern as the schedule day canvas).
    if (desktop) {
      return Draggable<Map<String, dynamic>>(
        data: student,
        maxSimultaneousDrags: isPending ? 0 : null,
        onDragUpdate: (details) => onDragUpdate(details.globalPosition),
        onDragEnd: (_) => onDragEnd(),
        onDraggableCanceled: (_, _) => onDragEnd(),
        onDragCompleted: onDragEnd,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: cardChild,
      );
    }
    return LongPressDraggable<Map<String, dynamic>>(
      data: student,
      maxSimultaneousDrags: isPending ? 0 : null,
      // Snappier than the platform 500ms long-press while still separating a
      // tap (tap → open) from a deliberate drag on touch.
      delay: const Duration(milliseconds: 250),
      hapticFeedbackOnStart: true,
      onDragUpdate: (details) => onDragUpdate(details.globalPosition),
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (_, _) => onDragEnd(),
      onDragCompleted: onDragEnd,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: cardChild,
    );
  }
}

class _CardBody extends ConsumerWidget {
  final Map<String, dynamic> student;
  final bool isPending;

  const _CardBody({required this.student, required this.isPending});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = student['first_name']?.toString() ?? '';
    final lastName = student['last_name']?.toString() ?? '';
    final displayName = '$firstName $lastName'.trim();
    final name = displayName.isEmpty ? 'Без имени' : displayName;
    final phone = student['phone']?.toString() ?? '';
    final linkedUserId = student['is_app_account'] == true
        ? student['linked_user_id']?.toString() ?? ''
        : '';
    final branchName = student['branch_name']?.toString() ?? '';
    final customData = student['custom_data'];
    final discipline = customData is Map
        ? customData['discipline']?.toString() ?? ''
        : '';
    final openTasks = _intValue(student['open_tasks_count']);
    final lessonsCount = _intValue(student['lessons_count']);
    final groupsCount = _intValue(student['groups_count']);

    // Жёлтым — ученик, по которому не висит ни одной задачи: про него забыли
    // (требование заказчика 17.07). Тот же приём, что на доске лидов, и то же
    // правило — см. no_open_tasks_highlight.
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
            : BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Name + pending spinner ────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
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
                    onPressed: () => ref
                        .read(messengerNavigationProvider.notifier)
                        .navigateTo(
                          MessengerNavigationState(partnerId: linkedUserId),
                        ),
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
            // ── Phone ─────────────────────────────────────────────────────
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
            // ── Discipline badge ──────────────────────────────────────────
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
            // ── Branch badge ──────────────────────────────────────────────
            if (branchName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _IconBadge(
                  icon: Icons.location_on_outlined,
                  text: branchName,
                ),
              ),
            // ── Metric badges (tasks / lessons / groups) ──────────────────
            if (openTasks > 0 || lessonsCount > 0 || groupsCount > 0)
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
                    if (lessonsCount > 0)
                      _MetricBadge(
                        icon: Icons.event_rounded,
                        text: '$lessonsCount',
                      ),
                    if (groupsCount > 0)
                      _MetricBadge(
                        icon: Icons.group_rounded,
                        text: '$groupsCount',
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

// ── Shared badge widgets ──────────────────────────────────────────────────────

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

class _MetricBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetricBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
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
}
