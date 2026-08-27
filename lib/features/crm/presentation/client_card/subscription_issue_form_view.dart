import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'client_card_ui.dart';
import 'subscription_issue_adjustment_sections.dart';
import 'subscription_issue_components.dart';
import 'subscription_issue_controller.dart';
import 'subscription_issue_models.dart';
import 'subscription_issue_payment_section.dart';

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
            finalPriceMinor: pricing.amountsValid
                ? pricing.finalPriceMinor
                : null,
            currencyCode: draft.currencyCode,
          ),
          SubscriptionIssuePaymentSection(
            draft: draft,
            fieldsEnabled: fieldsEnabled,
            searchPayers: searchPayers,
            selectPayer: controller.selectPayer,
            selectFundingMode: controller.selectFundingMode,
            validatePurchaseReason: controller.validatePurchaseReason,
            setPurchaseReason: controller.setPurchaseReason,
            onChanged: onChanged,
          ),
          SubscriptionIssueDiscountSection(
            draft: draft,
            fieldsEnabled: fieldsEnabled,
            selectMode: controller.selectDiscountMode,
            validateValue: controller.validateDiscountValue,
            setValue: controller.setDiscountValue,
            validateReason: controller.validateDiscountReason,
            setReason: controller.setDiscountReason,
            onChanged: onChanged,
          ),
          SubscriptionIssueSurchargeSection(
            draft: draft,
            fieldsEnabled: fieldsEnabled,
            setEnabled: controller.setSurchargeEnabled,
            validateAmount: controller.validateSurchargeAmount,
            setAmount: controller.setSurchargeAmount,
            validateReason: controller.validateSurchargeReason,
            setReason: controller.setSurchargeReason,
            onChanged: onChanged,
          ),
          SubscriptionIssueInstallmentSection(
            draft: draft,
            fieldsEnabled: fieldsEnabled,
            installments: controller.pricing.installments,
            setInstallmentCount: controller.setInstallmentCount,
            onChanged: onChanged,
          ),
          ..._feedbackSection(draft),
          _actions(),
        ],
      ),
    );
  }

  List<Widget> _feedbackSection(SubscriptionIssueDraft draft) {
    return [
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
    ];
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl),
      child: Row(
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
    );
  }
}
