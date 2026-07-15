part of 'client_card.dart';

// Standalone presentation widgets for the client card. Kept in the same
// library (part) so they retain private access without widening the API.

class _CommentsList extends ConsumerStatefulWidget {
  /// One ref per half whose comments should be shown. A single-side card passes
  /// one ref; a converted client passes both ('lead', …) and ('student', …).
  final List<ClientHalfRef> refs;

  /// When true (converted), each comment gets a «Лид»/«Ученик» origin chip.
  final bool showOrigin;
  final int refreshKey;
  const _CommentsList({
    required this.refs,
    required this.showOrigin,
    required this.refreshKey,
  });

  @override
  ConsumerState<_CommentsList> createState() => _CommentsListState();
}

class _CommentsListState extends ConsumerState<_CommentsList> {
  // The comments future is held in a field (not recreated in build()) so the
  // list doesn't re-fetch on every parent rebuild — the card rebuilds often on
  // realtime events. Recomputed only when refs/refreshKey change or on retry.
  late Future<List<Comment>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadMerged();
  }

  @override
  void didUpdateWidget(covariant _CommentsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey ||
        _refsSig(oldWidget.refs) != _refsSig(widget.refs)) {
      _future = _loadMerged();
    }
  }

  String _refsSig(List<ClientHalfRef> refs) =>
      refs.map((r) => '${r.entityType}/${r.entityId}').join(',');

  // Maps a comment `kind` to a short Russian badge label. Unknown / generic
  // kinds (e.g. plain staff comments) get no badge.
  String? _kindLabel(Object? kind) {
    return switch (kind?.toString()) {
      'admin_comment' => 'Админ',
      'teacher_note' => 'Педагог',
      'progress' => 'Прогресс',
      _ => null,
    };
  }

  Widget _kindBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColor.gold,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }

  // Loads every ref's comments in PARALLEL, isolates per-ref failures (a failed
  // half contributes no rows but never fails the whole list), tags each comment
  // with its origin entityType (`_origin`), merges, de-dups by id and sorts by
  // created_at desc.
  Future<List<Comment>> _loadMerged() async {
    final crm = ref.read(magicCrmServiceProvider);
    final results = await Future.wait(
      widget.refs.map((r) async {
        try {
          final rows = await crm.listComments(
            entityType: r.entityType,
            entityId: r.entityId,
          );
          return rows.map((c) => {...c, '_origin': r.entityType}).toList();
        } catch (_) {
          return <Map<String, dynamic>>[];
        }
      }),
    );
    return mergeByIdSorted(
      results,
      dateKey: 'created_at',
    ).map(Comment.fromMap).toList();
  }

  bool get _isStaff {
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    return role == 'admin' ||
        role == 'manager' ||
        role == 'director' ||
        role == 'system_admin';
  }

  // Flip a comment between admin-only (`admin_comment`) and teacher-visible
  // (`teacher_note`). Default is admin-only; this is the «показать преподавателю»
  // toggle from the client card.
  Future<void> _toggleCommentVisibility(Map<String, dynamic> c) async {
    final id = c['id']?.toString();
    if (id == null) return;
    final showToTeacher = c['kind'] != 'teacher_note';
    try {
      await ref
          .read(magicCrmServiceProvider)
          .setCommentVisibility(commentId: id, visibleToTeacher: showToTeacher);
      if (mounted) setState(() => _future = _loadMerged());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось изменить видимость: $e')),
        );
      }
    }
  }

  Widget _visibilityToggle(Map<String, dynamic> c) {
    final visible = c['kind'] == 'teacher_note';
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _toggleCommentVisibility(c),
        style: TextButton.styleFrom(
          foregroundColor: visible
              ? AppColor.gold
              : Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(
          visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          size: 14,
        ),
        label: Text(
          visible ? 'Виден преподавателю' : 'Показать преподавателю',
          style: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Comment>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: LinearProgressIndicator(color: AppColor.gold),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Не удалось загрузить комментарии',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: AppSpace.xs),
                TextButton.icon(
                  onPressed: () => setState(() => _future = _loadMerged()),
                  style: TextButton.styleFrom(foregroundColor: AppColor.gold),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) return const SizedBox.shrink();
        final comments = snapshot.data!;
        if (comments.isEmpty) {
          return Text(
            'Нет комментариев',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          );
        }

        return Column(
          children: comments.map((c) {
            final dt = DateTime.tryParse(c.createdAt ?? '')?.toLocal();
            final dateStr = dt != null
                ? DateFormat('d MMM HH:mm', 'ru').format(dt)
                : '';
            final kindLabel = _kindLabel(c.kind);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSpace.sm),
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.authorName.trim().isNotEmpty
                                    ? c.authorName
                                    : 'Сотрудник',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColor.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (kindLabel != null) ...[
                              const SizedBox(width: 6),
                              _kindBadge(kindLabel),
                            ],
                            if (widget.showOrigin && c.origin != null) ...[
                              const SizedBox(width: 6),
                              ClientOriginChip(entityType: c.origin!),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(c.content ?? '', style: const TextStyle(fontSize: 13)),
                  if (_isStaff &&
                      (c.kind == 'admin_comment' ||
                          c.kind == 'teacher_note')) ...[
                    const SizedBox(height: 2),
                    _visibilityToggle(c.raw),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// One labelled info row for compact read-only card sections.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
