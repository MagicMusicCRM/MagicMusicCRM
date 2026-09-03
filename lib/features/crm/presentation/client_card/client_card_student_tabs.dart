part of 'client_card.dart';

Widget _lessonBalanceSummary(
  CommerceLessonBalance balance, {
  required Map<String, int> indicators,
  required VoidCallback onSubscriptions,
  required VoidCallback onPayments,
}) {
  String units(num value) => value == value.truncate()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  final debt = balance.debts.isEmpty
      ? 'Нет'
      : balance.debts
            .map(
              (item) => formatPaymentMinor(
                item.amountMinor,
                currencyCode: item.currencyCode,
              ),
            )
            .join(', ');
  final date = DateFormat('dd.MM.yyyy');
  final metrics = <(String, String)>[
    ('Всего', units(balance.total)),
    ('Использовано', units(balance.used)),
    ('Зарезервировано', units(balance.reserved)),
    ('Оплачено', units(balance.paid)),
    ('Доступно', units(balance.available)),
    ('Долг', debt),
    (
      'Следующий платёж',
      balance.nextPaymentAt == null
          ? 'Нет'
          : date.format(balance.nextPaymentAt!.toLocal()),
    ),
    (
      'Срок',
      balance.expiresAt == null
          ? 'Без срока'
          : date.format(balance.expiresAt!.toLocal()),
    ),
    ('Оплачиваемые пропуски', '${indicators['paidMisses'] ?? 0}'),
    (
      'Частично оплачиваемые пропуски',
      '${indicators['partiallyPaidMisses'] ?? 0}',
    ),
    ('Неоплачиваемые пропуски', '${indicators['unpaidMisses'] ?? 0}'),
  ];
  return Builder(
    builder: (context) => DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColor.divider),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Остаток занятий · ${balance.activeSubscriptionCount} '
              '${balance.activeSubscriptionCount == 1 ? 'активный' : 'активных'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.lg,
              runSpacing: AppSpace.md,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.$1,
                          style: const TextStyle(
                            color: AppColor.text2,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          metric.$2,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                OutlinedButton.icon(
                  key: const Key('lesson-balance-subscriptions'),
                  onPressed: onSubscriptions,
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: const Text('Открыть абонементы'),
                ),
                TextButton.icon(
                  key: const Key('lesson-balance-payments'),
                  onPressed: onPayments,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Финансовая история'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _paymentsView(
  ColorScheme cs, {
  required CommerceStudent? commerce,
  required List<Payment> fallbackPayments,
  required bool creating,
  required CommerceMovement? adjustingPayment,
  required String? branchId,
  required String branchName,
  required VoidCallback onCreate,
  required VoidCallback onCancel,
  required ClientPaymentSubmit onSubmit,
  required ValueChanged<CommerceMovement> onAdjust,
  required void Function(CommerceMovement, ClientPaymentStatus) onTransition,
  required ValueChanged<CommerceMovement> onCorrect,
  required ValueChanged<CommerceMovement> onReverse,
  required ValueChanged<CommerceMovement> onReverseAdjustment,
  required VoidCallback onCancelAdjustment,
  required ClientPaymentAdjustmentSubmit onSubmitAdjustment,
  required void Function(
    BuildContext context,
    String paymentId,
    EntityPresentationReference presentation,
    EntityOpenTarget target,
  )
  onOpenPayment,
  String? highlightedPaymentId,
  ScrollController? scrollController,
  bool embedded = false,
}) {
  final account = commerce == null || commerce.accounts.isEmpty
      ? null
      : commerce.accounts.firstWhere(
          (item) => item.currencyCode == 'RUB',
          orElse: () => commerce.accounts.first,
        );
  final movements = commerce?.movements ?? const <CommerceMovement>[];
  final technicalHistory =
      commerce?.technicalHistory ?? const <CommerceTechnicalFinanceEvent>[];
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
    controller: embedded ? null : scrollController,
    shrinkWrap: embedded,
    physics: embedded ? const NeverScrollableScrollPhysics() : null,
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
              label: const Text('Внести оплату'),
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
      if (adjustingPayment != null) ...[
        ClientPaymentAdjustmentForm(
          payment: adjustingPayment,
          onSubmit: onSubmitAdjustment,
          onCancel: onCancelAdjustment,
        ),
        const SizedBox(height: AppSpace.lg),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 960
              ? 4
              : constraints.maxWidth >= 720
              ? 2
              : 1;
          final width =
              (constraints.maxWidth - AppSpace.md * (columns - 1)) / columns;
          return Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: [
              _PaymentMetric(
                width: width,
                label: 'Личный счёт',
                value: formatPaymentMinor(
                  balanceMinor,
                  currencyCode: account?.currencyCode ?? 'RUB',
                ),
                icon: Icons.account_balance_wallet_outlined,
                color: balanceMinor.isNegative ? cs.error : AppTheme.success,
              ),
              _PaymentMetric(
                width: width,
                label: 'Оплачено с учётом возвратов',
                value: formatPaymentMinor(
                  (account?.actualPaymentsMinor ?? BigInt.zero) +
                      (account?.adjustmentsMinor ?? BigInt.zero),
                  currencyCode: account?.currencyCode ?? 'RUB',
                ),
                icon: Icons.payments_outlined,
                color: AppTheme.success,
              ),
              _PaymentMetric(
                width: width,
                label: 'Ожидает подтверждения',
                value: formatPaymentMinor(
                  account?.pendingMinor ?? BigInt.zero,
                  currencyCode: account?.currencyCode ?? 'RUB',
                ),
                icon: Icons.hourglass_top_rounded,
                color: AppColor.actionBlue,
              ),
              _PaymentMetric(
                width: width,
                label: 'Долг',
                value: formatPaymentMinor(
                  account?.debtMinor ?? BigInt.zero,
                  currencyCode: account?.currencyCode ?? 'RUB',
                ),
                icon: Icons.warning_amber_rounded,
                color: (account?.debtMinor ?? BigInt.zero) > BigInt.zero
                    ? cs.error
                    : AppTheme.success,
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
      _PaymentExpansion(
        key: const Key('payment-movements-expansion'),
        title: 'Поступления и списания',
        count: movements.isNotEmpty
            ? movements.length
            : fallbackPayments.length,
        initiallyExpanded: highlightedPaymentId != null,
        children: [
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
                onOpen: (context, target) => onOpenPayment(
                  context,
                  movement.id,
                  _movementPresentation(movement),
                  target,
                ),
                onAdjust:
                    movement.kind == CommerceMovementKind.payment ||
                        (movement.kind == CommerceMovementKind.paymentRecord &&
                            movement.status == 'paid' &&
                            movement.sourcePaymentId != null)
                    ? () => onAdjust(movement)
                    : null,
                onTransition:
                    movement.kind == CommerceMovementKind.paymentRecord
                    ? (status) => onTransition(movement, status)
                    : null,
                onCorrect:
                    movement.kind == CommerceMovementKind.paymentRecord &&
                        movement.paymentRecordVersion != null
                    ? () => onCorrect(movement)
                    : null,
                onReverse:
                    movement.kind == CommerceMovementKind.paymentRecord &&
                        movement.paymentRecordVersion != null
                    ? () => onReverse(movement)
                    : null,
                onReverseAdjustment:
                    (movement.kind == CommerceMovementKind.refund ||
                            movement.kind == CommerceMovementKind.adjustment) &&
                        movement.adjustmentVersion != null
                    ? () => onReverseAdjustment(movement)
                    : null,
              ),
            )
          else
            ...fallbackPayments.map(
              (payment) => _LegacyPaymentRow(
                payment: payment,
                highlighted: payment.id == highlightedPaymentId,
                onOpen: payment.id == null
                    ? null
                    : (context, target) => onOpenPayment(
                        context,
                        payment.id!,
                        EntityPresentationReference(
                          primary: [
                            payment.paymentDate,
                            formatPaymentMajor(
                              payment.amountRaw ?? payment.amount,
                              currencyCode: payment.currency ?? 'RUB',
                            ),
                          ].whereType<String>().join(' · '),
                        ),
                        target,
                      ),
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      _PaymentExpansion(
        key: const Key('payment-installments-expansion'),
        title: 'Рассрочки и обязательства',
        count: installments.length,
        children: [
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
      ),
      if (technicalHistory.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        _PaymentExpansion(
          key: const Key('payment-technical-history-expansion'),
          title: 'Техническая история',
          count: technicalHistory.length,
          children: [
            for (final event in technicalHistory)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(switch (event.eventType) {
                  'monetary_reversal' => 'Оплата удалена с возвратом',
                  'adjustment_reversal' =>
                    'Возврат или корректировка сторнированы',
                  _ => 'Запись оплаты удалена',
                }),
                subtitle: Text(
                  [
                    event.reason,
                    event.actorName,
                    DateFormat(
                      'dd.MM.yyyy HH:mm',
                    ).format(event.occurredAt.toLocal()),
                  ].whereType<String>().join(' · '),
                ),
                trailing: Text(
                  formatPaymentMinor(
                    event.amountMinor,
                    currencyCode: event.currencyCode,
                  ),
                ),
              ),
          ],
        ),
      ],
    ],
  );
}

EntityPresentationReference _movementPresentation(CommerceMovement movement) {
  final identifier = movement.invoiceIdentifier?.trim();
  return EntityPresentationReference(
    primary: identifier?.isNotEmpty == true
        ? '№ $identifier'
        : '${DateFormat('dd.MM.yyyy').format(movement.occurredAt.toLocal())} · '
              '${formatPaymentMinor(movement.amountMinor, currencyCode: movement.currencyCode)}',
    context: [
      movement.branchName,
      if (movement.kind == CommerceMovementKind.paymentRecord)
        clientPaymentStatusLabel(movement.status),
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
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

class _PaymentExpansion extends StatelessWidget {
  const _PaymentExpansion({
    super.key,
    required this.title,
    required this.count,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final int count;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        maintainState: false,
        title: _PaymentSectionHeader(title: title, count: count),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpace.sm,
          0,
          AppSpace.sm,
          AppSpace.sm,
        ),
        children: [
          Divider(height: 1, color: cs.outlineVariant),
          ...children,
        ],
      ),
    );
  }
}

class _PaymentMovementRow extends StatelessWidget {
  const _PaymentMovementRow({
    required this.movement,
    required this.onOpen,
    this.onAdjust,
    this.onTransition,
    this.onCorrect,
    this.onReverse,
    this.onReverseAdjustment,
    this.highlighted = false,
  });

  final CommerceMovement movement;
  final void Function(BuildContext context, EntityOpenTarget target) onOpen;
  final bool highlighted;
  final VoidCallback? onAdjust;
  final ValueChanged<ClientPaymentStatus>? onTransition;
  final VoidCallback? onCorrect;
  final VoidCallback? onReverse;
  final VoidCallback? onReverseAdjustment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final credit = movement.direction == CommerceMovementDirection.credit;
    final title = switch (movement.kind) {
      CommerceMovementKind.payment => 'Оплата',
      CommerceMovementKind.paymentRecord => 'Оплата',
      CommerceMovementKind.refund => 'Возврат',
      CommerceMovementKind.adjustment => 'Корректировка',
      CommerceMovementKind.obligation => switch ((
        movement.direction,
        movement.factType,
      )) {
        (CommerceMovementDirection.credit, 'adjustment') =>
          'Возврат по абонементу',
        (CommerceMovementDirection.credit, _) => 'Пересчёт абонемента',
        (CommerceMovementDirection.debit, 'installment') =>
          'Взнос по абонементу',
        (CommerceMovementDirection.debit, _) => 'Начисление по абонементу',
      },
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
      if (movement.kind == CommerceMovementKind.paymentRecord)
        clientPaymentStatusLabel(movement.status),
      if (movement.kind == CommerceMovementKind.payment &&
          movement.status == 'paid')
        'Оплачен',
      movement.acceptedByName,
      if (movement.subscriptionName?.isNotEmpty == true)
        'Назначение: ${movement.subscriptionName}',
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EntityLinkText(
          text: title,
          onPressed: () => onOpen(context, EntityOpenTarget.current),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (movement.kind == CommerceMovementKind.paymentRecord)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: _PaymentStatusBadge(status: movement.status),
          ),
        if (movement.comment?.isNotEmpty == true)
          Text(movement.comment!, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: AppSpace.xs),
        Text(
          details,
          style: const TextStyle(color: AppColor.text2, fontSize: 12),
        ),
      ],
    );
    final amount = Text(
      '${credit ? '+' : '−'}${formatPaymentMinor(movement.amountMinor.abs(), currencyCode: movement.currencyCode)}',
      style: TextStyle(
        color: credit ? AppTheme.success : cs.error,
        fontWeight: FontWeight.w800,
      ),
    );
    final actions = <Widget>[
      if (onAdjust != null)
        IconButton(
          key: ValueKey('adjust-payment-${movement.id}'),
          tooltip: 'Возврат или корректировка',
          onPressed: onAdjust,
          icon: const Icon(Icons.undo_rounded),
        ),
      if (onTransition != null && movement.status != 'paid')
        PopupMenuButton<ClientPaymentStatus>(
          key: ValueKey('payment-status-${movement.id}'),
          tooltip: 'Изменить статус оплаты',
          onSelected: onTransition,
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: ClientPaymentStatus.paid,
              child: Text('Подтвердить оплату'),
            ),
            if (movement.status == 'posted_pending')
              const PopupMenuItem(
                value: ClientPaymentStatus.unpaid,
                child: Text('Отметить как долг'),
              ),
            if (movement.status == 'unpaid')
              const PopupMenuItem(
                value: ClientPaymentStatus.postedPending,
                child: Text('Ожидает подтверждения'),
              ),
          ],
          icon: const Icon(Icons.sync_alt_rounded),
        ),
      if (onCorrect != null)
        IconButton(
          key: ValueKey('correct-payment-${movement.id}'),
          tooltip: 'Изменить и пересчитать оплату',
          onPressed: onCorrect,
          icon: const Icon(Icons.edit_note_rounded, color: AppColor.gold),
        ),
      if (onReverse != null)
        IconButton(
          key: ValueKey('reverse-payment-${movement.id}'),
          tooltip: 'Удалить оплату с причиной',
          onPressed: onReverse,
          icon: Icon(Icons.delete_outline_rounded, color: cs.error),
        ),
      if (onReverseAdjustment != null)
        IconButton(
          key: ValueKey('reverse-adjustment-${movement.id}'),
          tooltip: 'Сторнировать возврат или корректировку',
          onPressed: onReverseAdjustment,
          icon: Icon(Icons.settings_backup_restore_rounded, color: cs.error),
        ),
    ];
    return Semantics(
      key: ValueKey('commerce-movement-${movement.id}'),
      container: true,
      label:
          '$title, ${formatPaymentMinor(movement.amountMinor, currencyCode: movement.currencyCode)}',
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
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final leading = Icon(
                  credit ? Icons.south_west_rounded : Icons.north_east_rounded,
                  color: credit ? AppTheme.success : cs.error,
                );
                if (constraints.maxWidth >= 620) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leading,
                      const SizedBox(width: AppSpace.md),
                      Expanded(child: content),
                      const SizedBox(width: AppSpace.sm),
                      amount,
                      ...actions,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leading,
                        const SizedBox(width: AppSpace.sm),
                        Expanded(child: content),
                      ],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [amount, ...actions],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentStatusBadge extends StatelessWidget {
  const _PaymentStatusBadge({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (status) {
      'paid' => AppTheme.success,
      'posted_pending' => AppColor.actionBlue,
      _ => cs.error,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: 3,
        ),
        child: Text(
          clientPaymentStatusLabel(status),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
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
      title: onOpen == null
          ? Text(
              formatPaymentMajor(
                payment.amountRaw ?? payment.amount,
                currencyCode: payment.currency ?? 'RUB',
              ),
            )
          : EntityLinkText(
              text: formatPaymentMajor(
                payment.amountRaw ?? payment.amount,
                currencyCode: payment.currency ?? 'RUB',
              ),
              onPressed: () => onOpen!(context, EntityOpenTarget.current),
            ),
      subtitle: Text(payment.paymentDate ?? 'Дата не указана'),
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
