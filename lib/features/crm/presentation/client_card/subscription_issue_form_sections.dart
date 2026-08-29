import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'subscription_issue_adjustment_sections.dart';
import 'subscription_issue_controller.dart';
import 'subscription_issue_payment_section.dart';

class SubscriptionIssueFormSections extends StatelessWidget {
  const SubscriptionIssueFormSections({
    super.key,
    required this.controller,
    required this.packages,
    required this.acceptedByLabel,
    required this.searchPayers,
    required this.onChanged,
  });

  final SubscriptionIssueController controller;
  final List<Map<String, dynamic>> packages;
  final String acceptedByLabel;
  final Future<List<SearchableSelectItem>> Function(String query) searchPayers;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    final fieldsEnabled = controller.fieldsEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        SearchablePickerField(
          key: const Key('subscription-package-selector'),
          label: 'Абонемент',
          placeholder: 'Выберите абонемент',
          hintText: 'Введите название абонемента',
          selectedId: draft.packageId,
          isNullable: false,
          enabled: fieldsEnabled,
          items: [
            for (final package in packages)
              if (package['id']?.toString().isNotEmpty == true)
                SearchableSelectItem(
                  id: package['id'].toString(),
                  label: package['name']?.toString() ?? 'Абонемент',
                ),
          ],
          onSelected: (item) {
            if (item == null || !fieldsEnabled) return;
            final package = packages.where(
              (candidate) => candidate['id']?.toString() == item.id,
            );
            if (package.isEmpty) return;
            controller.selectPackage(package.first);
            onChanged();
          },
        ),
        SubscriptionIssuePaymentSection(
          draft: draft,
          defaultPaymentMinor: controller.pricing.finalPriceMinor,
          fieldsEnabled: fieldsEnabled,
          searchPayers: searchPayers,
          selectPayer: controller.selectPayer,
          selectPaymentMethod: controller.selectPaymentMethod,
          selectFundingMode: controller.selectFundingMode,
          setStartsAt: controller.setStartsAt,
          setExpiresAt: controller.setExpiresAt,
          setPaymentAmount: controller.setPaymentAmount,
          setPaymentOccurredAt: controller.setPaymentOccurredAt,
          setPaymentComment: controller.setPaymentComment,
          validatePaymentAmount: controller.validatePaymentAmount,
          validateExpiresAt: controller.validateExpiresAt,
          validatePurchaseReason: controller.validatePurchaseReason,
          setPurchaseReason: controller.setPurchaseReason,
          acceptedByLabel: acceptedByLabel,
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
