import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class ClientPaymentSubmission {
  const ClientPaymentSubmission({required this.input, required this.identity});

  final RecordSubscriptionPaymentInput input;
  final MagicMutationIdentity identity;
}

typedef ClientPaymentSubmit =
    Future<void> Function(ClientPaymentSubmission submission);

class ClientPaymentAdjustmentSubmission {
  const ClientPaymentAdjustmentSubmission({
    required this.input,
    required this.identity,
  });

  final RecordPaymentAdjustmentInput input;
  final MagicMutationIdentity identity;
}

typedef ClientPaymentAdjustmentSubmit =
    Future<void> Function(ClientPaymentAdjustmentSubmission submission);

class ClientPaymentForm extends StatefulWidget {
  const ClientPaymentForm({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.subscriptions,
    required this.balanceMinor,
    required this.onSubmit,
    required this.onCancel,
    this.now,
  });

  final String? branchId;
  final String branchName;
  final List<CommerceSubscription> subscriptions;
  final BigInt balanceMinor;
  final ClientPaymentSubmit onSubmit;
  final VoidCallback onCancel;
  final DateTime? now;

  @override
  State<ClientPaymentForm> createState() => _ClientPaymentFormState();
}

class _ClientPaymentFormState extends State<ClientPaymentForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  final _invoiceController = TextEditingController();

  late DateTime _date;
  late MagicMutationIdentity _identity;
  SubscriptionPaymentMethod _method = SubscriptionPaymentMethod.cashless;
  String? _subscriptionId;
  bool _busy = false;
  bool _attempted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _identity = MagicMutationIdentity.create('client-payment');
    if (widget.subscriptions.isNotEmpty) {
      _subscriptionId = widget.subscriptions
          .firstWhere(
            (item) => item.status == 'active',
            orElse: () => widget.subscriptions.first,
          )
          .id;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    _invoiceController.dispose();
    super.dispose();
  }

  void _changed() {
    if (_attempted) {
      _identity = MagicMutationIdentity.create('client-payment');
      _attempted = false;
    }
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ru'),
    );
    if (selected == null || selected == _date) return;
    setState(() => _date = selected);
    _changed();
  }

  String? _validateAmount(String? raw) {
    final amount = parsePaymentMinor(raw ?? '');
    if (amount == null || amount <= BigInt.zero) {
      return 'Введите положительную сумму';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    if (widget.branchId == null || widget.branchId!.isEmpty) {
      setState(() => _error = 'Сначала укажите филиал в карточке ученика.');
      return;
    }
    final amount = parsePaymentMinor(_amountController.text)!;
    final occurredAt = DateTime(_date.year, _date.month, _date.day, 12).toUtc();
    final submission = ClientPaymentSubmission(
      identity: _identity,
      input: RecordSubscriptionPaymentInput(
        issuedSubscriptionId: _subscriptionId!,
        amountMinor: amount,
        method: _method,
        occurredAt: occurredAt,
        currencyCode: 'RUB',
        branchId: widget.branchId,
        comment: _commentController.text,
        invoiceIdentifier: _invoiceController.text,
      ),
    );
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      await widget.onSubmit(submission);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amount = parsePaymentMinor(_amountController.text) ?? BigInt.zero;
    final after = widget.balanceMinor + amount;
    return Form(
      key: _formKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: AppColor.divider),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Новая оплата',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть форму оплаты',
                    onPressed: _busy ? null : widget.onCancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final fields = <Widget>[
                    _ReadonlyPaymentField(
                      label: 'Филиал',
                      value: widget.branchName,
                      icon: Icons.apartment_rounded,
                    ),
                    InkWell(
                      key: const Key('payment-date'),
                      onTap: _busy ? null : _pickDate,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Дата',
                          prefixIcon: Icon(Icons.calendar_today_rounded),
                        ),
                        child: Text(DateFormat('dd.MM.yyyy').format(_date)),
                      ),
                    ),
                    TextFormField(
                      key: const Key('payment-amount'),
                      controller: _amountController,
                      enabled: !_busy,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                      ],
                      validator: _validateAmount,
                      onChanged: (_) {
                        _changed();
                        setState(() {});
                      },
                      decoration: const InputDecoration(
                        labelText: 'Сумма, ₽',
                        prefixIcon: Icon(Icons.currency_ruble_rounded),
                      ),
                    ),
                    DropdownButtonFormField<SubscriptionPaymentMethod>(
                      key: const Key('payment-method'),
                      initialValue: _method,
                      decoration: const InputDecoration(
                        labelText: 'Способ оплаты',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SubscriptionPaymentMethod.cashless,
                          child: Text('Безналичная оплата'),
                        ),
                        DropdownMenuItem(
                          value: SubscriptionPaymentMethod.cash,
                          child: Text('Наличные'),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _method = value);
                              _changed();
                            },
                    ),
                    const _ReadonlyPaymentField(
                      label: 'Статус',
                      value: 'Проведён',
                      icon: Icons.verified_rounded,
                    ),
                    const _ReadonlyPaymentField(
                      label: 'Принял',
                      value: 'Текущий сотрудник · фиксируется автоматически',
                      icon: Icons.badge_outlined,
                    ),
                  ];
                  if (!wide) {
                    return Column(
                      children: fields
                          .expand(
                            (field) => [
                              field,
                              const SizedBox(height: AppSpace.md),
                            ],
                          )
                          .toList(growable: false),
                    );
                  }
                  return Wrap(
                    spacing: AppSpace.md,
                    runSpacing: AppSpace.md,
                    children: fields
                        .map(
                          (field) => SizedBox(
                            width: (constraints.maxWidth - AppSpace.md) / 2,
                            child: field,
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                key: const Key('payment-subscription'),
                initialValue: _subscriptionId,
                decoration: const InputDecoration(
                  labelText: 'Погашаемое обязательство',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
                validator: (value) => value == null
                    ? 'Сначала выдайте и выберите абонемент'
                    : null,
                items: widget.subscriptions
                    .map(
                      (subscription) => DropdownMenuItem<String>(
                        value: subscription.id,
                        child: Text(subscription.terms.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() => _subscriptionId = value);
                        _changed();
                      },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const Key('payment-invoice'),
                controller: _invoiceController,
                enabled: !_busy,
                maxLength: 120,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(
                  labelText: 'Номер счёта или чека',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextFormField(
                key: const Key('payment-comment'),
                controller: _commentController,
                enabled: !_busy,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColor.actionBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(
                    color: AppColor.actionBlue.withValues(alpha: 0.35),
                  ),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: AppSpace.md,
                  runSpacing: AppSpace.xs,
                  children: [
                    Text(
                      'Баланс до: ${formatPaymentMinor(widget.balanceMinor)}',
                    ),
                    Text('Оплата: +${formatPaymentMinor(amount)}'),
                    Text(
                      'Баланс после: ${formatPaymentMinor(after)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpace.md),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    key: const Key('payment-error'),
                    style: TextStyle(color: cs.error),
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : widget.onCancel,
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  FilledButton.icon(
                    key: const Key('payment-submit'),
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_card_rounded),
                    label: Text(_attempted ? 'Повторить' : 'Провести оплату'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadonlyPaymentField extends StatelessWidget {
  const _ReadonlyPaymentField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      child: Text(value),
    );
  }
}

class ClientPaymentAdjustmentForm extends StatefulWidget {
  const ClientPaymentAdjustmentForm({
    super.key,
    required this.payment,
    required this.onSubmit,
    required this.onCancel,
    this.now,
  });

  final CommerceMovement payment;
  final ClientPaymentAdjustmentSubmit onSubmit;
  final VoidCallback onCancel;
  final DateTime? now;

  @override
  State<ClientPaymentAdjustmentForm> createState() =>
      _ClientPaymentAdjustmentFormState();
}

class _ClientPaymentAdjustmentFormState
    extends State<ClientPaymentAdjustmentForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  late MagicMutationIdentity _identity;
  PaymentAdjustmentKind _kind = PaymentAdjustmentKind.refund;
  String _direction = 'outcome';
  bool _busy = false;
  bool _attempted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _identity = MagicMutationIdentity.create('payment-adjustment');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _changed() {
    if (_attempted) {
      _identity = MagicMutationIdentity.create('payment-adjustment');
      _attempted = false;
    }
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final now = widget.now ?? DateTime.now();
    final input = RecordPaymentAdjustmentInput(
      sourcePaymentId: widget.payment.id,
      kind: _kind,
      amountMinor: parsePaymentMinor(_amountController.text)!,
      occurredAt: DateTime(now.year, now.month, now.day, 12).toUtc(),
      reason: _reasonController.text,
      direction: _kind == PaymentAdjustmentKind.correction ? _direction : null,
    );
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        ClientPaymentAdjustmentSubmission(input: input, identity: _identity),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceDate = DateFormat(
      'dd.MM.yyyy',
    ).format(widget.payment.occurredAt.toLocal());
    return Form(
      key: _formKey,
      child: DecoratedBox(
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Исправление оплаты от $sourceDate · '
                      '${formatPaymentMinor(widget.payment.amountMinor)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть форму исправления',
                    onPressed: _busy ? null : widget.onCancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (widget.payment.subscriptionName?.isNotEmpty == true)
                Text(
                  'Назначение: ${widget.payment.subscriptionName}',
                  style: const TextStyle(color: AppColor.text2),
                ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<PaymentAdjustmentKind>(
                key: const Key('adjustment-kind'),
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Операция'),
                items: const [
                  DropdownMenuItem(
                    value: PaymentAdjustmentKind.refund,
                    child: Text('Возврат'),
                  ),
                  DropdownMenuItem(
                    value: PaymentAdjustmentKind.correction,
                    child: Text('Корректировка'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _kind = value);
                        _changed();
                      },
              ),
              if (_kind == PaymentAdjustmentKind.correction) ...[
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<String>(
                  key: const Key('adjustment-direction'),
                  initialValue: _direction,
                  decoration: const InputDecoration(labelText: 'Направление'),
                  items: const [
                    DropdownMenuItem(value: 'outcome', child: Text('Расход')),
                    DropdownMenuItem(value: 'income', child: Text('Приход')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _direction = value);
                          _changed();
                        },
                ),
              ],
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const Key('adjustment-amount'),
                controller: _amountController,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                ],
                validator: (raw) {
                  final value = parsePaymentMinor(raw ?? '');
                  return value == null || value <= BigInt.zero
                      ? 'Введите положительную сумму'
                      : null;
                },
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(labelText: 'Сумма, ₽'),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const Key('adjustment-reason'),
                controller: _reasonController,
                enabled: !_busy,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                validator: (value) =>
                    value?.trim().isEmpty != false ? 'Укажите причину' : null,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(labelText: 'Причина'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('adjustment-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: AppSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : widget.onCancel,
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  FilledButton(
                    key: const Key('adjustment-submit'),
                    onPressed: _busy ? null : _submit,
                    child: Text(_attempted ? 'Повторить' : 'Провести'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

BigInt? parsePaymentMinor(String raw) {
  final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final rubles = BigInt.tryParse(parts[0]);
  if (rubles == null) return null;
  final kopecks = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
  return rubles * BigInt.from(100) + BigInt.parse(kopecks);
}

String formatPaymentMinor(BigInt minor, {String currencyCode = 'RUB'}) {
  final negative = minor.isNegative;
  final absolute = minor.abs();
  final rubles = absolute ~/ BigInt.from(100);
  final kopecks = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
  final grouped = NumberFormat.decimalPattern('ru').format(rubles.toInt());
  final value = '$grouped,$kopecks';
  return '${negative ? '−' : ''}$value ${currencyCode == 'RUB' ? '₽' : currencyCode}';
}
