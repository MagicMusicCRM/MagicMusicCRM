part of 'leads_widget.dart';

// Lead card: contact, status, tasks, quick actions, drag payload.

class _LeadCard extends ConsumerWidget {
  final Lead lead;
  final Color statusColor;
  final List<StatusRecord> allStatuses;
  final Function(String, String, int) onMove;
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
    final linkedUserId = lead.linkedUserId;
    final openTasks = lead.openTasksCount;
    final forgotten = hasNoOpenTasks(openTasks);
    final comments = lead.commentsCount;
    final trials = lead.trialLessonsCount;
    final currentStatus = lead.status;
    final dtStr = lead.createdAt;
    final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
    final dateStr = dt != null ? DateFormat('d MMM', 'ru').format(dt) : '';

    final discipline = lead.discipline;
    final level = lead.level;
    final tableFields = lead.tableCustomFields;

    // True while THIS card is the one carried by the transfer drag — the card
    // stays mounted (so the Draggable survives) but renders as a faded source
    // placeholder.
    final beingTransferred = ref.watch(
      leadTransferControllerProvider.select(
        (c) => c.isActive && c.leadId == id,
      ),
    );

    final Widget feedback = Transform.rotate(
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
                            color: AppColor.text,
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
    // Leave a faded placeholder gap in the source column while dragging.
    final Widget childWhenDragging = Opacity(
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
    );
    final Widget cardChild = Opacity(
      opacity: beingTransferred ? 0.4 : (isPending ? 0.62 : 1),
      child: AbsorbPointer(
        absorbing: isPending,
        child: GestureDetector(
          onTap: onTap,
          child: Card(
            margin: const EdgeInsets.only(bottom: 10),
            // Жёлтым — лид, по которому не висит ни одной задачи: про него
            // забыли, следующего шага никто не запланировал (требование
            // заказчика 17.07). Правило и цвет — в no_open_tasks_highlight.
            color: forgotten
                ? noOpenTasksSurface(context)
                : Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              // Перенос важнее «забыт»: он про то, что происходит ПРЯМО
              // СЕЙЧАС, и перебивать его подсказкой нельзя.
              side: beingTransferred
                  ? const BorderSide(color: AppColor.transferCyan, width: 1.4)
                  : forgotten
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
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
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: AppColor.gold,
                          ),
                          onPressed: () => _openChat(ref),
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
                          if (v == 'comment') {
                            _addComment(context, ref);
                          } else if (v == 'task') {
                            _addTask(context, ref);
                          } else if (v == 'schedule') {
                            _openInSchedule(ref);
                          } else if (v == 'subscription') {
                            onTap();
                          } else {
                            onMove(id, v, lead.version);
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
                              value: 'schedule',
                              child: Text('Открыть в расписании'),
                            ),
                            if (linkedStudentId.isEmpty) ...[
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'subscription',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.card_membership_rounded,
                                      size: 18,
                                      color: AppColor.success,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Продать абонемент',
                                      style: TextStyle(
                                        color: AppColor.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  if (tableFields.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final field in tableFields)
                            KeyedSubtree(
                              key: ValueKey('lead-table-field-${field['key']}'),
                              child: _InfoBadge(
                                text: clientTableFieldText(field),
                                color: AppColor.gold.withAlpha(32),
                                textColor: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      return Draggable<({String id, int version})>(
        data: (id: id, version: lead.version),
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
    return LongPressDraggable<({String id, int version})>(
      data: (id: id, version: lead.version),
      maxSimultaneousDrags: isPending ? 0 : null,
      // Snappier than the platform 500ms long-press, but still long enough that a
      // normal tap (tap → open) doesn't linger past the threshold and silently
      // move the lead (a 180ms delay mis-fired that way). 250ms reads as instant
      // while keeping tap vs. deliberate-drag cleanly separated on touch.
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

  Future<void> _addComment(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // On a failed save the dialog reopens with the typed text preserved.
    var draft = '';
    while (true) {
      if (!context.mounted) return;
      final controller = TextEditingController(text: draft);
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
      if (content == null || content.trim().isEmpty) return;
      try {
        await ref
            .read(magicCrmServiceProvider)
            .createComment(
              entityType: 'lead',
              entityId: lead.id,
              body: content.trim(),
            );
        onRefresh();
        return;
      } catch (e) {
        draft = content;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(
                e,
                fallback: 'Не удалось сохранить комментарий.',
              ),
            ),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    }
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    await showCreateSharedTask(
      context,
      ref,
      linkedEntity: EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: lead.id,
        variant: 'lead',
        presentation: EntityPresentationReference(
          primary: [
            lead.lastName,
            lead.name,
          ].where((value) => value.trim().isNotEmpty).join(' '),
        ),
      ),
      onSaved: onRefresh,
    );
  }

  void _openChat(WidgetRef ref) {
    final userId = lead.linkedUserId;
    if (userId.isEmpty) return;
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(CrmNavigationRequest.directChat(userId));
  }

  void _openInSchedule(WidgetRef ref) {
    ref
        .read(scheduleNavigationProvider.notifier)
        .createForLead(DateTime.now(), leadId: lead.id, leadName: lead.name);
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(
          CrmNavigationRequest.schedule(date: DateTime.now(), leadId: lead.id),
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
