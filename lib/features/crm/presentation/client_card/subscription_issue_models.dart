import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/models/subscription_purchase.dart';

enum SubscriptionIssueDiscountMode { none, percent, fixed }

enum SubscriptionIssueSubmitResult { previewLoaded, committed, blocked, failed }

typedef SubscriptionIdentityFactory = MagicMutationIdentity Function();
typedef SubscriptionIssueSubmit =
    Future<void> Function(SubscriptionIssueSubmission submission);
typedef SubscriptionIssuePreview =
    Future<SubscriptionPurchasePreview> Function(
      PurchaseSubscriptionInput input,
    );

class SubscriptionIssueSubmission {
  const SubscriptionIssueSubmission({
    required this.purchase,
    required this.preview,
    required this.identity,
  });

  final PurchaseSubscriptionInput purchase;
  final SubscriptionPurchasePreview preview;
  final MagicMutationIdentity identity;
}

class SubscriptionIssueDraft {
  const SubscriptionIssueDraft({
    required this.packageId,
    required this.recipientStudentId,
    required this.recipientLabel,
    required this.payerStudentId,
    required this.payerLabel,
    required this.currencyCode,
    this.paymentMethod = SubscriptionPaymentMethod.cashless,
    this.fundingMode = SubscriptionFundingMode.personalAccount,
    this.discountMode = SubscriptionIssueDiscountMode.none,
    this.discountValue = '',
    this.discountReason = '',
    this.surchargeEnabled = false,
    this.surchargeAmount = '',
    this.surchargeReason = '',
    this.purchaseReason = '',
    this.installmentCount = 2,
  });

  factory SubscriptionIssueDraft.fromPackage({
    required Map<String, dynamic> package,
    required String recipientStudentId,
    required String recipientLabel,
  }) {
    return SubscriptionIssueDraft(
      packageId: package['id'].toString(),
      recipientStudentId: recipientStudentId,
      recipientLabel: recipientLabel,
      payerStudentId: recipientStudentId,
      payerLabel: recipientLabel,
      currencyCode: package['currencyCode']?.toString().toUpperCase() ?? 'RUB',
    );
  }

  final String packageId;
  final String recipientStudentId;
  final String recipientLabel;
  final String payerStudentId;
  final String payerLabel;
  final String currencyCode;
  final SubscriptionPaymentMethod paymentMethod;
  final SubscriptionFundingMode fundingMode;
  final SubscriptionIssueDiscountMode discountMode;
  final String discountValue;
  final String discountReason;
  final bool surchargeEnabled;
  final String surchargeAmount;
  final String surchargeReason;
  final String purchaseReason;
  final int installmentCount;

  SubscriptionIssueDraft copyWith({
    String? payerStudentId,
    String? payerLabel,
    SubscriptionPaymentMethod? paymentMethod,
    SubscriptionFundingMode? fundingMode,
    SubscriptionIssueDiscountMode? discountMode,
    String? discountValue,
    String? discountReason,
    bool? surchargeEnabled,
    String? surchargeAmount,
    String? surchargeReason,
    String? purchaseReason,
    int? installmentCount,
  }) {
    return SubscriptionIssueDraft(
      packageId: packageId,
      recipientStudentId: recipientStudentId,
      recipientLabel: recipientLabel,
      payerStudentId: payerStudentId ?? this.payerStudentId,
      payerLabel: payerLabel ?? this.payerLabel,
      currencyCode: currencyCode,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      fundingMode: fundingMode ?? this.fundingMode,
      discountMode: discountMode ?? this.discountMode,
      discountValue: discountValue ?? this.discountValue,
      discountReason: discountReason ?? this.discountReason,
      surchargeEnabled: surchargeEnabled ?? this.surchargeEnabled,
      surchargeAmount: surchargeAmount ?? this.surchargeAmount,
      surchargeReason: surchargeReason ?? this.surchargeReason,
      purchaseReason: purchaseReason ?? this.purchaseReason,
      installmentCount: installmentCount ?? this.installmentCount,
    );
  }
}

BigInt subscriptionPackageBasePriceMinor(Map<String, dynamic> package) {
  final canonical = BigInt.tryParse(
    (package['basePriceMinor'] ?? package['base_price_minor'])?.toString() ??
        '',
  );
  if (canonical != null) return canonical;
  return parseSubscriptionMoneyMinor(package['price']?.toString() ?? '') ??
      BigInt.zero;
}

BigInt? parseSubscriptionMoneyMinor(String raw) {
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

int? parseSubscriptionPercentBasisPoints(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final whole = int.tryParse(match.group(1)!);
  if (whole == null) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction.isEmpty ? '0' : fraction);
}
