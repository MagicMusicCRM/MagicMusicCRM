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
    required this.fieldsEnabled,
    required this.searchPayers,
    required this.selectPayer,
    required this.selectPaymentMethod,
    required this.selectFundingMode,
    required this.validatePurchaseReason,
    required this.setPurchaseReason,
    required this.onChanged,
  });

  final SubscriptionIssueDraft draft;
  final bool fieldsEnabled;
  final Future<List<SearchableSelectItem>> Function(String query) searchPayers;
  final ValueChanged<SearchableSelectItem> selectPayer;
  final ValueChanged<SubscriptionPaymentMethod> selectPaymentMethod;
  final ValueChanged<SubscriptionFundingMode> selectFundingMode;
  final FormFieldValidator<String> validatePurchaseReason;
  final ValueChanged<String> setPurchaseReason;
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
        SearchablePickerField(
          key: const Key('subscription-payer'),
          label: 'Личный счёт плательщика',
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
                  if (value != null) {
                    _change(() => selectPaymentMethod(value));
                  }
                }
              : null,
          decoration: clientCardInputDecoration(
            Theme.of(context).colorScheme,
            label: 'Способ оплаты',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            SubscriptionIssueModeChip(
              key: const Key('subscription-funding-account'),
              label: 'С личного счёта',
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
                : 'Причина оплаты с чужого счёта *',
            hint: 'Причина сохранится в истории действий',
            isDense: true,
          ),
        ),
      ],
    );
  }
}
