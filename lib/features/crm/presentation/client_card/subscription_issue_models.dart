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
    required this.startsAt,
    required this.expiresAt,
    required this.paymentOccurredAt,
    this.expiresAtExplicitlySet = false,
    this.paymentAmount = '',
    this.paymentComment = '',
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
    required DateTime commandTimestamp,
  }) {
    final start = DateTime.utc(
      commandTimestamp.year,
      commandTimestamp.month,
      commandTimestamp.day,
    );
    return SubscriptionIssueDraft(
      packageId: package['id'].toString(),
      recipientStudentId: recipientStudentId,
      recipientLabel: recipientLabel,
      payerStudentId: recipientStudentId,
      payerLabel: recipientLabel,
      currencyCode: package['currencyCode']?.toString().toUpperCase() ?? 'RUB',
      startsAt: start,
      expiresAt: subscriptionAddCalendarMonth(start),
      paymentOccurredAt: commandTimestamp.toUtc(),
    );
  }

  final String packageId;
  final String recipientStudentId;
  final String recipientLabel;
  final String payerStudentId;
  final String payerLabel;
  final String currencyCode;
  final DateTime startsAt;
  final DateTime expiresAt;
  final DateTime paymentOccurredAt;
  final bool expiresAtExplicitlySet;
  final String paymentAmount;
  final String paymentComment;
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
    DateTime? startsAt,
    DateTime? expiresAt,
    DateTime? paymentOccurredAt,
    bool? expiresAtExplicitlySet,
    String? paymentAmount,
    String? paymentComment,
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
      startsAt: startsAt ?? this.startsAt,
      expiresAt: expiresAt ?? this.expiresAt,
      paymentOccurredAt: paymentOccurredAt ?? this.paymentOccurredAt,
      expiresAtExplicitlySet:
          expiresAtExplicitlySet ?? this.expiresAtExplicitlySet,
      paymentAmount: paymentAmount ?? this.paymentAmount,
      paymentComment: paymentComment ?? this.paymentComment,
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

DateTime subscriptionAddCalendarMonth(DateTime source) {
  final utc = source.toUtc();
  final nextMonth = utc.month == 12 ? 1 : utc.month + 1;
  final nextYear = utc.month == 12 ? utc.year + 1 : utc.year;
  final lastDay = DateTime.utc(nextYear, nextMonth + 1, 0).day;
  return DateTime.utc(
    nextYear,
    nextMonth,
    utc.day > lastDay ? lastDay : utc.day,
  );
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

/// Exact unit amount used by the purchase projection. Package units are a
/// PostgreSQL numeric value, so converting them (or money) through `double`
/// can change the result before it reaches the UI.
class SubscriptionUnitAmount implements Comparable<SubscriptionUnitAmount> {
  const SubscriptionUnitAmount._(this.numerator, this.denominator);

  final BigInt numerator;
  final BigInt denominator;

  factory SubscriptionUnitAmount.parse(Object? raw) {
    final text = raw?.toString().trim().replaceAll(',', '.') ?? '';
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
    if (match == null) {
      return SubscriptionUnitAmount._(BigInt.zero, BigInt.one);
    }
    final fraction = match.group(2) ?? '';
    return SubscriptionUnitAmount._(
      BigInt.parse('${match.group(1)}$fraction'),
      BigInt.from(10).pow(fraction.length),
    );
  }

  @override
  int compareTo(SubscriptionUnitAmount other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  /// The UI intentionally rounds half up to the existing two decimal places.
  String format({int fractionDigits = 2}) {
    final scale = BigInt.from(10).pow(fractionDigits);
    final scaled = numerator * scale;
    var rounded = scaled ~/ denominator;
    if ((scaled.remainder(denominator) * BigInt.two) >= denominator) {
      rounded += BigInt.one;
    }
    final whole = rounded ~/ scale;
    final fraction = rounded.remainder(scale);
    if (fraction == BigInt.zero) return whole.toString();
    return '$whole.${fraction.toString().padLeft(fractionDigits, '0')}';
  }
}

SubscriptionUnitAmount subscriptionPackageUnitCount(
  Map<String, dynamic> package,
) => SubscriptionUnitAmount.parse(
  package['unitCount'] ?? package['lessons_total'] ?? package['lessonsTotal'],
);

/// Mirrors `commerce-projection.repository.ts` paid_units exactly for a sale
/// preview: non-positive obligation grants all units; otherwise payment is
/// clamped to the package capacity.
SubscriptionUnitAmount subscriptionPaidUnits({
  required SubscriptionUnitAmount packageUnits,
  required BigInt paidNowMinor,
  required BigInt finalObligationMinor,
}) {
  if (finalObligationMinor <= BigInt.zero) return packageUnits;
  final paidNow = paidNowMinor < BigInt.zero ? BigInt.zero : paidNowMinor;
  if (paidNow >= finalObligationMinor) return packageUnits;
  return SubscriptionUnitAmount._(
    paidNow * packageUnits.numerator,
    finalObligationMinor * packageUnits.denominator,
  );
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
