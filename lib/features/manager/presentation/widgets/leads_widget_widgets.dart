part of 'leads_widget.dart';

// Kanban board, lead cards, badges, drag handles and the lead dialog.
// Part of the leads_widget library so private classes retain their access.

class _KanbanColumn extends StatefulWidget {
  final StatusRecord status;
  final List<Map<String, dynamic>> leads;
  final int totalCount;
  final Function(String, String) onMove;
  final Function(String) onDelete;
  final Function(Map<String, dynamic>) onTap;
  final List<StatusRecord> allStatuses;
  final VoidCallback onRefresh;
  final Set<String> pendingLeadIds;
  final String? nextCursor;
  final bool loadingMore;
  final ValueChanged<String?> onLoadMore;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  // D1/D5: whether a board-wide search query is active, so an empty column
  // shows the right message («ничего не найдено» vs «нет лидов»).
  final bool hasActiveQuery;

  const _KanbanColumn({
    required this.status,
    required this.leads,
    required this.totalCount,
    required this.onMove,
    required this.onDelete,
    required this.onTap,
    required this.allStatuses,
    required this.onRefresh,
    required this.pendingLeadIds,
    required this.nextCursor,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.hasActiveQuery = false,
  });

  @override
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  @override
  Widget build(BuildContext context) {
    final hasMore =
        (widget.nextCursor?.trim().isNotEmpty ?? false) &&
        widget.totalCount > widget.leads.length;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        widget.onDragEnd();
        widget.onMove(details.data, widget.status.$1);
      },
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        // Cap the column to a fraction of the screen so cards are never
        // horizontally clipped on a narrow (mobile) viewport, while keeping a
        // comfortable fixed width on wider (desktop) screens. The 24 subtracts
        // the column's own horizontal margins (6 + 6) plus board padding so a
        // single column still fits fully inside the viewport on small phones.
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
                ? widget.status.$3.withAlpha(30)
                : Theme.of(context).colorScheme.surface.withAlpha(127),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: hovering
                  ? widget.status.$3
                  : widget.status.$3.withAlpha(45),
              width: hovering ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.status.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.status.$2,
                      style: TextStyle(
                        color: widget.status.$3,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(
                          color: widget.status.$3.withAlpha(70),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${widget.totalCount}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: hovering
                    ? Container(
                        height: 40,
                        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: widget.status.$3,
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          color: widget.status.$3.withAlpha(25),
                        ),
                        child: Center(
                          child: Text(
                            'Отпустите, чтобы перенести',
                            style: TextStyle(
                              color: widget.status.$3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: widget.leads.isEmpty && !hasMore
                    ? _buildEmptyColumn(context)
                    : ListView.builder(
                  key: PageStorageKey('leads_col_${widget.status.$1}'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.leads.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= widget.leads.length) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
                        child: OutlinedButton.icon(
                          onPressed: widget.loadingMore
                              ? null
                              : () => widget.onLoadMore(widget.nextCursor),
                          icon: widget.loadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded),
                          label: Text(
                            widget.loadingMore
                                ? 'Загрузка...'
                                : 'Загрузить ещё',
                          ),
                        ),
                      );
                    }
                    final lead = widget.leads[index];
                    final leadId = lead['id']?.toString() ?? '';
                    return _LeadCard(
                      lead: lead,
                      statusColor: widget.status.$3,
                      allStatuses: widget.allStatuses,
                      onMove: widget.onMove,
                      onDelete: widget.onDelete,
                      onTap: () => widget.onTap(lead),
                      onRefresh: widget.onRefresh,
                      isPending: widget.pendingLeadIds.contains(leadId),
                      onDragUpdate: widget.onDragUpdate,
                      onDragEnd: widget.onDragEnd,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// D5: per-column empty state. Distinguishes a search miss («ничего не
  /// найдено») from a genuinely empty column («перетащите карточку сюда»).
  Widget _buildEmptyColumn(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final searching = widget.hasActiveQuery;
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
              searching
                  ? Icons.search_off_rounded
                  : Icons.inbox_outlined,
              size: 28,
              color: cs.onSurfaceVariant.withAlpha(140),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              searching ? 'Ничего не найдено' : 'Нет лидов',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              searching
                  ? 'Измените запрос'
                  : 'Перетащите карточку сюда',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant.withAlpha(160),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Finalizing kanban column structure

class _LeadCard extends ConsumerWidget {
  final Map<String, dynamic> lead;
  final Color statusColor;
  final List<StatusRecord> allStatuses;
  final Function(String, String) onMove;
  final Function(String) onDelete;
  final VoidCallback onTap;
  final VoidCallback onRefresh;
  final bool isPending;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _LeadCard({
    required this.lead,
    required this.statusColor,
    required this.allStatuses,
    required this.onMove,
    required this.onDelete,
    required this.onTap,
    required this.onRefresh,
    required this.isPending,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = lead['id']?.toString() ?? '';
    final firstName = lead['name']?.toString() ?? '';
    final lName = lead['last_name']?.toString() ?? '';
    final name = '$firstName $lName'.trim();
    final displayName = name.isEmpty ? 'Без имени' : name;
    final phone = lead['phone']?.toString() ?? '';
    final source = lead['source']?.toString() ?? '';
    final branchName = lead['branch_name']?.toString() ?? '';
    final assignedName = lead['assigned_name']?.toString() ?? '';
    final linkedStudentId = lead['linked_student_id']?.toString() ?? '';
    final openTasks = _intValue(lead['open_tasks_count']);
    final comments = _intValue(lead['comments_count']);
    final trials = _intValue(lead['trial_lessons_count']);
    final currentStatus = lead['status']?.toString() ?? 'new';
    final dtStr = lead['created_at']?.toString();
    final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
    final dateStr = dt != null ? DateFormat('d MMM', 'ru').format(dt) : '';

    final customData = lead['custom_data'] as Map<String, dynamic>? ?? {};
    final discipline = customData['discipline']?.toString() ?? '';
    final level = customData['level']?.toString() ?? '';

    final transfer = ref.read(leadTransferControllerProvider);
    // True while THIS card is the one carried by the transfer drag — the card
    // stays mounted (so the Draggable survives) but renders as a faded source
    // placeholder.
    final beingTransferred = ref.watch(
      leadTransferControllerProvider.select(
        (c) => c.isActive && c.leadId == id,
      ),
    );

    return LongPressDraggable<String>(
      data: id,
      maxSimultaneousDrags: isPending ? 0 : null,
      // Snappier than the platform 500ms long-press, but still long enough that a
      // normal click (tap → open) doesn't linger past the threshold and silently
      // move the lead (a 180ms delay mis-fired that way). 250ms reads as instant
      // while keeping click vs. deliberate-drag cleanly separated on mouse+touch.
      delay: const Duration(milliseconds: 250),
      hapticFeedbackOnStart: true,
      onDragUpdate: (details) => onDragUpdate(details.globalPosition),
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (_, _) => onDragEnd(),
      onDragCompleted: onDragEnd,
      feedback: Transform.rotate(
        angle: 0.03,
        child: Material(
          color: Colors.transparent,
          child: Builder(
            builder: (context) {
              // Match the dragged card's width to the responsive column inner
              // width so the feedback is not clipped on a narrow screen.
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
              border: Border.all(color: statusColor, width: 2),
              boxShadow: AppShadow.shLift,
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
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
      ),
      // Leave a faded placeholder gap in the source column while dragging.
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(
              color: statusColor.withAlpha(120),
              style: BorderStyle.solid,
            ),
          ),
          child: const SizedBox(height: 64, width: double.infinity),
        ),
      ),
      child: Opacity(
        opacity: beingTransferred ? 0.4 : (isPending ? 0.62 : 1),
        child: AbsorbPointer(
          absorbing: isPending,
          child: GestureDetector(
            onTap: onTap,
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(
                  color: beingTransferred
                      ? AppColor.transferCyan
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: beingTransferred ? 1.4 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (linkedStudentId.isEmpty)
                          _LeadDragHandle(lead: lead, controller: transfer),
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Написать в чат',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: AppColor.gold,
                          ),
                          onPressed: () => _openChat(context, ref),
                        ),
                        PopupMenuButton<String>(
                          icon: isPending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.more_horiz_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  size: 18,
                                ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 150),
                          onSelected: (v) {
                            if (v == 'delete') {
                              onDelete(id);
                            } else if (v == 'comment') {
                              _addComment(context, ref);
                            } else if (v == 'task') {
                              _addTask(context, ref);
                            } else if (v == 'trial') {
                              _scheduleTrial(context, ref);
                            } else if (v == 'convert') {
                              _convertToStudent(context, ref);
                            } else {
                              onMove(id, v);
                            }
                          },
                          itemBuilder: (_) {
                            final currentMatch = allStatuses.where(
                              (s) => s.$1 == currentStatus,
                            );
                            final currentLabel = currentMatch.isEmpty
                                ? currentStatus
                                : currentMatch.first.$2;
                            return [
                              // Show the current status (disabled, checked) so a
                              // status move makes the present state explicit.
                              PopupMenuItem<String>(
                                enabled: false,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: AppColor.success,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text('Сейчас: $currentLabel'),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              ...allStatuses
                                  .where((s) => s.$1 != currentStatus)
                                  .map(
                                    (s) => PopupMenuItem(
                                      value: s.$1,
                                      child: Text('Перевести в: ${s.$2}'),
                                    ),
                                  ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'comment',
                                child: Text('Добавить комментарий'),
                              ),
                              const PopupMenuItem(
                                value: 'task',
                                child: Text('Создать задачу'),
                              ),
                              const PopupMenuItem(
                                value: 'trial',
                                child: Text('Назначить пробный'),
                              ),
                              if (linkedStudentId.isEmpty) ...[
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'convert',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.school_rounded,
                                        size: 18,
                                        color: AppColor.success,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Сделать учеником',
                                        style: TextStyle(
                                          color: AppColor.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Удалить',
                                  style: TextStyle(color: AppColor.danger),
                                ),
                              ),
                            ];
                          },
                        ),
                      ],
                    ),
                    if (phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          phone,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (discipline.isNotEmpty)
                          _InfoBadge(
                            text: discipline,
                            color: AppColor.gold.withAlpha(51),
                            textColor: AppColor.gold,
                          ),
                        if (level.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _InfoBadge(
                              text: level,
                              color: AppTheme.warning.withAlpha(51),
                              textColor: AppTheme.warning,
                            ),
                          ),
                      ],
                    ),
                    if (branchName.isNotEmpty || assignedName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (branchName.isNotEmpty)
                              _IconBadge(
                                icon: Icons.location_on_outlined,
                                text: branchName,
                              ),
                            if (assignedName.isNotEmpty)
                              _IconBadge(
                                icon: Icons.person_pin_circle_outlined,
                                text: assignedName,
                              ),
                          ],
                        ),
                      ),
                    if (openTasks > 0 ||
                        comments > 0 ||
                        trials > 0 ||
                        linkedStudentId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (openTasks > 0)
                              _MetricBadge(
                                icon: Icons.task_alt_rounded,
                                text: '$openTasks',
                              ),
                            if (comments > 0)
                              _MetricBadge(
                                icon: Icons.chat_bubble_outline_rounded,
                                text: '$comments',
                              ),
                            if (trials > 0)
                              _MetricBadge(
                                icon: Icons.event_available_rounded,
                                text: '$trials',
                              ),
                            if (linkedStudentId.isNotEmpty)
                              const _MetricBadge(
                                icon: Icons.link_rounded,
                                text: 'ученик',
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (source.isNotEmpty)
                          Text(
                            source,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _addComment(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Комментарий к лиду'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Текст...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (content != null && content.trim().isNotEmpty) {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: 'lead',
            entityId: lead['id'],
            body: content.trim(),
          );
      onRefresh();
    }
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Задача по лиду'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Что сделать?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (title != null && title.trim().isNotEmpty) {
      await ref
          .read(magicCrmServiceProvider)
          .createTask(
            entityType: 'lead',
            entityId: lead['id'],
            title: title.trim(),
          );
      onRefresh();
    }
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final leadId = lead['id']?.toString();
    if (leadId == null || leadId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .resolveLeadChatUser(leadId);
      final userId = result['userId']?.toString();
      if (userId == null || userId.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'У этого лида пока нет связанного пользователя для чата. '
              'Свяжите его по телефону в разделе «Пользователи».',
            ),
          ),
        );
        return;
      }
      // The leads board lives inside the messenger shell — setting the
      // navigation target makes the shell open/create the direct chat and
      // switch to the chat tab.
      ref
          .read(messengerNavigationProvider.notifier)
          .navigateTo(MessengerNavigationState(partnerId: userId));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось открыть чат: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }

  Future<void> _convertToStudent(BuildContext context, WidgetRef ref) async {
    if ((lead['linked_student_id']?.toString() ?? '').isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лид уже связан с учеником')),
      );
      return;
    }
    final student = await ConvertLeadDialog.show(context, lead: lead);
    if (student == null) return; // cancelled / failed in-dialog
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Лид конвертирован в ученика'),
          backgroundColor: AppColor.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    onRefresh();
  }

  Future<void> _scheduleTrial(BuildContext context, WidgetRef ref) async {
    final crm = ref.read(magicCrmServiceProvider);
    final [teachersRes, roomsRes] = await Future.wait([
      crm.listTeachers(limit: 100),
      crm.listRooms(limit: 100),
    ]);

    final teachers = List<Map<String, dynamic>>.from(teachersRes);
    final rooms = List<Map<String, dynamic>>.from(roomsRes);

    if (!context.mounted) return;
    if (teachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступных преподавателей')),
      );
      return;
    }

    String? selectedTeacher = teachers.isNotEmpty ? teachers.first['id'] : null;
    String? selectedRoom = rooms.isNotEmpty ? rooms.first['id'] : null;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Пробное занятие'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedTeacher,
                decoration: const InputDecoration(labelText: 'Учитель'),
                items: teachers
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'].toString(),
                        child: Text('${t['first_name']} ${t['last_name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocalState(() => selectedTeacher = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRoom,
                decoration: const InputDecoration(labelText: 'Кабинет'),
                items: rooms
                    .map(
                      (r) => DropdownMenuItem(
                        value: r['id'].toString(),
                        child: Text(r['name']),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocalState(() => selectedRoom = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(
                  'Дата: ${DateFormat('dd.MM.yyyy').format(selectedDate)}',
                ),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) {
                    setLocalState(() => selectedDate = picked);
                  }
                },
              ),
              ListTile(
                title: Text('Время: ${selectedTime.format(ctx)}'),
                trailing: const Icon(Icons.access_time_rounded),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: selectedTime,
                  );
                  if (picked != null) {
                    setLocalState(() => selectedTime = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Назначить'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedTeacher != null) {
      final scheduledAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );

      await crm.createLesson(
        leadId: lead['id'],
        teacherId: selectedTeacher,
        roomId: selectedRoom,
        scheduledAt: scheduledAt.toIso8601String(),
        isTrial: true,
        status: 'scheduled',
        notes: 'Пробное занятие по лиду: ${lead['name'] ?? ''}',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пробное занятие назначено')),
        );
      }
      onRefresh();
    }
  }
}

/// Visible drag affordance that starts the Лид → Ученик transfer flow.
///
/// A plain [Draggable] (immediate, movement-threshold) so a normal desktop
/// mouse drag works without a long press — and crucially its `feedback` ghost is
/// pointer-routed, so the card stays "in hand" even after the host switches the
/// segment to Ученики mid-drag. The hover/timer/branch/column logic all run in
/// [LeadTransferController] fed by `onDragUpdate`.
class _LeadDragHandle extends StatelessWidget {
  final Map<String, dynamic> lead;
  final LeadTransferController controller;

  const _LeadDragHandle({required this.lead, required this.controller});

  @override
  Widget build(BuildContext context) {
    final id = lead['id']?.toString() ?? '';
    return Draggable<String>(
      data: id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => controller.startFromLead(lead),
      onDragUpdate: (d) => controller.updatePointer(d.globalPosition),
      // No DragTarget is used, so both callbacks fire — endDrag is idempotent.
      onDragEnd: (_) => controller.endDrag(),
      onDraggableCanceled: (_, _) => controller.endDrag(),
      feedback: TransferGhostCard(controller: controller, lead: lead),
      childWhenDragging: const _HandleIcon(faded: true),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Перетащите в «Ученики»',
          child: const _HandleIcon(),
        ),
      ),
    );
  }
}

class _HandleIcon extends StatelessWidget {
  final bool faded;
  const _HandleIcon({this.faded = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 32,
      child: Icon(
        Icons.drag_indicator_rounded,
        size: 18,
        color: AppColor.transferCyan.withValues(alpha: faded ? 0.3 : 0.9),
      ),
    );
  }
}

/// Toolbar trigger that opens the secondary-filter drawer, with a gold count
/// badge when one or more drawer filters are active.
class _FiltersButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;

  const _FiltersButton({required this.activeCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final hasActive = activeCount > 0;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: hasActive
          ? OutlinedButton.styleFrom(
              foregroundColor: AppColor.gold,
              side: const BorderSide(color: AppColor.goldLine),
            )
          : null,
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Фильтры'),
          if (hasActive) ...[
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColor.gold,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$activeCount',
                style: const TextStyle(
                  color: AppColor.onGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _InfoBadge({
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

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
        color: AppColor.gold.withAlpha(36),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColor.gold),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppColor.gold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadDialog extends StatefulWidget {
  const _LeadDialog();

  @override
  State<_LeadDialog> createState() => _LeadDialogState();
}

class _LeadDialogState extends State<_LeadDialog> {
  final _nameCtrl = TextEditingController();
  String _canonicalPhone = '';
  final _sourceCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Новый лид'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 10),
          RuPhoneField(
            onCanonicalChanged: (c) => _canonicalPhone = c,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sourceCtrl,
            decoration: const InputDecoration(
              labelText: 'Источник (ВКонтакте, сайт...)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'name': _nameCtrl.text.trim(),
                'phone': _canonicalPhone,
                'source': _sourceCtrl.text.trim(),
              });
            }
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
