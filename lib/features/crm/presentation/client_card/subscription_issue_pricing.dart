import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'subscription_issue_models.dart';

class SubscriptionIssuePricing {
  const SubscriptionIssuePricing({
    required this.basePriceMinor,
    required this.discountMinor,
    required this.surchargeMinor,
    required this.finalPriceMinor,
    required this.amountsValid,
    required this.installments,
    this.discountBasisPoints,
    this.error,
  });

  final BigInt basePriceMinor;
  final BigInt discountMinor;
  final BigInt surchargeMinor;
  final BigInt finalPriceMinor;
  final bool amountsValid;
  final List<SubscriptionInstallmentInput> installments;
  final int? discountBasisPoints;
  final String? error;

  bool get isValid => error == null;

  static SubscriptionIssuePricing calculate({
    required SubscriptionIssueDraft draft,
    required BigInt basePriceMinor,
    required DateTime commandTimestamp,
  }) {
    final amountsValid =
        validateDiscountValue(draft, basePriceMinor) == null &&
        validateSurchargeAmount(draft) == null;
    final discount = _discount(draft, basePriceMinor);
    final surcharge = _surcharge(draft);
    final finalPrice = basePriceMinor - discount.minor + surcharge.minor;
    final paidNow = draft.paymentAmount.trim().isEmpty
        ? finalPrice
        : parseSubscriptionMoneyMinor(draft.paymentAmount) ?? BigInt.zero;
    final installmentTotal = finalPrice > paidNow
        ? finalPrice - paidNow
        : BigInt.zero;
    final error =
        discount.error ??
        surcharge.error ??
        _paymentAmountError(draft) ??
        _dateRangeError(draft) ??
        _purchaseReasonError(draft) ??
        _installmentError(draft, installmentTotal);
    final installments = error == null
        ? _installments(draft, installmentTotal, commandTimestamp)
        : const <SubscriptionInstallmentInput>[];
    return SubscriptionIssuePricing(
      basePriceMinor: basePriceMinor,
      discountMinor: discount.minor,
      surchargeMinor: surcharge.minor,
      finalPriceMinor: finalPrice,
      amountsValid: amountsValid,
      installments: installments,
      discountBasisPoints: discount.basisPoints,
      error: error,
    );
  }

  static String? validateDiscountValue(
    SubscriptionIssueDraft draft,
    BigInt basePriceMinor,
  ) {
    if (draft.discountMode == SubscriptionIssueDiscountMode.none) return null;
    if (draft.discountValue.trim().isEmpty) return 'Укажите размер скидки';
    if (draft.discountMode == SubscriptionIssueDiscountMode.percent) {
      final basisPoints = parseSubscriptionPercentBasisPoints(
        draft.discountValue,
      );
      if (basisPoints == null) return 'Не более двух знаков после запятой';
      if (basisPoints < 1 || basisPoints > 10000) {
        return 'Допустимо от 0,01% до 100%';
      }
      return null;
    }
    final fixed = parseSubscriptionMoneyMinor(draft.discountValue);
    if (fixed == null || fixed <= BigInt.zero) {
      return 'Введите положительную сумму';
    }
    if (fixed > basePriceMinor) {
      return 'Скидка не может превышать стоимость';
    }
    return null;
  }

  static String? validateDiscountReason(SubscriptionIssueDraft draft) {
    if (draft.discountMode == SubscriptionIssueDiscountMode.none) return null;
    return draft.discountReason.trim().isEmpty
        ? 'Укажите причину скидки'
        : null;
  }

  static String? validateSurchargeAmount(SubscriptionIssueDraft draft) {
    if (!draft.surchargeEnabled) return null;
    final amount = parseSubscriptionMoneyMinor(draft.surchargeAmount);
    return amount == null || amount <= BigInt.zero
        ? 'Введите положительную сумму'
        : null;
  }

  static String? validateSurchargeReason(SubscriptionIssueDraft draft) {
    if (!draft.surchargeEnabled) return null;
    return draft.surchargeReason.trim().isEmpty
        ? 'Укажите причину доплаты'
        : null;
  }

  static String? validatePurchaseReason(SubscriptionIssueDraft draft) {
    return _purchaseReasonError(draft);
  }

