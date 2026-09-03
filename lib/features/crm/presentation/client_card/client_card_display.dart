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
          height: 16,
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
              color: AppColor.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
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
      ? ' / ${formatPaymentMajor(price / total * left, currencyCode: s.raw['currency_code']?.toString() ?? 'RUB')}'
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
  final minor = BigInt.tryParse(s.raw['final_price_minor']?.toString() ?? '');
  final currency = s.raw['currency_code']?.toString() ?? 'RUB';
  final money = minor != null
      ? ' / ${formatPaymentMinor(minor, currencyCode: currency)}'
      : price != null
      ? ' / ${formatPaymentMajor(price, currencyCode: currency)}'
      : '';
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
  final minor = BigInt.tryParse(s.raw['actual_paid_minor']?.toString() ?? '');
  final currency = s.raw['currency_code']?.toString() ?? 'RUB';
  if (minor != null) {
    return 'Оплачено: ${formatPaymentMinor(minor, currencyCode: currency)}';
  }
  if (paid == null) return null;
  return 'Оплачено: ${formatPaymentMajor(paid, currencyCode: currency)}';
}

/// «Переплата»/«Долг» — разница между тем, что пришло на счёт за абонемент, и
/// его стоимостью. Считается ровно из этих двух ledger-величин.
///
/// Ноль не показываем: «Переплата: 0 ₽» — это шум под каждым абонементом,
/// оплаченным ровно в стоимость, то есть под нормой.
({String label, bool isDebt})? _subscriptionOverpayment(Subscription s) {
  final paid = s.paidAmountRaw;
  final price = s.packagePriceRaw;
  final paidMinor = BigInt.tryParse(
    s.raw['actual_paid_minor']?.toString() ?? '',
  );
  final priceMinor = BigInt.tryParse(
    s.raw['final_price_minor']?.toString() ?? '',
  );
  final currency = s.raw['currency_code']?.toString() ?? 'RUB';
  if (paidMinor != null && priceMinor != null) {
    final diff = paidMinor - priceMinor;
    if (diff == BigInt.zero) return null;
    final amount = formatPaymentMinor(diff.abs(), currencyCode: currency);
    return (
      label: '${diff.isNegative ? 'Долг' : 'Переплата'}: $amount',
      isDebt: diff.isNegative,
    );
  }
  if (paid is! num || price is! num) return null;
  final diff = paid - price;
  if (diff == 0) return null;
  return diff > 0
      ? (
          label:
              'Переплата: ${formatPaymentMajor(diff, currencyCode: currency)}',
          isDebt: false,
        )
      : (
          label: 'Долг: ${formatPaymentMajor(-diff, currencyCode: currency)}',
          isDebt: true,
        );
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
