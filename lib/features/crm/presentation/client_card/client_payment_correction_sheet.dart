import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

class ClientPaymentCorrectionDraft {
  const ClientPaymentCorrectionDraft({
    required this.input,
    required this.reason,
  });

  final PaymentCorrectionInput input;
  final String reason;
}

Future<ClientPaymentCorrectionDraft?> showClientPaymentCorrectionEditor(
  BuildContext context, {
  required CommerceMovement payment,
  required String? branchId,
}) {
  return showMagicSheet<ClientPaymentCorrectionDraft>(
    context,
    title: 'Изменить оплату',
    subtitle: 'Сначала проверьте новые данные и результат пересчёта',
    icon: Icons.edit_note_rounded,
    builder: (_) =>
        _ClientPaymentCorrectionEditor(payment: payment, branchId: branchId),
  );
}

class _ClientPaymentCorrectionEditor extends StatefulWidget {
  const _ClientPaymentCorrectionEditor({
    required this.payment,
    required this.branchId,
  });

  final CommerceMovement payment;
  final String? branchId;

  @override
  State<_ClientPaymentCorrectionEditor> createState() =>
      _ClientPaymentCorrectionEditorState();
}

class _ClientPaymentCorrectionEditorState
    extends State<_ClientPaymentCorrectionEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _invoiceController;
  late final TextEditingController _commentController;
  final _reasonController = TextEditingController(
    text: 'Исправление данных оплаты',
  );
  late ClientPaymentStatus _status;
  late SubscriptionPaymentMethod _method;
  late DateTime _date;

  bool get _amountLocked => widget.payment.installmentId != null;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _minorForInput(widget.payment.amountMinor),
    );
    _invoiceController = TextEditingController(
      text: widget.payment.invoiceIdentifier ?? '',
    );
    _commentController = TextEditingController(
      text: widget.payment.comment ?? '',
    );
    _status = ClientPaymentStatus.values.firstWhere(
      (item) => item.apiValue == widget.payment.status,
      orElse: () => ClientPaymentStatus.postedPending,
    );
    _method = widget.payment.method == 'cash'
        ? SubscriptionPaymentMethod.cash
        : SubscriptionPaymentMethod.cashless;
    final sourceDate = widget.payment.dueAt ?? widget.payment.occurredAt;
    final local = sourceDate.toLocal();
    _date = DateTime(local.year, local.month, local.day);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _invoiceController.dispose();
    _commentController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ru'),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = _parseMinor(_amountController.text)!;
    final date = DateTime(_date.year, _date.month, _date.day, 12).toUtc();
    Navigator.pop(
      context,
      ClientPaymentCorrectionDraft(
        reason: _reasonController.text.trim(),
        input: PaymentCorrectionInput(
          expectedVersion: widget.payment.paymentRecordVersion!,
          amountMinor: amount,
          status: _status,
          dueAt: _status == ClientPaymentStatus.paid ? null : date,
          method: _status == ClientPaymentStatus.paid ? _method : null,
          externalIdentifier: _status == ClientPaymentStatus.paid
              ? _invoiceController.text
              : null,
          occurredAt: _status == ClientPaymentStatus.paid ? date : null,
          branchId: _status == ClientPaymentStatus.paid
              ? widget.branchId
              : null,
          verificationNote: _commentController.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paid = _status == ClientPaymentStatus.paid;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('payment-correction-amount'),
            controller: _amountController,
            enabled: !_amountLocked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            validator: (raw) {
              final value = _parseMinor(raw ?? '');
              return value == null || value <= BigInt.zero
                  ? 'Введите положительную сумму'
                  : null;
            },
            decoration: InputDecoration(
              labelText: 'Сумма, ₽',
              helperText: _amountLocked
                  ? 'Сумма части рассрочки меняется через абонемент'
                  : null,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<ClientPaymentStatus>(
            menuMaxHeight: 256,
            key: const Key('payment-correction-status'),
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Статус'),
            items: ClientPaymentStatus.values
                .map(
                  (status) => DropdownMenuItem(
                    value: status,
                    child: Text(_statusLabel(status)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          const SizedBox(height: AppSpace.md),
          InkWell(
            key: const Key('payment-correction-date'),
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: paid ? 'Дата оплаты' : 'Срок оплаты',
                prefixIcon: const Icon(Icons.calendar_today_rounded),
              ),
              child: Text(DateFormat('dd.MM.yyyy').format(_date)),
            ),
          ),
          if (paid) ...[
            const SizedBox(height: AppSpace.md),
            DropdownButtonFormField<SubscriptionPaymentMethod>(
              menuMaxHeight: 256,
              key: const Key('payment-correction-method'),
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
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const Key('payment-correction-invoice'),
              controller: _invoiceController,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Укажите номер операции или чека'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Номер операции или чека',
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          TextFormField(
            key: const Key('payment-correction-comment'),
            controller: _commentController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Комментарий'),
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            key: const Key('payment-correction-reason'),
            controller: _reasonController,
            maxLength: 500,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Укажите причину исправления'
                : null,
            decoration: const InputDecoration(labelText: 'Причина *'),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('payment-correction-preview'),
                onPressed: _submit,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Рассчитать'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<bool?> showClientPaymentCorrectionConfirmation(
  BuildContext context, {
  required PaymentCorrectionPreview preview,
  required String reason,
  required Future<void> Function(MagicMutationIdentity identity) onConfirm,
}) {
  return showMagicSheet<bool>(
    context,
    title: 'Подтвердите исправление',
    subtitle: 'Старая запись останется в технической истории',
    icon: Icons.calculate_rounded,
    builder: (_) => _PaymentCorrectionConfirmation(
      preview: preview,
      reason: reason,
      onConfirm: onConfirm,
    ),
  );
}

class _PaymentCorrectionConfirmation extends StatefulWidget {
  const _PaymentCorrectionConfirmation({
    required this.preview,
    required this.reason,
    required this.onConfirm,
  });

  final PaymentCorrectionPreview preview;
  final String reason;
  final Future<void> Function(MagicMutationIdentity identity) onConfirm;

  @override
  State<_PaymentCorrectionConfirmation> createState() =>
      _PaymentCorrectionConfirmationState();
}

class _PaymentCorrectionConfirmationState
    extends State<_PaymentCorrectionConfirmation> {
  late final MagicMutationIdentity _identity;
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _identity = MagicMutationIdentity.create('payment-correction');
  }

  Future<void> _submit() async {
    if (!_accepted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(_identity);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось исправить оплату.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final delta = preview.walletDeltaMinor;
    final deltaPrefix = delta > BigInt.zero ? '+' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CorrectionSummary(
          title: 'Было',
          values: preview.before,
          currencyCode: preview.currencyCode,
        ),
        const SizedBox(height: AppSpace.md),
        _CorrectionSummary(
          title: 'Станет',
          values: preview.after,
          currencyCode: preview.currencyCode,
        ),
        const SizedBox(height: AppSpace.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border.all(color: AppColor.divider),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Пересчёт личного счёта',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Изменение: $deltaPrefix${_money(delta, preview.currencyCode)}',
                ),
                Text(
                  'Новый остаток: ${_money(preview.resultingBalanceMinor, preview.currencyCode)}',
                ),
                if (preview.negativeBalanceWarning)
                  Text(
                    'После исправления остаток будет отрицательным.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text('Причина: ${widget.reason}'),
        CheckboxListTile(
          key: const Key('payment-correction-confirm'),
          contentPadding: EdgeInsets.zero,
          value: _accepted,
          onChanged: _busy
              ? null
              : (value) => setState(() => _accepted = value == true),
          title: const Text('Подтверждаю исправление и пересчёт'),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Назад'),
            ),
            const Spacer(),
            FilledButton(
              key: const Key('payment-correction-commit'),
              onPressed: _accepted && !_busy ? _submit : null,
              child: Text(_busy ? 'Сохраняем…' : 'Исправить оплату'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CorrectionSummary extends StatelessWidget {
  const _CorrectionSummary({
    required this.title,
    required this.values,
    required this.currencyCode,
  });

  final String title;
  final PaymentCorrectionValues values;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final date = values.status == ClientPaymentStatus.paid
        ? values.occurredAt
        : values.dueAt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColor.divider),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpace.xs),
            Text('Сумма: ${_money(values.amountMinor, currencyCode)}'),
            Text('Статус: ${_statusLabel(values.status)}'),
            if (date != null)
              Text('Дата: ${DateFormat('dd.MM.yyyy').format(date.toLocal())}'),
            if (values.method != null)
              Text(
                'Способ: ${values.method == SubscriptionPaymentMethod.cash ? 'Наличные' : 'Безналичная оплата'}',
              ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(ClientPaymentStatus status) => switch (status) {
  ClientPaymentStatus.unpaid => 'Долг',
  ClientPaymentStatus.postedPending => 'Ожидает подтверждения',
  ClientPaymentStatus.paid => 'Оплачено',
};

BigInt? _parseMinor(String raw) {
  final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  final value = num.tryParse(normalized);
  if (value == null) return null;
  return BigInt.from((value * 100).round());
}

String _minorForInput(BigInt value) {
  final whole = value ~/ BigInt.from(100);
  final fraction = (value.abs() % BigInt.from(100)).toString().padLeft(2, '0');
  return fraction == '00' ? whole.toString() : '$whole,$fraction';
}

String _money(BigInt value, String currencyCode) {
  final sign = value.isNegative ? '−' : '';
  final absolute = value.abs();
  final whole = absolute ~/ BigInt.from(100);
  final fraction = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
  final suffix = currencyCode == 'RUB' ? '₽' : currencyCode;
  return '$sign$whole,$fraction $suffix';
}
