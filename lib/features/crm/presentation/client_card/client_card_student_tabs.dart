part of 'client_card.dart';

Widget _paymentsView(
  ColorScheme cs, {
  required CommerceStudent? commerce,
  required List<Payment> fallbackPayments,
  required bool creating,
  required String? branchId,
  required String branchName,
  required VoidCallback onCreate,
  required VoidCallback onCancel,
  required ClientPaymentSubmit onSubmit,
  required void Function(
    BuildContext context,
    String paymentId,
    EntityOpenTarget target,
  )
  onOpenPayment,
  String? highlightedPaymentId,
  ScrollController? scrollController,
}) {
  final account = commerce == null || commerce.accounts.isEmpty
      ? null
      : commerce.accounts.firstWhere(
          (item) => item.currencyCode == 'RUB',
          orElse: () => commerce.accounts.first,
        );
  final movements = commerce?.movements ?? const <CommerceMovement>[];
  final installments =
      commerce?.subscriptions
          .expand(
            (subscription) => subscription.installments.map(
              (item) => (subscription: subscription, installment: item),
            ),
          )
          .toList(growable: false) ??
      const <
        ({CommerceSubscription subscription, CommerceInstallment installment})
      >[];
  final balanceMinor = account?.balanceMinor ?? BigInt.zero;
  final paymentAvailable =
      highlightedPaymentId == null ||
      movements.any((item) => item.id == highlightedPaymentId) ||
      fallbackPayments.any((item) => item.id == highlightedPaymentId);

  return ListView(
    key: const Key('client-payments-tab'),
    controller: scrollController,
    padding: const EdgeInsets.all(AppSpace.xl),
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Оплаты и личный счёт',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: AppSpace.xs),
                Text(
                  'Платежи неизменяемы; исправления проводятся отдельной операцией.',
                  style: TextStyle(color: AppColor.text2, fontSize: 13),
                ),
              ],
            ),
          ),
          if (!creating)
            FilledButton.icon(
              key: const Key('open-payment-form'),
              onPressed: onCreate,
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('Добавить оплату'),
            ),
        ],
      ),
      const SizedBox(height: AppSpace.lg),
      if (creating) ...[
        ClientPaymentForm(
          branchId: branchId,
          branchName: branchName,
          subscriptions: commerce?.subscriptions ?? const [],
          balanceMinor: balanceMinor,
          onSubmit: onSubmit,
          onCancel: onCancel,
        ),
        const SizedBox(height: AppSpace.lg),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 720
              ? (constraints.maxWidth - AppSpace.md * 2) / 3
              : constraints.maxWidth;
          return Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: [
              _PaymentMetric(
                width: width,
                label: 'Личный счёт',
                value: formatPaymentMinor(balanceMinor),
                icon: Icons.account_balance_wallet_outlined,
                color: balanceMinor.isNegative ? cs.error : AppTheme.success,
              ),
              _PaymentMetric(
                width: width,
                label: 'Фактически оплачено',
                value: formatPaymentMinor(
                  account?.actualPaymentsMinor ?? BigInt.zero,
                ),
                icon: Icons.payments_outlined,
                color: AppTheme.success,
              ),
              _PaymentMetric(
                width: width,
                label: 'Обязательства',
                value: formatPaymentMinor(
                  (account?.obligationDebitsMinor ?? BigInt.zero) -
                      (account?.obligationCreditsMinor ?? BigInt.zero),
                ),
                icon: Icons.receipt_long_outlined,
                color: AppColor.actionBlue,
              ),
            ],
          );
        },
      ),
      const SizedBox(height: AppSpace.xl),
      if (!paymentAvailable) ...[
        const _PaymentEmpty(
          icon: Icons.link_off_rounded,
          text: 'Связанная запись недоступна',
        ),
        const SizedBox(height: AppSpace.lg),
      ],
      _PaymentSectionHeader(
        title: 'Поступления и списания',
        count: movements.length,
      ),
      const SizedBox(height: AppSpace.sm),
      if (movements.isEmpty && fallbackPayments.isEmpty)
        const _PaymentEmpty(
          icon: Icons.receipt_long_outlined,
          text: 'Операций пока нет',
        )
      else if (movements.isNotEmpty)
        ...movements.map(
          (movement) => _PaymentMovementRow(
            movement: movement,
            highlighted: movement.id == highlightedPaymentId,
            onOpen: (context, target) =>
                onOpenPayment(context, movement.id, target),
          ),
        )
      else
        ...fallbackPayments.map(
          (payment) => _LegacyPaymentRow(
            payment: payment,
            highlighted: payment.id == highlightedPaymentId,
            onOpen: payment.id == null
                ? null
                : (context, target) =>
                      onOpenPayment(context, payment.id!, target),
          ),
        ),
      const SizedBox(height: AppSpace.xl),
      _PaymentSectionHeader(
        title: 'Рассрочки и обязательства',
        count: installments.length,
      ),
      const SizedBox(height: AppSpace.sm),
      if (installments.isEmpty)
        const _PaymentEmpty(
          icon: Icons.event_available_outlined,
          text: 'Активных графиков рассрочки нет',
        )
      else
        ...installments.map(
          (entry) => _InstallmentRow(
            subscription: entry.subscription,
            installment: entry.installment,
          ),
        ),
    ],
  );
}

