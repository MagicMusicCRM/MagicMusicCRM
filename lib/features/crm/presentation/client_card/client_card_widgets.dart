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
  late Future<List<Map<String, dynamic>>> _future;

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
  Future<List<Map<String, dynamic>>> _loadMerged() async {
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
    return mergeByIdSorted(results, dateKey: 'created_at');
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
      await ref.read(magicCrmServiceProvider).setCommentVisibility(
            commentId: id,
            visibleToTeacher: showToTeacher,
          );
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
          visible
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
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
    return FutureBuilder<List<Map<String, dynamic>>>(
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
            final dt = DateTime.tryParse(c['created_at'] ?? '')?.toLocal();
            final dateStr = dt != null
                ? DateFormat('d MMM HH:mm', 'ru').format(dt)
                : '';
            final kindLabel = _kindLabel(c['kind']);
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
                                (c['author_name']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ??
                                        false)
                                    ? c['author_name'].toString()
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
                            if (widget.showOrigin && c['_origin'] != null) ...[
                              const SizedBox(width: 6),
                              ClientOriginChip(
                                entityType: c['_origin'].toString(),
                              ),
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
                  Text(
                    c['content'] ?? '',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (_isStaff &&
                      (c['kind'] == 'admin_comment' ||
                          c['kind'] == 'teacher_note')) ...[
                    const SizedBox(height: 2),
                    _visibilityToggle(c),
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

// ── Pure display helpers ─────────────────────────────────────────────────────
// Stateless factories/formatters peeled off _ClientCardState. Top-level (still
// in this library via `part`, so the leading underscore keeps them file-local
// to the client-card sources) — the State class calls them unchanged.

/// Shared card container used by the student Инфо/Документы tabs.
Widget _buildInfoCard(String title, List<Widget> children) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppTheme.primaryGold,
            ),
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    ),
  );
}

Widget _sectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.md, top: AppSpace.xs),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AppColor.gold,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Text(
          title,
          style: const TextStyle(
            color: AppColor.gold,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );
}

/// Lead status-change history list (read-only).
Widget _statusHistorySection(
  ColorScheme cs, {
  required bool loading,
  required List<Map<String, dynamic>> history,
}) {
  if (loading) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: LinearProgressIndicator(color: AppColor.gold),
    );
  }
  if (history.isEmpty) {
    return Text(
      'Изменений статуса пока нет',
      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: history.take(12).map((h) {
      final from = h['old_status']?.toString();
      final to = h['new_status']?.toString();
      final transition = [
        if (from != null && from.isNotEmpty) from else '—',
        '→',
        if (to != null && to.isNotEmpty) to else '—',
      ].join(' ');
      final comment = h['comment']?.toString().trim() ?? '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          leading: const Icon(
            Icons.history_rounded,
            size: 18,
            color: AppColor.gold,
          ),
          title: Text(transition, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              _formatDate(h['changed_at']),
              if (comment.isNotEmpty) comment,
            ].where((value) => value.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }).toList(),
  );
}

Widget _emptyHint(ColorScheme cs, String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
    child: Text(
      text,
      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
    ),
  );
}

Widget _headerBadge(String label) {
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
        fontSize: 10.5,
      ),
    ),
  );
}

Widget _summaryChip(IconData icon, String label, int value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColor.goldSoft,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      border: Border.all(color: AppColor.goldLine),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColor.gold),
        const SizedBox(width: 6),
        Text(
          '$label: $value',
          style: const TextStyle(
            color: AppColor.gold,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

Widget _entityTile(
  ColorScheme cs, {
  required String title,
  String? subtitle,
  required IconData leading,
  String? origin,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      leading: Icon(leading, size: 18, color: AppColor.gold),
      title: Text(
        title.isEmpty ? 'Без названия' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle == null || subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: origin == null ? null : ClientOriginChip(entityType: origin),
    ),
  );
}

Widget _miniSection(
  ColorScheme cs, {
  required String title,
  required String empty,
  required List<Map<String, dynamic>> rows,
  required String Function(Map<String, dynamic>) titleBuilder,
  required String? Function(Map<String, dynamic>) subtitleBuilder,
  Widget? action,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: AppSpace.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          Text(
            empty,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          )
        else
          ...rows.take(4).map((row) {
            final subtitle = subtitleBuilder(row);
            final titleText = titleBuilder(row);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  side: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                title: Text(
                  titleText.isEmpty ? 'Без названия' : titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitle == null || subtitle.isEmpty
                    ? null
                    : Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            );
          }),
      ],
    ),
  );
}

String _subscriptionRemainder(Map<String, dynamic> s) {
  num toNum(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  String hours(num v) =>
      v == v.truncate() ? v.toInt().toString() : v.toStringAsFixed(1);
  final total = toNum(s['lessons_total']);
  final left = total - toNum(s['lessons_used']);
  final price = s['package_price'];
  final money = (price is num && total > 0)
      ? ' / ${(price / total * left).round()} ₽'
      : '';
  final status = s['status']?.toString();
  final suffix = status == 'active' ? '' : ' · ${_formatStatus(status)}';
  return 'Остаток: ${hours(left)} из ${hours(total)} астр.ч.$money$suffix';
}

String _ledgerKindLabel(Object? kind) {
  return switch (kind?.toString()) {
    'payment' => 'Платёж',
    'lesson_charge' => 'Списание за занятие',
    'refund' => 'Возврат',
    'adjustment' => 'Корректировка',
    'transfer_in' => 'Перенос (зачисление)',
    'transfer_out' => 'Перенос (списание)',
    _ => 'Операция',
  };
}

String _familyRoleLabel(Object? role) {
  return switch (role?.toString()) {
    'parent' => 'Родитель',
    'child' => 'Ребёнок',
    'guardian' => 'Опекун',
    'payer' => 'Плательщик',
    'sibling' => 'Брат/сестра',
    final value when value != null && value.isNotEmpty => value,
    _ => 'Член семьи',
  };
}

String _formatStatus(Object? status) {
  return switch (status?.toString()) {
    'open' => 'Открыта',
    'in_progress' => 'В работе',
    'done' => 'Выполнена',
    'cancelled' => 'Отменена',
    final value when value != null && value.isNotEmpty => value,
    _ => '',
  };
}

String _formatDate(Object? raw) {
  final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (dt == null) return '';
  return DateFormat('dd.MM.yyyy HH:mm', 'ru').format(dt);
}

