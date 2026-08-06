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
        // Flexible: на телефонной ширине длинный заголовок переносится, а не
        // переполняет Row (#13).
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColor.gold,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Plain-student history timeline: own tasks + non-progress comments, merged
/// and sorted desc. (Converted clients use [_mergedHistoryView] instead.)
Widget _studentTimelineView(
  ColorScheme cs, {
  required List<Map<String, dynamic>> tasks,
  required List<Map<String, dynamic>> comments,
  bool embedded = false,
}) {
  if (tasks.isEmpty && comments.isEmpty) {
    return Center(
      child: Text(
        'История пуста',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
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
    shrinkWrap: embedded,
    physics: embedded ? const NeverScrollableScrollPhysics() : null,
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
                        color: isTask ? AppTheme.warning : AppTheme.primaryGold,
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
  bool embedded = false,
}) {
  // Lead status history loads independently; show a spinner until it settles
  // so converted history isn't briefly missing its lead half.
  if (loading) {
    return const Center(child: CircularProgressIndicator(color: AppColor.gold));
  }
  if (items.isEmpty) {
    return Center(
      child: Text(
        'История пуста',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
  }
  return ListView.builder(
    padding: const EdgeInsets.all(AppSpace.xl),
    shrinkWrap: embedded,
    physics: embedded ? const NeverScrollableScrollPhysics() : null,
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
      // Who made the change: stored all along, but the card only ever showed
      // the transition and the date.
      final author = h['changed_by_name']?.toString().trim() ?? '';
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
              if (author.isNotEmpty) author,
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

// _entityTile удалён: строки задач стали раскрываемым [_TaskTile] (#12), а
// других потребителей у плоской плитки не осталось.

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

String _subscriptionRemainder(Subscription s) {
  String hours(num v) =>
      v == v.truncate() ? v.toInt().toString() : v.toStringAsFixed(1);
  final total = s.lessonsTotal;
  final left = total - s.lessonsUsed;
  final price = s.packagePriceRaw;
  final money = (price is num && total > 0)
      ? ' / ${(price / total * left).round()} ₽'
      : '';
  final status = s.status;
  final suffix = status == 'active' ? '' : ' · ${_formatStatus(status)}';
  return 'Остаток: ${hours(left)} из ${hours(total)} астр.ч.$money$suffix';
}

/// «Курс» — what the whole subscription is: its hours and its price, as
/// opposed to «Остаток», which is what is left of it.
String? _subscriptionCourse(Subscription s) {
  final total = s.lessonsTotal;
  if (total <= 0) return null;
  String hours(num v) =>
      v == v.truncate() ? v.toInt().toString() : v.toStringAsFixed(1);
  final price = s.packagePriceRaw;
  final money = price is num ? ' / ${price.round()} ₽' : '';
  return 'Курс: ${hours(total)} астр.ч.$money';
}

/// «Оплачено» — сколько денег пришло на личный счёт за этот абонемент.
///
/// ✔ Решение владельца 16.07: «оплату и переплату по абонементу считаем по
/// личному счёту». Абонемент — бизнес-логика, которая кладёт свою стоимость на
/// счёт клиента (`issueSubscription` заводит приход), поэтому «Оплачено» это и
/// есть тот приход, а не отдельная сущность.
///
/// Возвращает null, если прихода нет: у старых абонементов не проставлен
/// `payment_id`, и «Оплачено: 0 ₽» соврало бы про них.
String? _subscriptionPaid(Subscription s) {
  final paid = s.paidAmountRaw;
  if (paid is! num) return null;
  return 'Оплачено: ${paid.round()} ₽';
}

/// «Переплата»/«Долг» — разница между тем, что пришло на счёт за абонемент, и
/// его стоимостью. Считается ровно из этих двух ledger-величин.
///
/// Ноль не показываем: «Переплата: 0 ₽» — это шум под каждым абонементом,
/// оплаченным ровно в стоимость, то есть под нормой.
({String label, bool isDebt})? _subscriptionOverpayment(Subscription s) {
  final paid = s.paidAmountRaw;
  final price = s.packagePriceRaw;
  if (paid is! num || price is! num) return null;
  final diff = paid - price;
  if (diff == 0) return null;
  return diff > 0
      ? (label: 'Переплата: ${diff.round()} ₽', isDebt: false)
      : (label: 'Долг: ${(-diff).round()} ₽', isDebt: true);
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
