import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'subscription_issue_adjustment_sections.dart';
import 'subscription_issue_controller.dart';
import 'subscription_issue_payment_section.dart';

class SubscriptionIssueFormSections extends StatelessWidget {
  const SubscriptionIssueFormSections({
    super.key,
    required this.controller,
    required this.searchPayers,
    required this.onChanged,
  });

  final SubscriptionIssueController controller;
  final Future<List<SearchableSelectItem>> Function(String query) searchPayers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final fieldsEnabled = controller.fieldsEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    );
  }
}
