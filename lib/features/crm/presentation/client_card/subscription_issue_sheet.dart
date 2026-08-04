import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'client_card_ui.dart';

enum SubscriptionIssueDiscountMode { none, percent, fixed }

class SubscriptionImmediatePaymentDraft {
  const SubscriptionImmediatePaymentDraft({
    required this.amountMinor,
    required this.method,
    required this.occurredAt,
    required this.currencyCode,
    required this.identity,
  });

  final BigInt amountMinor;
  final SubscriptionPaymentMethod method;
  final DateTime occurredAt;
  final String currencyCode;
  final MagicMutationIdentity identity;

  RecordSubscriptionPaymentInput toInput({
    required String issuedSubscriptionId,
  }) {
    return RecordSubscriptionPaymentInput(
      issuedSubscriptionId: issuedSubscriptionId,
      amountMinor: amountMinor,
      method: method,
      occurredAt: occurredAt,
      currencyCode: currencyCode,
    );
  }
}

/// Immutable command assembled by the issue form.
///
/// Both identities and [SubscriptionImmediatePaymentDraft.occurredAt] live for
/// the lifetime of the form. After the first request the fields are frozen, so
/// tapping «Повторить» sends exactly the same fingerprints to both endpoints.
class SubscriptionIssueSubmission {
  const SubscriptionIssueSubmission({
    required this.issue,
    required this.issueIdentity,
    this.payment,
  });

  final IssueSubscriptionInput issue;
  final MagicMutationIdentity issueIdentity;
  final SubscriptionImmediatePaymentDraft? payment;
}

typedef SubscriptionIssueSubmit =
    Future<void> Function(SubscriptionIssueSubmission submission);

Future<bool?> showSubscriptionIssueFormSheet(
  BuildContext context, {
  required Map<String, dynamic> package,
  required SubscriptionIssueSubmit onSubmit,
}) {
  return showMagicSheet<bool>(
    context,
    title: 'Условия абонемента',
    subtitle: package['name']?.toString() ?? 'Настройте выдачу',
    icon: Icons.receipt_long_rounded,
    builder: (_) => SubscriptionIssueForm(package: package, onSubmit: onSubmit),
  );
}

class SubscriptionIssueForm extends StatefulWidget {
  const SubscriptionIssueForm({
    super.key,
    required this.package,
    required this.onSubmit,
    this.commandTimestamp,
  });

  final Map<String, dynamic> package;
  final SubscriptionIssueSubmit onSubmit;

  /// Test seam; production commands use the instant at which the form opens.
  final DateTime? commandTimestamp;

  @override
  State<SubscriptionIssueForm> createState() => _SubscriptionIssueFormState();
}

class _SubscriptionIssueFormState extends State<SubscriptionIssueForm> {
  final _formKey = GlobalKey<FormState>();
  final _discountValueController = TextEditingController();
  final _discountReasonController = TextEditingController();
  final _paymentAmountController = TextEditingController();
  final _surchargeAmountController = TextEditingController();
  final _surchargeReasonController = TextEditingController();

  late final BigInt _basePriceMinor;
  late final String _currencyCode;
  late final DateTime _commandTimestamp;
  late final MagicMutationIdentity _issueIdentity;
  late final MagicMutationIdentity _paymentIdentity;
  late final DirtyFormExitController _exitController;

  SubscriptionIssueDiscountMode _discountMode =
      SubscriptionIssueDiscountMode.none;
  SubscriptionPaymentMethod _paymentMethod = SubscriptionPaymentMethod.cash;
  bool _useInstallments = false;
  bool _useSurcharge = false;
  bool _recordPayment = false;
  bool _paymentAmountTouched = false;
  int _installmentCount = 2;
  bool _busy = false;
  bool _attempted = false;
  String? _error;

  bool get _fieldsEnabled => !_attempted;

  @override
  void initState() {
    super.initState();
    _basePriceMinor = _packageBasePriceMinor(widget.package);
    _currencyCode =
        widget.package['currencyCode']?.toString().toUpperCase() ?? 'RUB';
    _commandTimestamp = (widget.commandTimestamp ?? DateTime.now()).toUtc();
    _issueIdentity = MagicMutationIdentity.create('subscription-issue');
    _paymentIdentity = MagicMutationIdentity.create('subscription-payment');
    _exitController = DirtyFormExitController(
      onSave: () => _submit(closeOnSuccess: false),
    );
    _paymentAmountController.text = _minorToInput(_basePriceMinor);
  }

