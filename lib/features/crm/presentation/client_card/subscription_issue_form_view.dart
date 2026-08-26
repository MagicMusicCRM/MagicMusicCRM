import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'client_card_ui.dart';
import 'subscription_issue_components.dart';
import 'subscription_issue_controller.dart';
import 'subscription_issue_models.dart';

class SubscriptionIssueFormView extends StatelessWidget {
  const SubscriptionIssueFormView({
    super.key,
    required this.formKey,
    required this.packageName,
    required this.controller,
    required this.searchPayers,
    required this.onChanged,
    required this.onClose,
    required this.submitPressed,
  });

  final GlobalKey<FormState> formKey;
  final String packageName;
  final SubscriptionIssueController controller;
  final Future<List<SearchableSelectItem>> Function(String query) searchPayers;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  final VoidCallback submitPressed;

  void _change(VoidCallback action) {
    action();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final pricing = controller.pricing;
    final fieldsEnabled = controller.fieldsEnabled;
    return Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: onChanged,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubscriptionIssuePriceSummary(
            packageName: packageName,
            basePriceMinor: pricing.basePriceMinor,
            discountMinor: pricing.discountMinor,
            surchargeMinor: pricing.surchargeMinor,
            finalPriceMinor: pricing.finalPriceMinor,
            currencyCode: draft.currencyCode,
          ),
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
              if (item != null) _change(() => controller.selectPayer(item));
            },
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
                    draft.fundingMode ==
                    SubscriptionFundingMode.personalAccount,
                enabled: fieldsEnabled,
                onSelected: () => _change(
                  () => controller.selectFundingMode(
                    SubscriptionFundingMode.personalAccount,
                  ),
                ),
              ),
              SubscriptionIssueModeChip(
                key: const Key('subscription-funding-installment'),
                label: 'Рассрочка',
                selected:
                    draft.fundingMode == SubscriptionFundingMode.installment,
                enabled: fieldsEnabled,
                onSelected: () => _change(
                  () => controller.selectFundingMode(
                    SubscriptionFundingMode.installment,
                  ),
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
            validator: controller.validatePurchaseReason,
            onChanged: controller.setPurchaseReason,
            decoration: clientCardInputDecoration(
              Theme.of(context).colorScheme,
              label: draft.payerStudentId == draft.recipientStudentId
                  ? 'Комментарий к покупке'
                  : 'Причина оплаты с чужого счёта *',
              hint: 'Причина сохранится в истории действий',
              isDense: true,
            ),
          ),
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
                onSelected: () => _change(
                  () => controller.selectDiscountMode(
                    SubscriptionIssueDiscountMode.none,
                  ),
                ),
              ),
              SubscriptionIssueModeChip(
                key: const Key('subscription-discount-percent'),
                label: 'Процент',
                selected:
                    draft.discountMode == SubscriptionIssueDiscountMode.percent,
                enabled: fieldsEnabled,
                onSelected: () => _change(
                  () => controller.selectDiscountMode(
                    SubscriptionIssueDiscountMode.percent,
                  ),
                ),
              ),
              SubscriptionIssueModeChip(
                key: const Key('subscription-discount-fixed'),
                label: 'Сумма',
                selected:
                    draft.discountMode == SubscriptionIssueDiscountMode.fixed,
                enabled: fieldsEnabled,
                onSelected: () => _change(
                  () => controller.selectDiscountMode(
                    SubscriptionIssueDiscountMode.fixed,
                  ),
                ),
              ),
            ],
          ),
          if (draft.discountMode != SubscriptionIssueDiscountMode.none) ...[
            const SizedBox(height: AppSpace.md),
            SubscriptionIssueAdaptivePair(
              first: TextFormField(
                key: const Key('subscription-discount-value'),
                initialValue: draft.discountValue,
                enabled: fieldsEnabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                ],
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
          const SizedBox(height: AppSpace.lg),
          SubscriptionIssueOptionCard(
            key: const Key('subscription-surcharge-toggle'),
            icon: Icons.add_circle_outline_rounded,
            title: 'Доплата',
            subtitle: 'Добавить обоснованную сумму к стоимости абонемента',
            value: draft.surchargeEnabled,
            enabled: fieldsEnabled,
            onChanged: (value) =>
                _change(() => controller.setSurchargeEnabled(value)),
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
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                ],
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
              onChanged: fieldsEnabled
                  ? (value) {
                      if (value != null) {
                        _change(() => controller.setInstallmentCount(value));
                      }
                    }
                  : null,
            ),
            if (pricing.installments.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              SubscriptionIssueInstallmentPreview(
                installments: pricing.installments,
                currencyCode: draft.currencyCode,
              ),
            ],
          ],
          if (controller.preview != null) ...[
            const SizedBox(height: AppSpace.md),
            SubscriptionIssuePurchasePreviewCard(
              preview: controller.preview!,
              recipientLabel: draft.recipientLabel,
              payerLabel: draft.payerLabel,
            ),
          ],
          if (controller.attempted) ...[
            const SizedBox(height: AppSpace.md),
            const SubscriptionIssueRetryNotice(),
          ],
          if (controller.error != null) ...[
            const SizedBox(height: AppSpace.md),
            SubscriptionIssueInlineError(error: controller.error!),
          ],
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              Expanded(
                child: clientCardGhostButton(
                  'Отмена',
                  controller.busy ? null : onClose,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('subscription-issue-submit'),
                  onPressed: controller.busy ? null : submitPressed,
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
                  child: controller.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColor.onGold,
                          ),
                        )
                      : Text(
                          controller.attempted
                              ? 'Повторить'
                              : controller.preview == null
                              ? 'Проверить'
                              : 'Подтвердить покупку',
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
