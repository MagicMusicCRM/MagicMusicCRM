part of 'leads_widget.dart';

// Drag handle and its icon for reordering lead cards.

class _LeadDragHandle extends StatelessWidget {
  final Lead lead;
  final LeadTransferController controller;

  const _LeadDragHandle({required this.lead, required this.controller});

  @override
  Widget build(BuildContext context) {
    final id = lead.id;
    return Draggable<String>(
      data: id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => controller.startFromLead(lead.raw),
      onDragUpdate: (d) => controller.updatePointer(d.globalPosition),
      // No DragTarget is used, so both callbacks fire — endDrag is idempotent.
      onDragEnd: (_) => controller.endDrag(),
      onDraggableCanceled: (_, _) => controller.endDrag(),
      feedback: TransferGhostCard(controller: controller, lead: lead.raw),
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