class _PaymentMetric extends StatelessWidget {
  const _PaymentMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColor.divider),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColor.text2)),
                const SizedBox(height: AppSpace.xs),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
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

class _PaymentSectionHeader extends StatelessWidget {
  const _PaymentSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        Text('$count', style: const TextStyle(color: AppColor.text2)),
      ],
    );
  }
}

class _PaymentMovementRow extends StatelessWidget {
  const _PaymentMovementRow({
    required this.movement,
    required this.onOpen,
    this.highlighted = false,
  });

  final CommerceMovement movement;
  final void Function(BuildContext context, EntityOpenTarget target) onOpen;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final credit = movement.direction == CommerceMovementDirection.credit;
    final title = switch (movement.kind) {
      CommerceMovementKind.payment => 'Оплата',
      CommerceMovementKind.obligation => 'Обязательство по абонементу',
      CommerceMovementKind.lessonCharge => 'Списание за занятие',
    };
    final details = [
      DateFormat('dd.MM.yyyy').format(movement.occurredAt.toLocal()),
      movement.branchName,
      switch (movement.method) {
        'cash' => 'Наличные',
        'cashless' => 'Безналичная оплата',
        _ => null,
      },
      if (movement.invoiceIdentifier?.isNotEmpty == true)
        '№ ${movement.invoiceIdentifier}',
      if (movement.status == 'paid') 'Проведён',
      movement.acceptedByName,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return Semantics(
      key: ValueKey('commerce-movement-${movement.id}'),
      button: true,
      link: true,
      label: '$title, ${formatPaymentMinor(movement.amountMinor)}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Material(
          color: cs.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: highlighted ? AppColor.gold : AppColor.divider,
              width: highlighted ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: () => onOpen(context, EntityOpenTarget.current),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    credit
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: credit ? AppTheme.success : cs.error,
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (movement.comment?.isNotEmpty == true)
                          Text(
                            movement.comment!,
                            style: const TextStyle(fontSize: 13),
                          ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          details,
                          style: const TextStyle(
                            color: AppColor.text2,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    '${credit ? '+' : '−'}${formatPaymentMinor(movement.amountMinor)}',
                    style: TextStyle(
                      color: credit ? AppTheme.success : cs.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  _EntityOpenButtons(
                    onOpen: (target) => onOpen(context, target),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({
    required this.subscription,
    required this.installment,
  });

  final CommerceSubscription subscription;
  final CommerceInstallment installment;

  @override
  Widget build(BuildContext context) {
    final paid = installment.status == 'paid';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      leading: Icon(
        paid ? Icons.check_circle_rounded : Icons.schedule_rounded,
        color: paid ? AppTheme.success : AppColor.actionBlue,
      ),
      title: Text(
        '${subscription.terms.displayName} · платёж ${installment.installmentNumber}',
      ),
      subtitle: Text(
        '${DateFormat('dd.MM.yyyy').format(installment.dueAt.toLocal())} · '
        '${paid ? 'Оплачен' : 'Ожидает оплаты'}',
      ),
      trailing: Text(
        formatPaymentMinor(
          installment.amountMinor,
          currencyCode: installment.currencyCode,
        ),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LegacyPaymentRow extends StatelessWidget {
  const _LegacyPaymentRow({
    required this.payment,
    this.onOpen,
    this.highlighted = false,
  });

  final Payment payment;
  final void Function(BuildContext context, EntityOpenTarget target)? onOpen;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: highlighted
          ? RoundedRectangleBorder(
              side: const BorderSide(color: AppColor.gold, width: 2),
              borderRadius: BorderRadius.circular(AppRadius.control),
            )
          : null,
      leading: const Icon(Icons.payments_outlined, color: AppTheme.success),
      title: Text('${payment.amountRaw} ₽'),
      subtitle: Text(payment.paymentDate ?? 'Дата не указана'),
      onTap: onOpen == null
          ? null
          : () => onOpen!(context, EntityOpenTarget.current),
      trailing: onOpen == null
          ? null
          : _EntityOpenButtons(onOpen: (target) => onOpen!(context, target)),
    );
  }
}

class _PaymentEmpty extends StatelessWidget {
  const _PaymentEmpty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(color: AppColor.divider),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColor.text2),
          const SizedBox(width: AppSpace.md),
          Text(text, style: const TextStyle(color: AppColor.text2)),
        ],
      ),
    );
  }
}
