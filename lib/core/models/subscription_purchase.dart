enum SubscriptionPaymentMethod {
  cash('cash'),
  cashless('cashless');

  const SubscriptionPaymentMethod(this.apiValue);
  final String apiValue;
}

enum SubscriptionDiscountKind { percent, fixed }

/// Discount shape accepted by the v4 subscription-issue command.
///
/// Percent is stored as integer basis points in Flutter, preserving the API's
/// two-decimal precision without floating-point drift (20% = 2000).
class SubscriptionDiscountInput {
  const SubscriptionDiscountInput._({
    required this.kind,
    required this.reason,
    this.percentBasisPoints,
    this.fixedMinor,
  });

  factory SubscriptionDiscountInput.percent({
    required int basisPoints,
    required String reason,
  }) {
    return SubscriptionDiscountInput._(
      kind: SubscriptionDiscountKind.percent,
      percentBasisPoints: basisPoints,
      reason: reason.trim(),
    );
  }

  factory SubscriptionDiscountInput.fixed({
    required BigInt fixedMinor,
    required String reason,
  }) {
    return SubscriptionDiscountInput._(
      kind: SubscriptionDiscountKind.fixed,
      fixedMinor: fixedMinor,
      reason: reason.trim(),
    );
  }

  final SubscriptionDiscountKind kind;
  final String reason;
  final int? percentBasisPoints;
  final BigInt? fixedMinor;

  Map<String, dynamic> toJson() {
    return switch (kind) {
      SubscriptionDiscountKind.percent => <String, dynamic>{
        'type': 'percent',
        'percent': percentBasisPoints! % 100 == 0
            ? percentBasisPoints! ~/ 100
            : percentBasisPoints! / 100,
        'reason': reason,
      },
      SubscriptionDiscountKind.fixed => <String, dynamic>{
        'type': 'fixed',
        'fixedMinor': fixedMinor!.toString(),
        'reason': reason,
      },
    };
  }
}

class SubscriptionInstallmentInput {
  const SubscriptionInstallmentInput({
    required this.dueAt,
    required this.amountMinor,
  });

  final DateTime dueAt;
  final BigInt amountMinor;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'dueAt': dueAt.toUtc().toIso8601String(),
    'amountMinor': amountMinor.toString(),
  };
}

class SubscriptionSurchargeInput {
  const SubscriptionSurchargeInput({
    required this.amountMinor,
    required this.reason,
  });

  final BigInt amountMinor;
  final String reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'amountMinor': amountMinor.toString(),
    'reason': reason.trim(),
  };
}

class IssueSubscriptionInput {
  const IssueSubscriptionInput({
    required this.packageId,
    this.discount,
    this.installments = const <SubscriptionInstallmentInput>[],
    this.paymentMethod,
    this.surcharge,
  });

  final String packageId;
  final SubscriptionDiscountInput? discount;
  final List<SubscriptionInstallmentInput> installments;
  final SubscriptionPaymentMethod? paymentMethod;
  final SubscriptionSurchargeInput? surcharge;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'packageId': packageId,
    if (discount != null) 'discount': discount!.toJson(),
    if (installments.isNotEmpty)
      'installments': installments
          .map((installment) => installment.toJson())
          .toList(growable: false),
    if (paymentMethod != null) 'paymentMethod': paymentMethod!.apiValue,
    if (surcharge != null) 'surcharge': surcharge!.toJson(),
  };
}

enum SubscriptionFundingMode {
  personalAccount('personal_account'),
  installment('installment');

  const SubscriptionFundingMode(this.apiValue);
  final String apiValue;
}

class PurchaseSubscriptionInput {
  const PurchaseSubscriptionInput({
    required this.issue,
    required this.payerStudentId,
    required this.fundingMode,
    required this.startsAt,
    required this.expiresAt,
    required this.paymentAmountMinor,
    this.paymentOccurredAt,
    this.paymentComment,
    this.purchaseReason,
  });

  final IssueSubscriptionInput issue;
  final String payerStudentId;
  final SubscriptionFundingMode fundingMode;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final BigInt paymentAmountMinor;
  final DateTime? paymentOccurredAt;
  final String? paymentComment;
  final String? purchaseReason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    ...issue.toJson(),
    'payerStudentId': payerStudentId,
    'fundingMode': fundingMode.apiValue,
    'startsAt': _dateOnly(startsAt),
    'expiresAt': expiresAt == null ? null : _dateOnly(expiresAt!),
    'paymentAmountMinor': paymentAmountMinor.toString(),
    if (paymentOccurredAt != null)
      'paymentOccurredAt': paymentOccurredAt!.toUtc().toIso8601String(),
    if (paymentComment?.trim().isNotEmpty == true)
      'paymentComment': paymentComment!.trim(),
    if (purchaseReason?.trim().isNotEmpty == true)
      'purchaseReason': purchaseReason!.trim(),
  };
}

class SubscriptionPurchasePreview {
  const SubscriptionPurchasePreview({
    required this.recipientStudentId,
    required this.payerStudentId,
    required this.fundingMode,
    required this.currencyCode,
    required this.finalPriceMinor,
    required this.payerBalanceMinor,
    required this.paidNowMinor,
    required this.balanceAfterMinor,
    required this.canCommit,
    required this.shortageMinor,
    required this.debtMinor,
    required this.overpaymentMinor,
    required this.previewToken,
  });

  final String recipientStudentId;
  final String payerStudentId;
  final SubscriptionFundingMode fundingMode;
  final String currencyCode;
  final BigInt finalPriceMinor;
  final BigInt payerBalanceMinor;
  final BigInt paidNowMinor;
  final BigInt balanceAfterMinor;
  final bool canCommit;
  final BigInt shortageMinor;
  final BigInt debtMinor;
  final BigInt overpaymentMinor;
  final String previewToken;

  factory SubscriptionPurchasePreview.fromJson(Map<String, dynamic> json) {
    return SubscriptionPurchasePreview(
      recipientStudentId: json['recipientStudentId'].toString(),
      payerStudentId: json['payerStudentId'].toString(),
      fundingMode: json['fundingMode'] == 'installment'
          ? SubscriptionFundingMode.installment
          : SubscriptionFundingMode.personalAccount,
      currencyCode: json['currencyCode'].toString(),
      finalPriceMinor: _purchaseMinor(json['finalPriceMinor']),
      payerBalanceMinor: _purchaseMinor(json['payerBalanceMinor']),
      paidNowMinor: _purchaseMinor(json['paidNowMinor'] ?? 0),
      balanceAfterMinor: _purchaseMinor(json['balanceAfterMinor']),
      canCommit: json['canCommit'] == true,
      shortageMinor: _purchaseMinor(json['shortageMinor']),
      debtMinor: _purchaseMinor(
        json['debtMinor'] ?? json['shortageMinor'] ?? 0,
      ),
      overpaymentMinor: _purchaseMinor(json['overpaymentMinor'] ?? 0),
      previewToken: json['previewToken'].toString(),
    );
  }
}

BigInt _purchaseMinor(Object? value) => BigInt.parse(value.toString());

String _dateOnly(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}';
}
