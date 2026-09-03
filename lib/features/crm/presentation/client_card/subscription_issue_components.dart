import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/utils/money_format.dart';

import 'subscription_issue_models.dart';

class SubscriptionIssuePriceSummary extends StatelessWidget {
  const SubscriptionIssuePriceSummary({
    super.key,
    required this.packageName,
    required this.basePriceMinor,
    required this.discountMinor,
    required this.surchargeMinor,
    required this.finalPriceMinor,
    required this.currencyCode,
  });

  final String packageName;
  final BigInt basePriceMinor;
  final BigInt discountMinor;
  final BigInt surchargeMinor;
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
          SubscriptionIssuePriceLine(
            label: 'Базовая сумма',
            value: formatSubscriptionMinor(basePriceMinor, currencyCode),
          ),
          SubscriptionIssuePriceLine(
            label: 'Скидка',
            value: discountMinor == BigInt.zero
                ? 'Не указано'
                : '−${formatSubscriptionMinor(discountMinor, currencyCode)}',
          ),
          SubscriptionIssuePriceLine(
            label: 'Доплата',
            value: surchargeMinor == BigInt.zero
                ? 'Не указано'
                : '+${formatSubscriptionMinor(surchargeMinor, currencyCode)}',
          ),
          const Divider(height: AppSpace.lg, color: AppColor.divider),
          SubscriptionIssuePriceLine(
            key: const Key('subscription-issue-final'),
            label: 'Итого',
            value: finalPriceMinor == null
                ? 'Не указано'
                : formatSubscriptionMinor(finalPriceMinor!, currencyCode),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class SubscriptionIssuePurchasePreviewCard extends StatelessWidget {
  const SubscriptionIssuePurchasePreviewCard({
    super.key,
    required this.preview,
    required this.recipientLabel,
    required this.payerLabel,
    required this.packageUnits,
  });

  final SubscriptionPurchasePreview preview;
  final String recipientLabel;
  final String payerLabel;
  final SubscriptionUnitAmount packageUnits;

  @override
  Widget build(BuildContext context) {
    final statusColor = !preview.canCommit
        ? AppColor.danger
        : preview.overpaymentMinor > BigInt.zero
        ? AppColor.danger
        : preview.debtMinor > BigInt.zero
        ? AppColor.warning
        : AppColor.success;
    final paidUnits = subscriptionPaidUnits(
      packageUnits: packageUnits,
      paidNowMinor: preview.paidNowMinor,
      finalObligationMinor: preview.finalPriceMinor,
    );
    return Container(
      key: const Key('subscription-purchase-preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            preview.canCommit ? 'Расчёт покупки' : 'Покупку нельзя провести',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpace.sm),
          SubscriptionIssuePriceLine(
            label: 'Получатель',
            value: recipientLabel,
          ),
          SubscriptionIssuePriceLine(label: 'Плательщик', value: payerLabel),
          SubscriptionIssuePriceLine(
            label: preview.fundingMode == SubscriptionFundingMode.installment
                ? 'Обязательство'
                : 'Стоимость',
            value: formatSubscriptionMinor(
              preview.finalPriceMinor,
              preview.currencyCode,
            ),
          ),
          SubscriptionIssuePriceLine(
            label: 'Оплачено сейчас',
            value: formatSubscriptionMinor(
              preview.paidNowMinor,
              preview.currencyCode,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Container(
            key: const Key('subscription-paid-units-status'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.xs,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: statusColor),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Оплачено занятий',
                    style: TextStyle(color: AppColor.text2, fontSize: 12),
                  ),
                ),
                Text(
                  '${paidUnits.format()} из ${packageUnits.format()} занятий',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SubscriptionIssuePriceLine(
            label: 'Расчёт по абонементу',
            value: formatSubscriptionMinor(
              preview.balanceAfterMinor,
              preview.currencyCode,
            ),
            emphasized: true,
          ),
          if (preview.debtMinor > BigInt.zero)
            SubscriptionIssuePriceLine(
              label: 'Долг после покупки',
              value: formatSubscriptionMinor(
                preview.debtMinor,
                preview.currencyCode,
              ),
              emphasized: true,
            ),
          if (preview.overpaymentMinor > BigInt.zero)
            SubscriptionIssuePriceLine(
              label: 'Переплата по абонементу',
              value: formatSubscriptionMinor(
                preview.overpaymentMinor,
                preview.currencyCode,
              ),
              emphasized: true,
            ),
        ],
      ),
    );
  }
}

class SubscriptionIssuePriceLine extends StatelessWidget {
  const SubscriptionIssuePriceLine({
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

class SubscriptionIssueSectionTitle extends StatelessWidget {
  const SubscriptionIssueSectionTitle(this.label, {super.key});
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

class SubscriptionIssueModeChip extends StatelessWidget {
  const SubscriptionIssueModeChip({
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

class SubscriptionIssueAdaptivePair extends StatelessWidget {
  const SubscriptionIssueAdaptivePair({
    super.key,
    required this.first,
    required this.second,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 520 * textScale) {
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

class SubscriptionIssueOptionCard extends StatelessWidget {
  const SubscriptionIssueOptionCard({
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

class SubscriptionIssueInstallmentPreview extends StatelessWidget {
  const SubscriptionIssueInstallmentPreview({
    super.key,
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
                    formatSubscriptionMinor(
                      installments[index].amountMinor,
                      currencyCode,
                    ),
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

class SubscriptionIssueRetryNotice extends StatelessWidget {
  const SubscriptionIssueRetryNotice({super.key});

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

class SubscriptionIssueInlineError extends StatelessWidget {
  const SubscriptionIssueInlineError({super.key, required this.error});
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

String formatSubscriptionMinor(BigInt minor, String currencyCode) {
  return formatPaymentMinor(minor, currencyCode: currencyCode);
}
