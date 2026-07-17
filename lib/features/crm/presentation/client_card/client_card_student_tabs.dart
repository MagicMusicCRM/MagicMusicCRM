part of 'client_card.dart';

// Read-only list view for the student Оплаты tab. Library-private via `part`,
// so the State class calls it unchanged; kept out of client_card_display.dart
// only to keep each source under the ~800-line bar.

/// Student «Оплаты» tab body: the student's payment history.
Widget _paymentsView(ColorScheme cs, {required List<Payment> payments}) {
  if (payments.isEmpty) {
    return Center(
      child: Text(
        'Оплат не найдено',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
  }
  return ListView.builder(
    padding: const EdgeInsets.all(AppSpace.xl),
    itemCount: payments.length,
    itemBuilder: (context, i) {
      final p = payments[i];
      final dt = DateTime.tryParse(p.paymentDate ?? '');
      final dateStr = dt != null
          ? DateFormat('d MMM yyyy', 'ru').format(dt)
          : '—';
      final paymentNote = p.note;
      final method = p.methodLabel;
      final subtitle = [
        dateStr,
        if (paymentNote.isNotEmpty) paymentNote,
      ].join(' • ');
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(
            Icons.account_balance_wallet_rounded,
            color: AppTheme.success,
          ),
          title: Text(
            '${p.amountRaw} ₽',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: method.isEmpty
              ? null
              : Text(
                  method,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
        ),
      );
    },
  );
}
