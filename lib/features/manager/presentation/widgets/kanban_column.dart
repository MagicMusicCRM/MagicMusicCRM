part of 'leads_widget.dart';

// Kanban board column with drag-target and lead ordering.

class _KanbanColumn extends StatefulWidget {
  final StatusRecord status;
  final List<Map<String, dynamic>> leads;
  final int totalCount;
  final Function(String, String) onMove;
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
  String? _requestedCursor;

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
            color: hovering ? widget.status.$3.withAlpha(30) : AppColor.bg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: hovering ? widget.status.$3 : AppColor.divider,
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
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
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
                    : MagicDesktopScrollbar(
                        axis: Axis.vertical,
                        builder: (context, controller) => ListView.builder(
                          controller: controller,
                          key: PageStorageKey('leads_col_${widget.status.$1}'),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: widget.leads.length + (hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= widget.leads.length) {
                              final cursor = widget.nextCursor!;
                              if (!widget.loadingMore &&
                                  _requestedCursor != cursor) {
                                _requestedCursor = cursor;
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) widget.onLoadMore(cursor);
                                });
                              }
                              return const Padding(
                                padding: EdgeInsets.fromLTRB(0, 10, 0, 14),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
                            final lead = widget.leads[index];
                            final leadId = lead['id']?.toString() ?? '';
                            return _LeadCard(
                              lead: Lead.fromMap(lead),
                              statusColor: widget.status.$3,
                              allStatuses: widget.allStatuses,
                              onMove: widget.onMove,
                              onTap: () => widget.onTap(lead),
                              onRefresh: widget.onRefresh,
                              isPending: widget.pendingLeadIds.contains(leadId),
                              onDragUpdate: widget.onDragUpdate,
                              onDragEnd: widget.onDragEnd,
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
              searching ? Icons.search_off_rounded : Icons.inbox_outlined,
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
              searching ? 'Измените запрос' : 'Перетащите карточку сюда',
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