  static ({BigInt minor, int? basisPoints, String? error}) _discount(
    SubscriptionIssueDraft draft,
    BigInt basePriceMinor,
  ) {
    final valueError = validateDiscountValue(draft, basePriceMinor);
    final reasonError = validateDiscountReason(draft);
    final error = valueError ?? reasonError;
    switch (draft.discountMode) {
      case SubscriptionIssueDiscountMode.none:
        return (minor: BigInt.zero, basisPoints: null, error: error);
      case SubscriptionIssueDiscountMode.percent:
        final basisPoints = parseSubscriptionPercentBasisPoints(
          draft.discountValue,
        );
        if (basisPoints == null || basisPoints < 1 || basisPoints > 10000) {
          return (minor: BigInt.zero, basisPoints: basisPoints, error: error);
        }
        final minor =
            (basePriceMinor * BigInt.from(basisPoints) + BigInt.from(5000)) ~/
            BigInt.from(10000);
        return (minor: minor, basisPoints: basisPoints, error: error);
      case SubscriptionIssueDiscountMode.fixed:
        final fixed = parseSubscriptionMoneyMinor(draft.discountValue);
        return (
          minor: fixed == null || fixed <= BigInt.zero || fixed > basePriceMinor
              ? BigInt.zero
              : fixed,
          basisPoints: null,
          error: error,
        );
    }
  }

  static ({BigInt minor, String? error}) _surcharge(
    SubscriptionIssueDraft draft,
  ) {
    final error =
        validateSurchargeAmount(draft) ?? validateSurchargeReason(draft);
    if (!draft.surchargeEnabled) return (minor: BigInt.zero, error: error);
    final amount = parseSubscriptionMoneyMinor(draft.surchargeAmount);
    return (
      minor: amount == null || amount <= BigInt.zero ? BigInt.zero : amount,
      error: error,
    );
  }

  static String? _purchaseReasonError(SubscriptionIssueDraft draft) {
    if (draft.payerStudentId == draft.recipientStudentId) return null;
    return draft.purchaseReason.trim().isEmpty
        ? 'Укажите причину оплаты другим плательщиком'
        : null;
  }

  static String? _paymentAmountError(SubscriptionIssueDraft draft) {
    if (draft.paymentAmount.trim().isEmpty) return null;
    return parseSubscriptionMoneyMinor(draft.paymentAmount) == null
        ? 'Введите корректную сумму оплаты'
        : null;
  }

  static String? _dateRangeError(SubscriptionIssueDraft draft) {
    return draft.expiresAt.isBefore(draft.startsAt)
        ? 'Дата окончания не может быть раньше даты начала.'
        : null;
  }

  static String? _installmentError(
    SubscriptionIssueDraft draft,
    BigInt finalPrice,
  ) {
    if (draft.fundingMode != SubscriptionFundingMode.installment) return null;
    if (draft.installmentCount < 2 || draft.installmentCount > 12) {
      return 'Количество платежей должно быть от 2 до 12.';
    }
    if (finalPrice < BigInt.from(draft.installmentCount)) {
      return 'Итог должен позволять ${draft.installmentCount} положительных платежа.';
    }
    return null;
  }

  static List<SubscriptionInstallmentInput> _installments(
    SubscriptionIssueDraft draft,
    BigInt finalPrice,
    DateTime commandTimestamp,
  ) {
    if (draft.fundingMode != SubscriptionFundingMode.installment) {
      return const <SubscriptionInstallmentInput>[];
    }
    final count = draft.installmentCount;
    final equalPart = finalPrice ~/ BigInt.from(count);
    final remainder = (finalPrice % BigInt.from(count)).toInt();
    return List<SubscriptionInstallmentInput>.generate(count, (index) {
      return SubscriptionInstallmentInput(
        dueAt: _addUtcMonths(commandTimestamp, index),
        amountMinor: equalPart + (index < remainder ? BigInt.one : BigInt.zero),
      );
    }, growable: false);
  }

  static DateTime _addUtcMonths(DateTime source, int months) {
    final utc = source.toUtc();
    final zeroBasedMonth = utc.month - 1 + months;
    final year = utc.year + zeroBasedMonth ~/ 12;
    final month = zeroBasedMonth % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = utc.day > lastDay ? lastDay : utc.day;
    return DateTime.utc(
      year,
      month,
      day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
      utc.microsecond,
    );
  }
}
