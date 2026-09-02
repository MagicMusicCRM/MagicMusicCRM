import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/models/subscription_purchase.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'client_card_ui.dart';
import 'subscription_issue_components.dart';
import 'subscription_issue_models.dart';

class SubscriptionIssuePaymentSection extends StatelessWidget {
  const SubscriptionIssuePaymentSection({
    super.key,
    required this.draft,
    required this.defaultPaymentMinor,
    required this.fieldsEnabled,
    required this.searchPayers,
    required this.selectPayer,
    required this.selectPaymentMethod,
    required this.selectFundingMode,
    required this.setStartsAt,
    required this.setExpiresAt,
    required this.setIndefinite,
    required this.setPaymentAmount,
    required this.setPaymentOccurredAt,
    required this.setPaymentComment,
    required this.validatePaymentAmount,
    required this.validateExpiresAt,
    required this.validatePurchaseReason,
    required this.setPurchaseReason,
    required this.acceptedByLabel,
    required this.onChanged,
  });

  final SubscriptionIssueDraft draft;
  final BigInt defaultPaymentMinor;
  final bool fieldsEnabled;
  final Future<List<SearchableSelectItem>> Function(String query) searchPayers;
  final ValueChanged<SearchableSelectItem> selectPayer;
  final ValueChanged<SubscriptionPaymentMethod> selectPaymentMethod;
  final ValueChanged<SubscriptionFundingMode> selectFundingMode;
  final ValueChanged<DateTime> setStartsAt;
  final ValueChanged<DateTime> setExpiresAt;
  final ValueChanged<bool> setIndefinite;
  final ValueChanged<String> setPaymentAmount;
  final ValueChanged<DateTime> setPaymentOccurredAt;
  final ValueChanged<String> setPaymentComment;
  final FormFieldValidator<String> validatePaymentAmount;
  final String? Function() validateExpiresAt;
  final FormFieldValidator<String> validatePurchaseReason;
  final ValueChanged<String> setPurchaseReason;
  final String acceptedByLabel;
  final VoidCallback onChanged;

