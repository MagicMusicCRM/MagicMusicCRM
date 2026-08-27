import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magic_music_crm/core/models/subscription_purchase.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'client_card_ui.dart';
import 'subscription_issue_components.dart';
import 'subscription_issue_controller.dart';
import 'subscription_issue_models.dart';

class SubscriptionIssueDiscountSection extends StatelessWidget {
  const SubscriptionIssueDiscountSection({
    super.key,
    required this.controller,
    required this.draft,
    required this.fieldsEnabled,
    required this.onChanged,
  });

  final SubscriptionIssueController controller;
  final SubscriptionIssueDraft draft;
  final bool fieldsEnabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.lg),
        const SubscriptionIssueSectionTitle('Скидка'),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            SubscriptionIssueModeChip(
              key: const Key('subscription-discount-none'),
              label: 'Без скидки',
              selected:
                  draft.discountMode == SubscriptionIssueDiscountMode.none,
              enabled: fieldsEnabled,
              onSelected: () => _selectMode(SubscriptionIssueDiscountMode.none),
            ),
            SubscriptionIssueModeChip(
              key: const Key('subscription-discount-percent'),
              label: 'Процент',
              selected:
                  draft.discountMode == SubscriptionIssueDiscountMode.percent,
              enabled: fieldsEnabled,
              onSelected: () =>
                  _selectMode(SubscriptionIssueDiscountMode.percent),
            ),
            SubscriptionIssueModeChip(
              key: const Key('subscription-discount-fixed'),
              label: 'Сумма',
              selected:
                  draft.discountMode == SubscriptionIssueDiscountMode.fixed,
              enabled: fieldsEnabled,
              onSelected: () =>
                  _selectMode(SubscriptionIssueDiscountMode.fixed),
            ),
          ],
        ),
        if (draft.discountMode != SubscriptionIssueDiscountMode.none) ...[
          const SizedBox(height: AppSpace.md),
          SubscriptionIssueAdaptivePair(
            first: KeyedSubtree(
              key: ValueKey(draft.discountMode),
              child: TextFormField(
                key: const Key('subscription-discount-value'),
                initialValue: draft.discountValue,
                enabled: fieldsEnabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_decimalInputFormatter],
                decoration: clientCardInputDecoration(
                  Theme.of(context).colorScheme,
                  label:
                      draft.discountMode ==
                          SubscriptionIssueDiscountMode.percent
                      ? 'Скидка, %'
                      : 'Скидка, ₽',
                  isDense: true,
                ),
                validator: controller.validateDiscountValue,
                onChanged: controller.setDiscountValue,
              ),
            ),
            second: TextFormField(
              key: const Key('subscription-discount-reason'),
              initialValue: draft.discountReason,
              enabled: fieldsEnabled,
              maxLength: 500,
              decoration: clientCardInputDecoration(
                Theme.of(context).colorScheme,
                label: 'Причина',
                hint: 'Например: семейная скидка',
                isDense: true,
              ),
              validator: controller.validateDiscountReason,
              onChanged: controller.setDiscountReason,
            ),
          ),
        ],
      ],
    );
  }

  void _selectMode(SubscriptionIssueDiscountMode mode) {
    controller.selectDiscountMode(mode);
    onChanged();
  }
}

class SubscriptionIssueSurchargeSection extends StatelessWidget {
  const SubscriptionIssueSurchargeSection({
    super.key,
    required this.controller,
    required this.draft,
    required this.fieldsEnabled,
    required this.onChanged,
  });

  final SubscriptionIssueController controller;
  final SubscriptionIssueDraft draft;
  final bool fieldsEnabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.lg),
        SubscriptionIssueOptionCard(
          key: const Key('subscription-surcharge-toggle'),
          icon: Icons.add_circle_outline_rounded,
          title: 'Доплата',
          subtitle: 'Добавить обоснованную сумму к стоимости абонемента',
          value: draft.surchargeEnabled,
          enabled: fieldsEnabled,
          onChanged: _setEnabled,
        ),
        if (draft.surchargeEnabled) ...[
          const SizedBox(height: AppSpace.md),
          SubscriptionIssueAdaptivePair(
            first: TextFormField(
              key: const Key('subscription-surcharge-amount'),
              initialValue: draft.surchargeAmount,
              enabled: fieldsEnabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_decimalInputFormatter],
              decoration: clientCardInputDecoration(
                Theme.of(context).colorScheme,
                label: 'Доплата, ₽',
                isDense: true,
              ),
              validator: controller.validateSurchargeAmount,
              onChanged: controller.setSurchargeAmount,
            ),
            second: TextFormField(
              key: const Key('subscription-surcharge-reason'),
              initialValue: draft.surchargeReason,
              enabled: fieldsEnabled,
              maxLength: 500,
              decoration: clientCardInputDecoration(
                Theme.of(context).colorScheme,
                label: 'Причина доплаты',
                hint: 'Например: дополнительное занятие',
                isDense: true,
              ),
              validator: controller.validateSurchargeReason,
              onChanged: controller.setSurchargeReason,
            ),
          ),
        ],
      ],
    );
  }

  void _setEnabled(bool value) {
    controller.setSurchargeEnabled(value);
    onChanged();
  }
}

class SubscriptionIssueInstallmentSection extends StatelessWidget {
  const SubscriptionIssueInstallmentSection({
    super.key,
    required this.controller,
    required this.draft,
    required this.fieldsEnabled,
    required this.onChanged,
  });

  final SubscriptionIssueController controller;
  final SubscriptionIssueDraft draft;
  final bool fieldsEnabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final installments = controller.pricing.installments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.xl),
        if (draft.fundingMode == SubscriptionFundingMode.installment) ...[
          const SubscriptionIssueSectionTitle('График рассрочки'),
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<int>(
            menuMaxHeight: 256,
            key: const Key('subscription-installment-count'),
            initialValue: draft.installmentCount,
            decoration: clientCardInputDecoration(
              Theme.of(context).colorScheme,
              label: 'Количество платежей',
              isDense: true,
            ),
            items: [
              for (var count = 2; count <= 12; count++)
                DropdownMenuItem(value: count, child: Text('$count')),
            ],
            onChanged: fieldsEnabled ? _setInstallmentCount : null,
          ),
          if (installments.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            SubscriptionIssueInstallmentPreview(
              installments: installments,
              currencyCode: draft.currencyCode,
            ),
          ],
        ],
      ],
    );
  }

  void _setInstallmentCount(int? value) {
    if (value == null) return;
    controller.setInstallmentCount(value);
    onChanged();
  }
}

final _decimalInputFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'[0-9,.]'),
);