  @override
  void dispose() {
    _discountValueController.dispose();
    _discountReasonController.dispose();
    _paymentAmountController.dispose();
    _surchargeAmountController.dispose();
    _surchargeReasonController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  int? get _percentBasisPoints =>
      _parsePercentBasisPoints(_discountValueController.text);

  BigInt? get _discountMinor {
    switch (_discountMode) {
      case SubscriptionIssueDiscountMode.none:
        return BigInt.zero;
      case SubscriptionIssueDiscountMode.percent:
        final basisPoints = _percentBasisPoints;
        if (basisPoints == null || basisPoints < 1 || basisPoints > 10000) {
          return null;
        }
        // PostgreSQL parity: round(base_minor * basis_points / 10000),
        // half-up. All values are non-negative.
        return (_basePriceMinor * BigInt.from(basisPoints) +
                BigInt.from(5000)) ~/
            BigInt.from(10000);
      case SubscriptionIssueDiscountMode.fixed:
        final fixed = _parseMoneyMinor(_discountValueController.text);
        if (fixed == null || fixed <= BigInt.zero || fixed > _basePriceMinor) {
          return null;
        }
        return fixed;
    }
  }

  BigInt? get _finalPriceMinor {
    final discount = _discountMinor;
    final surcharge = _surchargeMinor;
    return discount == null || surcharge == null
        ? null
        : _basePriceMinor - discount + surcharge;
  }

  BigInt? get _surchargeMinor {
    if (!_useSurcharge) return BigInt.zero;
    final value = _parseMoneyMinor(_surchargeAmountController.text);
    return value == null || value <= BigInt.zero ? null : value;
  }

  void _selectDiscountMode(SubscriptionIssueDiscountMode mode) {
    if (!_fieldsEnabled || _discountMode == mode) return;
    setState(() {
      _discountMode = mode;
      _discountValueController.clear();
      _error = null;
      _syncUntouchedPaymentAmount();
    });
    _exitController.markDirty();
  }

  void _pricingChanged() {
    if (!_fieldsEnabled) return;
    setState(() {
      _error = null;
      _syncUntouchedPaymentAmount();
    });
  }

  void _syncUntouchedPaymentAmount() {
    if (_paymentAmountTouched) return;
    final finalPrice = _finalPriceMinor;
    if (finalPrice != null) {
      _paymentAmountController.text = _minorToInput(finalPrice);
    }
  }

  String? _validateDiscountValue(String? raw) {
    if (_discountMode == SubscriptionIssueDiscountMode.none) return null;
    if ((raw ?? '').trim().isEmpty) return 'Укажите размер скидки';

    if (_discountMode == SubscriptionIssueDiscountMode.percent) {
      final basisPoints = _parsePercentBasisPoints(raw!);
      if (basisPoints == null) return 'Не более двух знаков после запятой';
      if (basisPoints < 1 || basisPoints > 10000) {
        return 'Допустимо от 0,01% до 100%';
      }
      return null;
    }

    final fixed = _parseMoneyMinor(raw!);
    if (fixed == null || fixed <= BigInt.zero) {
      return 'Введите положительную сумму';
    }
    if (fixed > _basePriceMinor) {
      return 'Скидка не может превышать стоимость';
    }
    return null;
  }

  String? _validateReason(String? raw) {
    if (_discountMode == SubscriptionIssueDiscountMode.none) return null;
    return (raw ?? '').trim().isEmpty ? 'Укажите причину скидки' : null;
  }

  String? _validatePaymentAmount(String? raw) {
    if (!_recordPayment) return null;
    final amount = _parseMoneyMinor(raw ?? '');
    if (amount == null || amount <= BigInt.zero) {
      return 'Введите положительную сумму';
    }
    final finalPrice = _finalPriceMinor;
    if (finalPrice != null && amount > finalPrice) {
      return 'Оплата не может превышать итог';
    }
    return null;
  }

  String? _validateSurchargeAmount(String? raw) {
    if (!_useSurcharge) return null;
    final amount = _parseMoneyMinor(raw ?? '');
    return amount == null || amount <= BigInt.zero
        ? 'Введите положительную сумму'
        : null;
  }

  String? _validateSurchargeReason(String? raw) {
    if (!_useSurcharge) return null;
    return (raw ?? '').trim().isEmpty ? 'Укажите причину доплаты' : null;
  }

  List<SubscriptionInstallmentInput> _installments(BigInt finalPrice) {
    if (!_useInstallments) return const <SubscriptionInstallmentInput>[];
    final count = _installmentCount;
    final equalPart = finalPrice ~/ BigInt.from(count);
    final remainder = (finalPrice % BigInt.from(count)).toInt();
    return List<SubscriptionInstallmentInput>.generate(count, (index) {
      return SubscriptionInstallmentInput(
        dueAt: _addUtcMonths(_commandTimestamp, index),
        amountMinor: equalPart + (index < remainder ? BigInt.one : BigInt.zero),
      );
    }, growable: false);
  }

  SubscriptionIssueSubmission _buildSubmission(BigInt finalPrice) {
    SubscriptionDiscountInput? discount;
    switch (_discountMode) {
      case SubscriptionIssueDiscountMode.none:
        break;
      case SubscriptionIssueDiscountMode.percent:
        discount = SubscriptionDiscountInput.percent(
          basisPoints: _percentBasisPoints!,
          reason: _discountReasonController.text,
        );
        break;
      case SubscriptionIssueDiscountMode.fixed:
        discount = SubscriptionDiscountInput.fixed(
          fixedMinor: _discountMinor!,
          reason: _discountReasonController.text,
        );
        break;
    }

    final payment = _recordPayment
        ? SubscriptionImmediatePaymentDraft(
            amountMinor: _parseMoneyMinor(_paymentAmountController.text)!,
            method: _paymentMethod,
            occurredAt: _commandTimestamp,
            currencyCode: _currencyCode,
            identity: _paymentIdentity,
          )
        : null;

    return SubscriptionIssueSubmission(
      issue: IssueSubscriptionInput(
        packageId: widget.package['id'].toString(),
        discount: discount,
        installments: _installments(finalPrice),
        paymentMethod: payment?.method,
        surcharge: _useSurcharge
            ? SubscriptionSurchargeInput(
                amountMinor: _surchargeMinor!,
                reason: _surchargeReasonController.text,
              )
            : null,
      ),
      issueIdentity: _issueIdentity,
      payment: payment,
    );
  }

  Future<bool> _submit({bool closeOnSuccess = true}) async {
    if (_busy) return false;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return false;

    final finalPrice = _finalPriceMinor;
    if (finalPrice == null || finalPrice < BigInt.zero) return false;
    if (_useInstallments && finalPrice < BigInt.from(_installmentCount)) {
      setState(() {
        _error =
            'Итог должен позволять $_installmentCount положительных платежа.';
      });
      return false;
    }

    final submission = _buildSubmission(finalPrice);
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    _exitController.setBusy(true);
    try {
      await widget.onSubmit(submission);
      _exitController.setBusy(false);
      _exitController.markClean();
      if (closeOnSuccess && mounted) Navigator.pop(context, true);
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _busy = false;
        _error = '$error';
      });
      _exitController.setBusy(false);
      return false;
    }
  }

  void _requestClose() {
    _exitController.requestExit(
      context,
      reason: DirtyFormExitReason.appBack,
      savedResult: true,
      discardedResult: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final finalPrice = _finalPriceMinor;
    final discount = _discountMinor;
    final surcharge = _surchargeMinor;
    final installmentItems = finalPrice == null
        ? const <SubscriptionInstallmentInput>[]
        : _installments(finalPrice);

    return DirtyFormExitScope(
      controller: _exitController,
      savedResult: true,
      discardedResult: false,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: _exitController.markDirty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PriceSummary(
              packageName: widget.package['name']?.toString() ?? 'Абонемент',
              basePriceMinor: _basePriceMinor,
              discountMinor: discount,
              surchargeMinor: surcharge,
              finalPriceMinor: finalPrice,
              currencyCode: _currencyCode,
            ),
            const SizedBox(height: AppSpace.lg),
            const _SectionTitle('Скидка'),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                _ModeChip(
                  key: const Key('subscription-discount-none'),
                  label: 'Без скидки',
                  selected: _discountMode == SubscriptionIssueDiscountMode.none,
                  enabled: _fieldsEnabled,
                  onSelected: () =>
                      _selectDiscountMode(SubscriptionIssueDiscountMode.none),
                ),
                _ModeChip(
                  key: const Key('subscription-discount-percent'),
                  label: 'Процент',
                  selected:
                      _discountMode == SubscriptionIssueDiscountMode.percent,
                  enabled: _fieldsEnabled,
                  onSelected: () => _selectDiscountMode(
                    SubscriptionIssueDiscountMode.percent,
                  ),
                ),
                _ModeChip(
                  key: const Key('subscription-discount-fixed'),
                  label: 'Сумма',
                  selected:
                      _discountMode == SubscriptionIssueDiscountMode.fixed,
                  enabled: _fieldsEnabled,
                  onSelected: () =>
                      _selectDiscountMode(SubscriptionIssueDiscountMode.fixed),
                ),
              ],
            ),
            if (_discountMode != SubscriptionIssueDiscountMode.none) ...[
              const SizedBox(height: AppSpace.md),
              _AdaptivePair(
                first: TextFormField(
                  key: const Key('subscription-discount-value'),
                  controller: _discountValueController,
                  enabled: _fieldsEnabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: clientCardInputDecoration(
                    Theme.of(context).colorScheme,
                    label:
                        _discountMode == SubscriptionIssueDiscountMode.percent
                        ? 'Скидка, %'
                        : 'Скидка, ₽',
                    isDense: true,
                  ),
                  validator: _validateDiscountValue,
                  onChanged: (_) => _pricingChanged(),
                ),
                second: TextFormField(
                  key: const Key('subscription-discount-reason'),
                  controller: _discountReasonController,
                  enabled: _fieldsEnabled,
                  maxLength: 500,
                  decoration: clientCardInputDecoration(
                    Theme.of(context).colorScheme,
                    label: 'Причина',
                    hint: 'Например: семейная скидка',
                    isDense: true,
                  ),
                  validator: _validateReason,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            _OptionCard(
              key: const Key('subscription-surcharge-toggle'),
              icon: Icons.add_circle_outline_rounded,
              title: 'Доплата',
              subtitle: 'Добавить обоснованную сумму к стоимости абонемента',
              value: _useSurcharge,
              enabled: _fieldsEnabled,
              onChanged: (value) => setState(() {
                _useSurcharge = value;
                _error = null;
                _syncUntouchedPaymentAmount();
                _exitController.markDirty();
              }),
            ),
            if (_useSurcharge) ...[
              const SizedBox(height: AppSpace.md),
              _AdaptivePair(
                first: TextFormField(
                  key: const Key('subscription-surcharge-amount'),
                  controller: _surchargeAmountController,
                  enabled: _fieldsEnabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: clientCardInputDecoration(
                    Theme.of(context).colorScheme,
                    label: 'Доплата, ₽',
                    isDense: true,
                  ),
                  validator: _validateSurchargeAmount,
                  onChanged: (_) => _pricingChanged(),
                ),
                second: TextFormField(
                  key: const Key('subscription-surcharge-reason'),
                  controller: _surchargeReasonController,
                  enabled: _fieldsEnabled,
                  maxLength: 500,
                  decoration: clientCardInputDecoration(
                    Theme.of(context).colorScheme,
                    label: 'Причина доплаты',
                    hint: 'Например: дополнительное занятие',
                    isDense: true,
                  ),
                  validator: _validateSurchargeReason,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
            ],
            const SizedBox(height: AppSpace.xl),
            _OptionCard(
              key: const Key('subscription-installments-toggle'),
              icon: Icons.calendar_view_month_rounded,
              title: 'Рассрочка',
              subtitle: 'Разделить итог на равные ежемесячные обязательства',
              value: _useInstallments,
              enabled:
                  _fieldsEnabled &&
                  finalPrice != null &&
                  finalPrice > BigInt.zero,
              onChanged: (value) => setState(() {
                _useInstallments = value;
                _error = null;
                _exitController.markDirty();
              }),
            ),
            if (_useInstallments) ...[
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<int>(
                key: const Key('subscription-installment-count'),
                initialValue: _installmentCount,
                decoration: clientCardInputDecoration(
                  Theme.of(context).colorScheme,
                  label: 'Количество платежей',
                  isDense: true,
                ),
                items: [
                  for (var count = 2; count <= 12; count++)
                    DropdownMenuItem(value: count, child: Text('$count')),
                ],
                onChanged: _fieldsEnabled
                    ? (value) => setState(() {
                        _installmentCount = value ?? 2;
                        _error = null;
                        _exitController.markDirty();
                      })
                    : null,
              ),
              if (installmentItems.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                _InstallmentPreview(
                  installments: installmentItems,
                  currencyCode: _currencyCode,
                ),
              ],
            ],
            const SizedBox(height: AppSpace.md),
            _OptionCard(
              key: const Key('subscription-payment-toggle'),
              icon: Icons.payments_outlined,
              title: 'Внести оплату сейчас',
              subtitle: 'Оплата будет записана отдельным финансовым фактом',
              value: _recordPayment,
              enabled:
                  _fieldsEnabled &&
                  finalPrice != null &&
                  finalPrice > BigInt.zero,
              onChanged: (value) => setState(() {
                _recordPayment = value;
                _error = null;
                _exitController.markDirty();
                if (value && !_paymentAmountTouched) {
                  _syncUntouchedPaymentAmount();
                }
              }),
            ),
            if (_recordPayment) ...[
              const SizedBox(height: AppSpace.md),
              _AdaptivePair(
                first: TextFormField(
                  key: const Key('subscription-payment-amount'),
                  controller: _paymentAmountController,
                  enabled: _fieldsEnabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: clientCardInputDecoration(
                    Theme.of(context).colorScheme,
                    label: 'Сумма оплаты, ₽',
                    helperText: 'Можно внести часть итога',
                    isDense: true,
                  ),
                  validator: _validatePaymentAmount,
                  onChanged: (_) {
                    _paymentAmountTouched = true;
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                second: _PaymentMethodPicker(
                  method: _paymentMethod,
                  enabled: _fieldsEnabled,
                  onChanged: (method) => setState(() {
                    _paymentMethod = method;
                    _error = null;
                    _exitController.markDirty();
                  }),
                ),
              ),
            ],
            if (_attempted) ...[
              const SizedBox(height: AppSpace.md),
              const _RetryNotice(),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpace.md),
              _InlineError(error: _error!),
            ],
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                Expanded(
                  child: clientCardGhostButton(
                    'Отмена',
                    _busy ? null : _requestClose,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: FilledButton(
                    key: const Key('subscription-issue-submit'),
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.gold,
                      foregroundColor: AppColor.onGold,
                      disabledBackgroundColor: AppColor.goldSoft,
                      disabledForegroundColor: AppColor.text2,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColor.onGold,
                            ),
                          )
                        : Text(_attempted ? 'Повторить' : 'Выдать'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  const _PriceSummary({
    required this.packageName,
    required this.basePriceMinor,
    required this.discountMinor,
    required this.surchargeMinor,
    required this.finalPriceMinor,
    required this.currencyCode,
  });

  final String packageName;
  final BigInt basePriceMinor;
  final BigInt? discountMinor;
  final BigInt? surchargeMinor;
  final BigInt? finalPriceMinor;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.input,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            packageName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColor.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          _PriceLine(
            label: 'Базовая сумма',
            value: _formatMinor(basePriceMinor, currencyCode),
          ),
          _PriceLine(
            label: 'Скидка',
            value: discountMinor == null
                ? '—'
                : '−${_formatMinor(discountMinor!, currencyCode)}',
          ),
          _PriceLine(
            label: 'Доплата',
            value: surchargeMinor == null || surchargeMinor == BigInt.zero
                ? '—'
                : '+${_formatMinor(surchargeMinor!, currencyCode)}',
          ),
          const Divider(height: AppSpace.lg, color: AppColor.divider),
          _PriceLine(
            key: const Key('subscription-issue-final'),
            label: 'Итого',
            value: finalPriceMinor == null
                ? '—'
                : _formatMinor(finalPriceMinor!, currencyCode),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: emphasized ? AppColor.text : AppColor.text2,
      fontSize: emphasized ? 15 : 12.5,
      fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColor.text,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled ? (_) => onSelected() : null,
      selectedColor: AppColor.goldSoft,
      side: BorderSide(color: selected ? AppColor.goldLine : AppColor.divider),
      labelStyle: TextStyle(
        color: selected ? AppColor.gold2 : AppColor.text2,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: AppSpace.md),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: AppSpace.md),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColor.input,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: const BorderSide(color: AppColor.divider),
        ),
        secondary: Icon(icon, color: enabled ? AppColor.gold : AppColor.text2),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColor.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColor.text2, fontSize: 11.5),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: AppColor.gold,
      ),
    );
  }
}

class _InstallmentPreview extends StatelessWidget {
  const _InstallmentPreview({
    required this.installments,
    required this.currencyCode,
  });

  final List<SubscriptionInstallmentInput> installments;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscription-installment-preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.input,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.divider),
      ),
      child: Column(
        children: [
          for (var index = 0; index < installments.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == installments.length - 1 ? 0 : AppSpace.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${index + 1}. ${DateFormat('dd.MM.yyyy').format(installments[index].dueAt.toLocal())}',
                      style: const TextStyle(
                        color: AppColor.text2,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    _formatMinor(installments[index].amountMinor, currencyCode),
                    style: const TextStyle(
                      color: AppColor.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

class _PaymentMethodPicker extends StatelessWidget {
  const _PaymentMethodPicker({
    required this.method,
    required this.enabled,
    required this.onChanged,
  });

  final SubscriptionPaymentMethod method;
  final bool enabled;
  final ValueChanged<SubscriptionPaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: clientCardInputDecoration(
        Theme.of(context).colorScheme,
        label: 'Способ оплаты',
        isDense: true,
      ),
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        children: [
          _ModeChip(
            key: const Key('subscription-payment-cash'),
            label: 'Наличные',
            selected: method == SubscriptionPaymentMethod.cash,
            enabled: enabled,
            onSelected: () => onChanged(SubscriptionPaymentMethod.cash),
          ),
          _ModeChip(
            key: const Key('subscription-payment-cashless'),
            label: 'Безнал',
            selected: method == SubscriptionPaymentMethod.cashless,
            enabled: enabled,
            onSelected: () => onChanged(SubscriptionPaymentMethod.cashless),
          ),
        ],
      ),
    );
  }
}

class _RetryNotice extends StatelessWidget {
  const _RetryNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_outlined, size: 18, color: AppColor.gold),
          SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Условия зафиксированы. Повтор отправит ту же операцию и не '
              'создаст второй абонемент или платёж.',
              style: TextStyle(color: AppColor.text2, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscription-issue-error'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.danger.withValues(alpha: 0.5)),
      ),
      child: Text(
        error,
        style: const TextStyle(color: AppColor.menuDanger, fontSize: 12),
      ),
    );
  }
}

BigInt _packageBasePriceMinor(Map<String, dynamic> package) {
  final canonical = BigInt.tryParse(
    (package['basePriceMinor'] ?? package['base_price_minor'])?.toString() ??
        '',
  );
  if (canonical != null) return canonical;
  return _parseMoneyMinor(package['price']?.toString() ?? '') ?? BigInt.zero;
}

BigInt? _parseMoneyMinor(String raw) {
  final normalized = raw
      .trim()
      .replaceAll(RegExp(r'[\s\u00A0\u202F]'), '')
      .replaceAll(',', '.');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final whole = BigInt.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * BigInt.from(100) +
      BigInt.parse(fraction.isEmpty ? '0' : fraction);
}

int? _parsePercentBasisPoints(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final whole = int.tryParse(match.group(1)!);
  if (whole == null) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction.isEmpty ? '0' : fraction);
}

String _minorToInput(BigInt minor) {
  final whole = minor ~/ BigInt.from(100);
  final fraction = (minor % BigInt.from(100)).toInt();
  return fraction == 0
      ? whole.toString()
      : '${whole.toString()},${fraction.toString().padLeft(2, '0')}';
}

String _formatMinor(BigInt minor, String currencyCode) {
  final amount = minor.toInt() / 100;
  final formatted = NumberFormat('#,##0.##', 'ru').format(amount);
  final symbol = currencyCode == 'RUB' ? '₽' : currencyCode;
  return '$formatted $symbol';
}

DateTime _addUtcMonths(DateTime source, int months) {
  final utc = source.toUtc();
  final zeroBasedMonth = utc.month - 1 + months;
  final year = utc.year + zeroBasedMonth ~/ 12;
  final month = zeroBasedMonth % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = utc.day > lastDay ? lastDay : utc.day;
  return DateTime.utc(
    year,
    month,
    day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  );
}
