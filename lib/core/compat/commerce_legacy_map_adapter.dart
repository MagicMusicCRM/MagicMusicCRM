part of '../models/commerce_projection.dart';

/// Compatibility boundary for finance presentation consumers that still expect
/// historical map shapes. It is a part to avoid a projection import cycle.
/// Remove when all consumers use the typed commerce projection directly.
class CommerceLegacyMapAdapter {
  const CommerceLegacyMapAdapter();

  Map<String, dynamic> balance(CommerceAccount account, String studentId) => {
    'student_id': studentId,
    'balance': _commerceMajor(account.balanceMinor),
    'total_paid': _commerceMajor(account.actualPaymentsMinor),
    'total_cost': _commerceMajor(account.writeOffsMinor),
  };

  Map<String, dynamic> subscription(
    CommerceSubscription subscription,
    String studentId,
  ) => {
    'id': subscription.id,
    'student_id': studentId,
    'lessons_total': subscription.units.total,
    'lessons_used': subscription.units.used,
    'lessons_remaining': subscription.units.remaining,
    'starts_at': subscription.startsAt.toIso8601String(),
    'expires_at': subscription.expiresAt?.toIso8601String(),
    'valid_until': subscription.expiresAt?.toIso8601String(),
    'status': subscription.status,
    'type': subscription.status == 'active' ? 'Абонемент' : subscription.status,
    'package_name': subscription.terms.displayName,
    'package_price': _commerceMajor(subscription.terms.finalPriceMinor),
    'final_price_minor': subscription.terms.finalPriceMinor.toString(),
    'paid_amount': _commerceMajor(subscription.financial.actualPaidMinor),
    'actual_paid_minor': subscription.financial.actualPaidMinor.toString(),
    'debt_minor': subscription.financial.debtMinor.toString(),
    'pending_minor': subscription.financial.pendingMinor.toString(),
    'overpayment_minor': subscription.financial.overpaymentMinor.toString(),
    'next_payment_at': subscription.financial.nextPaymentAt?.toIso8601String(),
    'base_price': _commerceMajor(subscription.terms.basePriceMinor),
    'currency_code': subscription.terms.currencyCode,
  };

  Map<String, dynamic> payment(CommerceMovement movement, String studentId) => {
    'id': movement.id,
    'student_id': studentId,
    'amount': _commerceMajor(movement.amountMinor),
    'currency': movement.currencyCode,
    'payment_date': movement.occurredAt.toIso8601String(),
    'method': movement.method,
    'type': movement.method,
    'description': movement.factType ?? movement.chargeType,
    'branch_id': movement.branchId,
    'branch_name': movement.branchName,
    'notes': movement.comment ?? movement.factType ?? movement.chargeType,
    'external_id': movement.invoiceIdentifier,
    'status': movement.status,
    'accepted_by_name': movement.acceptedByName,
    'students': {'id': studentId, 'first_name': '', 'last_name': ''},
  };
}
