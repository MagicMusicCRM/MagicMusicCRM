part of 'leads_widget.dart';

// Lead card: contact, status, tasks, quick actions, drag payload.

class _LeadCard extends ConsumerWidget {
  final Lead lead;
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
    final id = lead.id;
    final firstName = lead.name;
    final lName = lead.lastName;
    final name = '$firstName $lName'.trim();
    final displayName = name.isEmpty ? 'Без имени' : name;
    final phone = lead.phone;
    final source = lead.source;
    final branchName = lead.branchName;
    final assignedName = lead.assignedName;
    final linkedStudentId = lead.linkedStudentId;
    final openTasks = lead.openTasksCount;
    final comments = lead.commentsCount;
    final trials = lead.trialLessonsCount;
    final currentStatus = lead.status;
    final dtStr = lead.createdAt;
    final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
    final dateStr = dt != null ? DateFormat('d MMM', 'ru').format(dt) : '';

    final discipline = lead.discipline;
    final level = lead.level;

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
            entityId: lead.id,
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
            entityId: lead.id,
            title: title.trim(),
          );
      onRefresh();
    }
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final leadId = lead.id;
    if (leadId.isEmpty) return;
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
    if (lead.linkedStudentId.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лид уже связан с учеником')),
      );
      return;
    }
    final student = await ConvertLeadDialog.show(context, lead: lead.raw);
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
    await bookTrialLesson(
      context,
      ref,
      leadId: lead.id,
      leadName: lead.name,
      feedback: (message, {detail, ok = false}) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message))),
      onBooked: () async => onRefresh(),
    );
  }
}

/// Visible drag affordance that starts the Лид → Ученик transfer flow.
///
/// A plain [Draggable] (immediate, movement-threshold) so a normal desktop
/// mouse drag works without a long press — and crucially its `feedback` ghost is
/// pointer-routed, so the card stays "in hand" even after the host switches the
/// segment to Ученики mid-drag. The hover/timer/branch/column logic all run in
/// [LeadTransferController] fed by `onDragUpdate`.
