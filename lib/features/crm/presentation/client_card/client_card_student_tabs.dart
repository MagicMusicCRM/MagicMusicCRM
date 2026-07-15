part of 'client_card.dart';

// Read-only list views for the student Оплаты / Инвойсы tabs. Library-private
// via `part`, so the State class calls them unchanged; kept out of
// client_card_display.dart only to keep each source under the ~800-line bar.

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

/// Student «Инвойсы» tab body: expected/planned payments with paid/pending state.
Widget _invoicesView(
  ColorScheme cs, {
  required List<Map<String, dynamic>> expectedPayments,
}) {
  if (expectedPayments.isEmpty) {
    return Center(
      child: Text(
        'Инвойсов не найдено',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
  }
  return ListView.builder(
    padding: const EdgeInsets.all(AppSpace.xl),
    itemCount: expectedPayments.length,
    itemBuilder: (context, i) {
      final p = expectedPayments[i];
      final dt = DateTime.tryParse(p['due_date']?.toString() ?? '');
      final dateStr = dt != null
          ? DateFormat('d MMM yyyy', 'ru').format(dt)
          : '—';
      final status = p['status']?.toString() ?? 'pending';
      final description = (p['description'] ?? '').toString().trim();
      final paid = status == 'paid';
      final subtitle = [
        'Срок: $dateStr',
        if (description.isNotEmpty) description,
      ].join(' • ');
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(
            paid ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
            color: paid ? AppTheme.success : AppTheme.warning,
          ),
          title: Text(
            '${p['amount']} ₽',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (paid ? AppTheme.success : AppTheme.warning).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              paid ? 'Оплачено' : 'Ожидает',
              style: TextStyle(
                fontSize: 11,
                color: paid ? AppTheme.success : AppTheme.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    },
  );
}
