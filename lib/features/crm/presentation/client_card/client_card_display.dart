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

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.whereType<Map<String, dynamic>>().toList();
}

num _asNum(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

/// Lead «активность» aggregate: summary chips + linked-students/tasks/trials/
/// applications/timeline mini-sections. [onScheduleTrial] wires the «На пробный»
/// action (null hides it for a student-only card).
Widget _aggregateCard(
  ColorScheme cs, {
  required bool loadingCard,
  required Map<String, dynamic>? card,
  required List<Map<String, dynamic>> leadApplications,
  required int duplicateCount,
  required bool loadingDuplicates,
  required bool includeTasks,
  required VoidCallback? onScheduleTrial,
}) {
  if (loadingCard) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: LinearProgressIndicator(color: AppColor.gold),
    );
  }
  if (card == null) {
    return Text(
      'Карточка активности временно недоступна',
      style: TextStyle(color: cs.onSurfaceVariant),
    );
  }

  final linkedStudents = _list(card['linked_students']);
  final tasks = _list(card['tasks']);
  final trials = _list(card['trials']);
  final otherLeads = _list(card['other_leads']);
  final timeline = _list(card['timeline']);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          _summaryChip(Icons.school_outlined, 'Ученики', linkedStudents.length),
          _summaryChip(Icons.task_alt_rounded, 'Задачи', tasks.length),
          _summaryChip(Icons.event_available_rounded, 'Пробные', trials.length),
          _summaryChip(Icons.link_rounded, 'Похожие лиды', otherLeads.length),
          if (loadingDuplicates || duplicateCount > 0)
            _summaryChip(Icons.merge_type_rounded, 'Кандидаты', duplicateCount),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      _miniSection(
        cs,
        title: 'Связанные ученики',
        empty: 'Связанных учеников нет',
        rows: linkedStudents,
        titleBuilder: (row) =>
            '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim(),
        subtitleBuilder: (row) => row['phone']?.toString(),
      ),
      if (includeTasks)
        _miniSection(
          cs,
          title: 'Задачи',
          empty: 'Открытых задач нет',
          rows: tasks,
          titleBuilder: (row) => row['title']?.toString() ?? 'Задача',
          subtitleBuilder: (row) => _formatStatus(row['status']),
        ),
      _miniSection(
        cs,
        title: 'Пробные занятия',
        empty: 'Пробные занятия не назначены',
        rows: trials,
        titleBuilder: (row) => _formatDate(row['scheduled_at']),
        subtitleBuilder: (row) => [
          row['teacher_name'],
          row['room_name'],
        ].where((value) => value != null && '$value'.isNotEmpty).join(' · '),
        action: onScheduleTrial != null
            ? TextButton.icon(
                onPressed: onScheduleTrial,
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.gold,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('На пробный'),
              )
            : null,
      ),
      // KVA-234: заявки лида (HolliHop GetStudyRequests) — порядок секций по
      // HolliHop: Связанные ученики → Пробные занятия → Заявки → Лента.
      _miniSection(
        cs,
        title: 'Заявки',
        empty: 'Заявок нет',
        rows: leadApplications,
        titleBuilder: (row) => _formatDate(row['applied_at']),
        subtitleBuilder: (row) {
          final utm = row['utm'];
          final utmSource = utm is Map ? utm['Source']?.toString() : null;
          return [row['channel'], row['discipline'], utmSource]
              .where((value) => value != null && '$value'.isNotEmpty)
              .join(' · ');
        },
      ),
      _miniSection(
        cs,
        title: 'Лента',
        empty: 'История пока пустая',
        rows: timeline.take(8).toList(),
        titleBuilder: (row) => row['title']?.toString() ?? 'Событие',
        subtitleBuilder: (row) => _formatDate(row['occurred_at']),
      ),
    ],
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