  void _change(VoidCallback action) {
    action();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.lg),
        const SubscriptionIssueSectionTitle('Оплата абонемента'),
        const SizedBox(height: AppSpace.sm),
        CheckboxListTile(
          key: const ValueKey('subscription-indefinite'),
          title: const Text('Бессрочный'),
          value: draft.isIndefinite,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: fieldsEnabled
              ? (value) => _change(() => setIndefinite(value ?? true))
              : null,
        ),
        if (!draft.isIndefinite)
          _SubscriptionPeriodFields(
            draft: draft,
            fieldsEnabled: fieldsEnabled,
            setStartsAt: setStartsAt,
            setExpiresAt: setExpiresAt,
            validateExpiresAt: validateExpiresAt,
            onChanged: onChanged,
          ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const Key('subscription-accepted-by'),
          initialValue: acceptedByLabel,
          readOnly: true,
          decoration: clientCardInputDecoration(
            Theme.of(context).colorScheme,
            label: 'Принял',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SearchablePickerField(
          key: const Key('subscription-payer'),
          label: 'Плательщик',
          placeholder: 'Выберите ученика',
          hintText: 'Введите имя или ФИО ученика',
          selectedId: draft.payerStudentId,
          selectedLabel: draft.payerLabel,
          items: [
            SearchableSelectItem(
              id: draft.recipientStudentId,
              label: draft.recipientLabel,
              subtitle: 'Получатель абонемента',
            ),
          ],
          isNullable: false,
          enabled: fieldsEnabled,
          onSearch: searchPayers,
          onSelected: (item) {
            if (item != null) _change(() => selectPayer(item));
          },
        ),
        const SizedBox(height: AppSpace.md),
        _SubscriptionActualPaymentFields(
          draft: draft,
          defaultPaymentMinor: defaultPaymentMinor,
          fieldsEnabled: fieldsEnabled,
          setPaymentAmount: setPaymentAmount,
          setPaymentOccurredAt: setPaymentOccurredAt,
          setPaymentComment: setPaymentComment,
          selectPaymentMethod: selectPaymentMethod,
          validatePaymentAmount: validatePaymentAmount,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            SubscriptionIssueModeChip(
              key: const Key('subscription-funding-account'),
              label: 'Оплата',
              selected:
                  draft.fundingMode == SubscriptionFundingMode.personalAccount,
              enabled: fieldsEnabled,
              onSelected: () => _change(
                () =>
                    selectFundingMode(SubscriptionFundingMode.personalAccount),
              ),
            ),
            SubscriptionIssueModeChip(
              key: const Key('subscription-funding-installment'),
              label: 'Рассрочка',
              selected:
                  draft.fundingMode == SubscriptionFundingMode.installment,
              enabled: fieldsEnabled,
              onSelected: () => _change(
                () => selectFundingMode(SubscriptionFundingMode.installment),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const Key('subscription-purchase-reason'),
          initialValue: draft.purchaseReason,
          enabled: fieldsEnabled,
          maxLength: 500,
          minLines: 1,
          maxLines: 3,
          validator: validatePurchaseReason,
          onChanged: setPurchaseReason,
          decoration: clientCardInputDecoration(
            Theme.of(context).colorScheme,
            label: draft.payerStudentId == draft.recipientStudentId
                ? 'Комментарий к покупке'
                : 'Причина оплаты другим плательщиком *',
            hint: 'Причина сохранится в истории действий',
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _SubscriptionPeriodFields extends StatelessWidget {
  const _SubscriptionPeriodFields({
    required this.draft,
    required this.fieldsEnabled,
    required this.setStartsAt,
    required this.setExpiresAt,
    required this.validateExpiresAt,
    required this.onChanged,
  });

  final SubscriptionIssueDraft draft;
  final bool fieldsEnabled;
  final ValueChanged<DateTime> setStartsAt;
  final ValueChanged<DateTime> setExpiresAt;
  final String? Function() validateExpiresAt;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _dateField(
            context,
            key: 'subscription-starts-${_date(draft.startsAt)}',
            label: 'Начало действия',
            value: draft.startsAt,
            onPicked: setStartsAt,
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: _dateField(
            context,
            key: 'subscription-expires-${_date(draft.expiresAt)}',
            label: 'Окончание (включительно)',
            value: draft.expiresAt,
            onPicked: setExpiresAt,
            validator: (_) => validateExpiresAt(),
          ),
        ),
      ],
    );
  }

  Widget _dateField(
    BuildContext context, {
    required String key,
    required String label,
    required DateTime value,
    required ValueChanged<DateTime> onPicked,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      key: ValueKey(key),
      initialValue: _date(value),
      readOnly: true,
      enabled: fieldsEnabled,
      validator: validator,
      onTap: fieldsEnabled
          ? () => _pickDate(context, value, (picked) {
              onPicked(picked);
              onChanged();
            })
          : null,
      decoration: clientCardInputDecoration(
        Theme.of(context).colorScheme,
        label: label,
        isDense: true,
      ).copyWith(suffixIcon: const Icon(Icons.calendar_today_rounded)),
    );
  }
}

class _SubscriptionActualPaymentFields extends StatelessWidget {
  const _SubscriptionActualPaymentFields({
    required this.draft,
    required this.defaultPaymentMinor,
    required this.fieldsEnabled,
    required this.setPaymentAmount,
    required this.setPaymentOccurredAt,
    required this.setPaymentComment,
    required this.selectPaymentMethod,
    required this.validatePaymentAmount,
    required this.onChanged,
  });

  final SubscriptionIssueDraft draft;
  final BigInt defaultPaymentMinor;
  final bool fieldsEnabled;
  final ValueChanged<String> setPaymentAmount;
  final ValueChanged<DateTime> setPaymentOccurredAt;
  final ValueChanged<String> setPaymentComment;
  final ValueChanged<SubscriptionPaymentMethod> selectPaymentMethod;
  final FormFieldValidator<String> validatePaymentAmount;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _amountField(context)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: _paymentDateField(context)),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        _methodField(context),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const Key('subscription-payment-comment'),
          initialValue: draft.paymentComment,
          enabled: fieldsEnabled,
          maxLength: 500,
          minLines: 1,
          maxLines: 2,
          onChanged: setPaymentComment,
          decoration: clientCardInputDecoration(
            Theme.of(context).colorScheme,
            label: 'Комментарий к оплате',
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _amountField(BuildContext context) => TextFormField(
    key: ValueKey(
      'subscription-payment-${draft.paymentAmount.isEmpty ? defaultPaymentMinor : "manual"}',
    ),
    initialValue: draft.paymentAmount.isEmpty
        ? _minorInput(defaultPaymentMinor)
        : draft.paymentAmount,
    enabled: fieldsEnabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: validatePaymentAmount,
    onChanged: setPaymentAmount,
    decoration: clientCardInputDecoration(
      Theme.of(context).colorScheme,
      label: 'Оплачено сейчас',
      hint: 'Можно 0, часть или больше итога',
      isDense: true,
    ),
  );

  Widget _paymentDateField(BuildContext context) => TextFormField(
    key: ValueKey('subscription-paid-at-${_date(draft.paymentOccurredAt)}'),
    initialValue: _date(draft.paymentOccurredAt),
    readOnly: true,
    enabled: fieldsEnabled,
    onTap: fieldsEnabled
        ? () => _pickDate(context, draft.paymentOccurredAt, (picked) {
            setPaymentOccurredAt(
              DateTime.utc(
                picked.year,
                picked.month,
                picked.day,
                draft.paymentOccurredAt.hour,
                draft.paymentOccurredAt.minute,
                draft.paymentOccurredAt.second,
              ),
            );
            onChanged();
          })
        : null,
    decoration: clientCardInputDecoration(
      Theme.of(context).colorScheme,
      label: 'Дата оплаты',
      isDense: true,
    ).copyWith(suffixIcon: const Icon(Icons.calendar_today_rounded)),
  );

  Widget _methodField(BuildContext context) =>
      DropdownButtonFormField<SubscriptionPaymentMethod>(
        menuMaxHeight: 256,
        key: const Key('subscription-payment-method'),
        initialValue: draft.paymentMethod,
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
        onChanged: fieldsEnabled
            ? (value) {
                if (value == null) return;
                selectPaymentMethod(value);
                onChanged();
              }
            : null,
        decoration: clientCardInputDecoration(
          Theme.of(context).colorScheme,
          label: 'Способ оплаты',
          isDense: true,
        ),
      );
}

Future<void> _pickDate(
  BuildContext context,
  DateTime initial,
  ValueChanged<DateTime> onPicked,
) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: initial.toLocal(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (picked != null) onPicked(picked);
}

String _date(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(utc.day)}.${two(utc.month)}.${utc.year}';
}

String _minorInput(BigInt minor) {
  final whole = minor ~/ BigInt.from(100);
  final cents = (minor % BigInt.from(100)).toInt();
  return cents == 0
      ? whole.toString()
      : '$whole,${cents.toString().padLeft(2, '0')}';
}
