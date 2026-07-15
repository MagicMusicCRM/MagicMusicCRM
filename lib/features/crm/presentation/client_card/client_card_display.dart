part of 'client_card.dart';

// Stateless display helpers peeled off _ClientCardState (factories, formatters
// and read-only sections). Top-level and library-private via `part`, so the State
// class calls them unchanged. Split out of client_card_widgets.dart to keep each
// source under the ~800-line bar.


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

/// One student-lessons-tab row. [onOpenSchedule] jumps to the dashboard
/// schedule focused on this lesson (only wired when it has a date + id).
Widget _lessonRow(
  ColorScheme cs,
  Map<String, dynamic> l, {
  required void Function(DateTime scheduledAt, String lessonId) onOpenSchedule,
}) {
  final dt = DateTime.tryParse(l['scheduled_at']?.toString() ?? '');
  final dateStr = dt != null
      ? DateFormat('d MMM, HH:mm', 'ru').format(dt)
      : '—';
  final teacherData = l['teachers'] as Map<String, dynamic>?;
  String teacherName = '—';
  if (teacherData != null) {
    final tfName = teacherData['first_name']?.toString() ?? '';
    final tlName = teacherData['last_name']?.toString() ?? '';
    final p = teacherData['profiles'] as Map<String, dynamic>?;
    var tName = '$tfName $tlName'.trim();
    if (tName.isEmpty && p != null) {
      tName = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    teacherName = tName.isEmpty ? '—' : tName;
  }
  final completed = l['status'] == 'completed';
  final lessonId = l['id']?.toString();
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: (lessonId != null && lessonId.isNotEmpty && dt != null)
          ? () => onOpenSchedule(dt, lessonId)
          : null,
      title: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          'Преп.: $teacherName',
          '${l['groups']?['name'] ?? 'Инд.'}',
          if ((l['rooms']?['name']?.toString() ?? '').isNotEmpty)
            'Ауд.: ${l['rooms']['name']}',
        ].join(' • '),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (completed ? AppTheme.success : AppTheme.primaryGold).withAlpha(
            30,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          completed ? 'Завершено' : 'Запланировано',
          style: TextStyle(
            fontSize: 11,
            color: completed ? AppTheme.success : AppTheme.primaryGold,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

/// Student «Прогресс» tab: renders the `[PROGRESS]`-prefixed comments as cards.
Widget _progressNotesView(
  ColorScheme cs, {
  required List<Map<String, dynamic>> comments,
}) {
  final progressNotes = comments
      .where((c) => c['content']?.toString().startsWith('[PROGRESS]') ?? false)
      .toList();
  if (progressNotes.isEmpty) {
    return Center(
      child: Text(
        'Заметок об успехах ещё нет',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
  }
  return ListView.builder(
    padding: const EdgeInsets.all(AppSpace.xl),
    itemCount: progressNotes.length,
    itemBuilder: (ctx, i) {
      final note = progressNotes[i];
      final content = (note['content']?.toString() ?? '').replaceFirst(
        '[PROGRESS] ',
        '',
      );
      final dt = DateTime.tryParse(note['created_at']?.toString() ?? '');
      final dateStr = dt != null
          ? DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal())
          : '—';
      final author = note['profiles'];
      final authorName = author != null
          ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'.trim()
          : 'Система';
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.stars_rounded,
                    color: AppTheme.success,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    authorName.isEmpty ? 'Система' : authorName,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(content, style: const TextStyle(fontSize: 15, height: 1.4)),
            ],
          ),
        ),
      );
    },
  );
}

/// Plain-student history timeline: own tasks + non-progress comments, merged
/// and sorted desc. (Converted clients use [_mergedHistoryView] instead.)
Widget _studentTimelineView(
  ColorScheme cs, {
  required List<Map<String, dynamic>> tasks,
  required List<Map<String, dynamic>> comments,
}) {
  if (tasks.isEmpty && comments.isEmpty) {
    return Center(
      child: Text('История пуста', style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }
  final items = [
    ...tasks.map((t) => {'type': 'task', 'data': t, 'date': t['created_at']}),
    ...comments
        .where(
          (c) => !(c['content']?.toString().startsWith('[PROGRESS]') ?? false),
        )
        .map((c) => {'type': 'comment', 'data': c, 'date': c['created_at']}),
  ];
  items.sort(
    (a, b) =>
        ((b['date'] as String?) ?? '').compareTo((a['date'] as String?) ?? ''),
  );
  return ListView.builder(
    padding: const EdgeInsets.all(AppSpace.xl),
    itemCount: items.length,
    itemBuilder: (ctx, i) {
      final item = items[i];
      final isTask = item['type'] == 'task';
      final data = item['data'] as Map<String, dynamic>;
      final dt = DateTime.tryParse(item['date'] as String? ?? '');
      final dateStr = dt != null
          ? DateFormat('d MMM HH:mm', 'ru').format(dt.toLocal())
          : '—';
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isTask ? Icons.task_alt_rounded : Icons.comment_rounded,
                        size: 16,
                        color: isTask
                            ? AppTheme.warning
                            : AppTheme.primaryGold,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isTask ? 'Задача' : 'Комментарий',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isTask
                              ? AppTheme.warning
                              : AppTheme.primaryGold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isTask
                    ? (data['title']?.toString() ?? '')
                    : (data['content']?.toString() ?? ''),
                style: const TextStyle(fontSize: 14),
              ),
              if (isTask && data['description'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  data['description'].toString(),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Merged-history list (converted): lead status history + student timeline,
/// pre-sorted desc by the caller, each row carrying an origin chip.
Widget _mergedHistoryView(
  ColorScheme cs, {
  required bool loading,
  required List<Map<String, dynamic>> items,
}) {
  // Lead status history loads independently; show a spinner until it settles
  // so converted history isn't briefly missing its lead half.
  if (loading) {
    return const Center(child: CircularProgressIndicator(color: AppColor.gold));
  }
  if (items.isEmpty) {
    return Center(
      child: Text('История пуста', style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }
  return ListView.builder(
    padding: const EdgeInsets.all(AppSpace.xl),
    itemCount: items.length,
    itemBuilder: (ctx, i) {
      final item = items[i];
      final isStatus = item['_kind'] == 'status';
      final dt = DateTime.tryParse(item['_date']?.toString() ?? '');
      final dateStr = dt != null
          ? DateFormat('d MMM HH:mm', 'ru').format(dt.toLocal())
          : '—';
      final subtitle = item['_subtitle']?.toString() ?? '';
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isStatus ? Icons.flag_rounded : Icons.timeline_rounded,
                        size: 16,
                        color: isStatus
                            ? AppTheme.warning
                            : AppTheme.primaryGold,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isStatus ? 'Статус' : 'Событие',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isStatus
                              ? AppTheme.warning
                              : AppTheme.primaryGold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ClientOriginChip(
                        entityType: item['_origin']?.toString() ?? 'student',
                      ),
                    ],
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item['_title']?.toString() ?? '',
                style: const TextStyle(fontSize: 14),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      );
    },
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

