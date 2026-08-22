import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

class ClientPaymentSubmission {
  const ClientPaymentSubmission({required this.input, required this.identity});

  final CreateClientPaymentRecordInput input;
  final MagicMutationIdentity identity;
}

typedef ClientPaymentSubmit =
    Future<void> Function(ClientPaymentSubmission submission);

class ClientPaymentTransitionSubmission {
  const ClientPaymentTransitionSubmission({
    required this.input,
    required this.identity,
  });

  final TransitionClientPaymentRecordInput input;
  final MagicMutationIdentity identity;
}

class ClientPaymentReversalSubmission {
  const ClientPaymentReversalSubmission({
    required this.reason,
    required this.identity,
  });

  final String reason;
  final MagicMutationIdentity identity;
}

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
  final _reasonController = TextEditingController(text: 'Оплата по абонементу');

  late DateTime _date;
  late MagicMutationIdentity _identity;
  SubscriptionPaymentMethod _method = SubscriptionPaymentMethod.cashless;
  ClientPaymentStatus _status = ClientPaymentStatus.postedPending;
  String? _subscriptionId;
  bool _busy = false;
  bool _attempted = false;
  String? _error;

  List<CommerceSubscription> get _activeSubscriptions => widget.subscriptions
      .where((subscription) => subscription.status == 'active')
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _identity = MagicMutationIdentity.create('client-payment');
    if (_activeSubscriptions.isNotEmpty) {
      _subscriptionId = _activeSubscriptions.first.id;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    _invoiceController.dispose();
    _reasonController.dispose();
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
      lastDate: DateTime(2100),
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
    if (_status == ClientPaymentStatus.paid &&
        (widget.branchId == null || widget.branchId!.isEmpty)) {
      setState(() => _error = 'Сначала укажите филиал в карточке ученика.');
      return;
    }
    final amount = parsePaymentMinor(_amountController.text)!;
    final occurredAt = DateTime(_date.year, _date.month, _date.day, 12).toUtc();
    final submission = ClientPaymentSubmission(
      identity: _identity,
      input: CreateClientPaymentRecordInput(
        issuedSubscriptionId: _subscriptionId,
        amountMinor: amount,
        status: _status,
        method: _status == ClientPaymentStatus.paid ? _method : null,
        occurredAt: _status == ClientPaymentStatus.paid ? occurredAt : null,
        dueAt: _status == ClientPaymentStatus.paid ? null : occurredAt,
        currencyCode: 'RUB',
        branchId: _status == ClientPaymentStatus.paid ? widget.branchId : null,
        verificationNote: _commentController.text,
        externalIdentifier: _status == ClientPaymentStatus.paid
            ? _invoiceController.text
            : null,
        reason: _reasonController.text,
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
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось проверить оплату.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amount = parsePaymentMinor(_amountController.text) ?? BigInt.zero;
    final after =
        widget.balanceMinor +
        (_status == ClientPaymentStatus.paid ? amount : BigInt.zero);
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
                          labelText: 'Дата оплаты или срока',
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
                      menuMaxHeight: 256,
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
                      onChanged: _busy || _status != ClientPaymentStatus.paid
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _method = value);
                              _changed();
                            },
                    ),
                    DropdownButtonFormField<ClientPaymentStatus>(
                      menuMaxHeight: 256,
                      key: const Key('payment-status'),
                      isExpanded: true,
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Статус',
                        prefixIcon: Icon(Icons.verified_outlined),
                      ),
                      items: ClientPaymentStatus.values
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(
                                clientPaymentStatusLabel(status.apiValue),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _status = value);
                              _changed();
                            },
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
                menuMaxHeight: 256,
                key: const Key('payment-subscription'),
                initialValue: _subscriptionId,
                decoration: const InputDecoration(
                  labelText: 'Погашаемое обязательство',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Без привязки к абонементу'),
                  ),
                  ..._activeSubscriptions.map(
                    (subscription) => DropdownMenuItem<String>(
                      value: subscription.id,
                      child: Text(subscription.terms.displayName),
                    ),
                  ),
                ],
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
                validator: (value) =>
                    _status == ClientPaymentStatus.paid &&
                        (value ?? '').trim().isEmpty
                    ? 'Для оплаченной операции укажите номер'
                    : null,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(
                  labelText: 'Номер счёта или чека',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextFormField(
                key: const Key('payment-reason'),
                controller: _reasonController,
                enabled: !_busy,
                maxLength: 500,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Укажите причину добавления оплаты'
                    : null,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(
                  labelText: 'Причина *',
                  prefixIcon: Icon(Icons.history_edu_outlined),
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
                    Text(
                      _status == ClientPaymentStatus.paid
                          ? 'Оплата: +${formatPaymentMinor(amount)}'
                          : 'До подтверждения: ${formatPaymentMinor(amount)}',
                    ),
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

String clientPaymentStatusLabel(Object? raw) => switch (raw?.toString()) {
  'unpaid' => 'Не оплачен',
  'posted_pending' => 'Проведён, ожидает подтверждения',
  'paid' => 'Оплачен',
  _ => 'Статус не указан',
};

Future<void> _popPaymentSheet<T>(BuildContext context, T result) async {
  FocusManager.instance.primaryFocus?.unfocus();
  for (
    var frame = 0;
    frame < 30 &&
        context.mounted &&
        MediaQuery.viewInsetsOf(context).bottom > 0;
    frame++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  if (context.mounted) Navigator.pop(context, result);
}

Future<bool?> showClientPaymentTransitionSheet(
  BuildContext context, {
  required CommerceMovement payment,
  required ClientPaymentStatus targetStatus,
  required String? branchId,
  required Future<void> Function(ClientPaymentTransitionSubmission submission)
  onSubmit,
}) {
  return showMagicSheet<bool>(
    context,
    title: clientPaymentStatusLabel(targetStatus.apiValue),
    subtitle: 'Изменение статуса оплаты фиксируется в истории',
    icon: Icons.sync_alt_rounded,
    builder: (_) => _ClientPaymentTransitionForm(
      payment: payment,
      targetStatus: targetStatus,
      branchId: branchId,
      onSubmit: onSubmit,
    ),
  );
}

class _ClientPaymentTransitionForm extends StatefulWidget {
  const _ClientPaymentTransitionForm({
    required this.payment,
    required this.targetStatus,
    required this.branchId,
    required this.onSubmit,
  });

  final CommerceMovement payment;
  final ClientPaymentStatus targetStatus;
  final String? branchId;
  final Future<void> Function(ClientPaymentTransitionSubmission submission)
  onSubmit;

  @override
  State<_ClientPaymentTransitionForm> createState() =>
      _ClientPaymentTransitionFormState();
}

class _ClientPaymentTransitionFormState
    extends State<_ClientPaymentTransitionForm> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _identifier = TextEditingController();
  final _note = TextEditingController();
  final _identity = MagicMutationIdentity.create('payment-status');
  SubscriptionPaymentMethod _method = SubscriptionPaymentMethod.cashless;
  late DateTime _date;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    _identifier.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final version = widget.payment.paymentRecordVersion;
    if (version == null) {
      setState(() => _error = 'Обновите карточку: версия оплаты не получена.');
      return;
    }
    final paid = widget.targetStatus == ClientPaymentStatus.paid;
    if (paid && (widget.branchId == null || widget.branchId!.isEmpty)) {
      setState(() => _error = 'Сначала укажите филиал ученика.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        ClientPaymentTransitionSubmission(
          identity: _identity,
          input: TransitionClientPaymentRecordInput(
            expectedVersion: version,
            targetStatus: widget.targetStatus,
            reason: _reason.text,
            method: paid ? _method : null,
            externalIdentifier: paid ? _identifier.text : null,
            occurredAt: paid
                ? DateTime(_date.year, _date.month, _date.day, 12).toUtc()
                : null,
            branchId: paid ? widget.branchId : null,
            verificationNote: _note.text,
          ),
        ),
      );
      if (mounted) {
        await _popPaymentSheet(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = userErrorMessage(
            error,
            fallback: 'Не удалось проверить изменение.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = widget.targetStatus == ClientPaymentStatus.paid;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${formatPaymentMinor(widget.payment.amountMinor)} · '
            '${clientPaymentStatusLabel(widget.payment.status)} → '
            '${clientPaymentStatusLabel(widget.targetStatus.apiValue)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            key: const Key('payment-transition-reason'),
            controller: _reason,
            maxLength: 500,
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Укажите причину изменения статуса'
                : null,
            decoration: const InputDecoration(labelText: 'Причина *'),
          ),
          if (paid) ...[
            const SizedBox(height: AppSpace.sm),
            DropdownButtonFormField<SubscriptionPaymentMethod>(
              menuMaxHeight: 256,
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Способ оплаты'),
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
                  : (value) => setState(() {
                      if (value != null) _method = value;
                    }),
            ),
            const SizedBox(height: AppSpace.sm),
            TextFormField(
              key: const Key('payment-transition-identifier'),
              controller: _identifier,
              maxLength: 120,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Укажите номер операции или чека'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Номер операции или чека *',
              ),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          TextFormField(
            controller: _note,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Пометка для проверки',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _popPaymentSheet(context, false);
                        },
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('payment-transition-submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Сохраняем…' : 'Изменить статус'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<bool?> showClientPaymentReversalSheet(
  BuildContext context, {
  required PaymentReversalPreview preview,
  required Future<void> Function(ClientPaymentReversalSubmission submission)
  onSubmit,
}) {
  return showMagicSheet<bool>(
    context,
    title: preview.operation == 'monetary_reversal'
        ? 'Удалить оплату и вернуть сумму'
        : 'Удалить запись оплаты',
    subtitle:
        'Операция исчезнет из обычной статистики, но останется в техистории',
    icon: Icons.delete_outline_rounded,
    builder: (_) =>
        _ClientPaymentReversalForm(preview: preview, onSubmit: onSubmit),
  );
}

class _ClientPaymentReversalForm extends StatefulWidget {
  const _ClientPaymentReversalForm({
    required this.preview,
    required this.onSubmit,
  });

  final PaymentReversalPreview preview;
  final Future<void> Function(ClientPaymentReversalSubmission submission)
  onSubmit;

  @override
  State<_ClientPaymentReversalForm> createState() =>
      _ClientPaymentReversalFormState();
}

class _ClientPaymentReversalFormState
    extends State<_ClientPaymentReversalForm> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _identity = MagicMutationIdentity.create('payment-reversal');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        ClientPaymentReversalSubmission(
          reason: _reason.text,
          identity: _identity,
        ),
      );
      if (mounted) {
        await _popPaymentSheet(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = userErrorMessage(
            error,
            fallback: 'Не удалось проверить исправление.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Сумма: ${formatPaymentMinor(widget.preview.amountMinor)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (widget.preview.operation == 'monetary_reversal')
            Text(
              'Личный счёт: ${formatPaymentMinor(widget.preview.walletBalanceMinor)} '
              '→ ${formatPaymentMinor(widget.preview.resultingBalanceMinor)}',
            ),
          if (widget.preview.negativeBalanceWarning)
            Text(
              'После возврата баланс станет отрицательным.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            key: const Key('payment-reversal-reason'),
            controller: _reason,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Укажите причину удаления оплаты'
                : null,
            decoration: const InputDecoration(labelText: 'Причина *'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _popPaymentSheet(context, false);
                        },
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('payment-reversal-submit'),
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(_busy ? 'Удаляем…' : 'Удалить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<bool?> showClientAccountAdjustmentReversalSheet(
  BuildContext context, {
  required AccountAdjustmentReversalPreview preview,
  required Future<void> Function(ClientPaymentReversalSubmission submission)
  onSubmit,
}) {
  return showMagicSheet<bool>(
    context,
    title: 'Сторнировать возврат или корректировку',
    subtitle:
        'Обе неизменяемые записи останутся в технической истории и не попадут в обычную статистику',
    icon: Icons.settings_backup_restore_rounded,
    builder: (_) => _ClientAccountAdjustmentReversalForm(
      preview: preview,
      onSubmit: onSubmit,
    ),
  );
}

class _ClientAccountAdjustmentReversalForm extends StatefulWidget {
  const _ClientAccountAdjustmentReversalForm({
    required this.preview,
    required this.onSubmit,
  });

  final AccountAdjustmentReversalPreview preview;
  final Future<void> Function(ClientPaymentReversalSubmission submission)
  onSubmit;

  @override
  State<_ClientAccountAdjustmentReversalForm> createState() =>
      _ClientAccountAdjustmentReversalFormState();
}

class _ClientAccountAdjustmentReversalFormState
    extends State<_ClientAccountAdjustmentReversalForm> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _identity = MagicMutationIdentity.create('adjustment-reversal');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        ClientPaymentReversalSubmission(
          reason: _reason.text,
          identity: _identity,
        ),
      );
      if (mounted) await _popPaymentSheet(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось проверить отмену.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${preview.kind == 'refund' ? 'Возврат' : 'Корректировка'}: '
            '${formatPaymentMinor(preview.amountMinor.abs())}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            'Личный счёт: ${formatPaymentMinor(preview.walletBalanceMinor)} '
            '→ ${formatPaymentMinor(preview.resultingBalanceMinor)}',
          ),
          if (preview.negativeBalanceWarning)
            Text(
              'После сторно баланс станет отрицательным.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            key: const Key('adjustment-reversal-reason'),
            controller: _reason,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Укажите причину сторно' : null,
            decoration: const InputDecoration(labelText: 'Причина *'),
          ),
          if (_error != null)
            Text(
              _error!,
              key: const Key('adjustment-reversal-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async => _popPaymentSheet(context, false),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('adjustment-reversal-submit'),
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(_busy ? 'Сторнируем…' : 'Сторнировать'),
                ),
              ),
            ],
          ),
        ],
      ),
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
      sourcePaymentId: widget.payment.sourcePaymentId ?? widget.payment.id,
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
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось сохранить исправление.',
        );
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
                menuMaxHeight: 256,
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
                  menuMaxHeight: 256,
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
