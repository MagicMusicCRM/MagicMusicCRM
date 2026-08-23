import 'package:magic_music_crm/core/models/payment.dart';
import 'package:magic_music_crm/core/models/student_balance.dart';
import 'package:magic_music_crm/core/models/subscription.dart';

part '../compat/commerce_legacy_map_adapter.dart';

/// Actor-specific shape returned by the v4 commerce projection endpoints.
enum CommerceProjectionProfile {
  clientSelf('client_self'),
  teacherAssigned('teacher_assigned'),
  adminScoped('admin_scoped'),
  managerScoped('manager_scoped'),
  directorScoped('director_scoped'),
  systemAdminEmergency('system_admin_emergency');

  const CommerceProjectionProfile(this.apiValue);

  final String apiValue;

  factory CommerceProjectionProfile.fromJson(Object? raw) {
    final value = raw?.toString();
    return CommerceProjectionProfile.values.firstWhere(
      (profile) => profile.apiValue == value,
      orElse: () =>
          throw FormatException('Unknown commerce projection profile: $value'),
    );
  }
}

/// Read-only commerce envelope for a signed-in Client and all students linked
/// to that account. Flutter only obtains this shape from `GET /crm/me/commerce`.
class ClientCommerceProjection {
  const ClientCommerceProjection({
    required this.projection,
    required this.students,
  });

  final CommerceProjectionProfile projection;
  final List<CommerceStudent> students;

  factory ClientCommerceProjection.fromJson(Map<String, dynamic> json) {
    final projection = CommerceProjectionProfile.fromJson(json['projection']);
    if (projection != CommerceProjectionProfile.clientSelf) {
      throw FormatException(
        'Client commerce endpoint returned ${projection.apiValue}',
      );
    }
    return ClientCommerceProjection(
      projection: projection,
      students: _commerceMaps(
        json['students'],
      ).map(CommerceStudent.fromJson).toList(growable: false),
    );
  }

  CommerceStudent? studentById(String studentId) {
    for (final student in students) {
      if (student.studentId == studentId) return student;
    }
    return null;
  }
}

/// Scoped staff response for one student. The server chooses [projection] from
/// the effective actor policy; callers never send a profile themselves.
class StudentCommerceProjection {
  const StudentCommerceProjection({
    required this.projection,
    required this.student,
  });

  final CommerceProjectionProfile projection;
  final CommerceStudent student;

  factory StudentCommerceProjection.fromJson(Map<String, dynamic> json) {
    final rawStudent = json['student'];
    if (rawStudent is! Map) {
      throw const FormatException('Commerce student projection is missing');
    }
    return StudentCommerceProjection(
      projection: CommerceProjectionProfile.fromJson(json['projection']),
      student: CommerceStudent.fromJson(Map<String, dynamic>.from(rawStudent)),
    );
  }
}

class CommerceStudent {
  const CommerceStudent({
    required this.studentId,
    required this.accounts,
    required this.subscriptions,
    required this.movements,
    required this.technicalHistory,
    required this.lessonBalance,
  });

  final String studentId;
  final List<CommerceAccount> accounts;
  final List<CommerceSubscription> subscriptions;
  final List<CommerceMovement> movements;
  final List<CommerceTechnicalFinanceEvent> technicalHistory;
  final CommerceLessonBalance lessonBalance;

  factory CommerceStudent.fromJson(Map<String, dynamic> json) {
    final studentId = json['studentId']?.toString() ?? '';
    if (studentId.isEmpty) {
      throw const FormatException('Commerce projection has no studentId');
    }
    return CommerceStudent(
      studentId: studentId,
      accounts: _commerceMaps(
        json['accounts'],
      ).map(CommerceAccount.fromJson).toList(growable: false),
      subscriptions: _commerceMaps(
        json['subscriptions'],
      ).map(CommerceSubscription.fromJson).toList(growable: false),
      movements: _commerceMaps(
        json['movements'],
      ).map(CommerceMovement.fromJson).toList(growable: false),
      technicalHistory: _commerceMaps(
        json['technicalHistory'],
      ).map(CommerceTechnicalFinanceEvent.fromJson).toList(growable: false),
      lessonBalance: CommerceLessonBalance.fromJson(
        _commerceMap(json['lessonBalance'], 'lessonBalance'),
      ),
    );
  }

  /// Existing schedule/client-card widgets still consume the legacy typed
  /// models. These adapters are deliberately local to the projection: no
  /// global finance endpoint or base-card finance keys are consulted.
  List<Map<String, dynamic>> get legacySubscriptions => subscriptions
      .map((subscription) => subscription.toLegacyMap(studentId))
      .toList(growable: false);

  List<Subscription> get subscriptionModels =>
      legacySubscriptions.map(Subscription.fromMap).toList(growable: false);

  List<Payment> get paymentModels => movements
      .where((movement) => movement.kind == CommerceMovementKind.payment)
      .map((movement) => Payment.fromMap(movement.toLegacyPayment(studentId)))
      .toList(growable: false);

  StudentBalance? get primaryBalance {
    if (accounts.isEmpty) return null;
    final account = accounts.firstWhere(
      (item) => item.currencyCode == 'RUB',
      orElse: () => accounts.first,
    );
    return StudentBalance.fromMap(account.toLegacyBalance(studentId));
  }
}

class CommerceAccount {
  const CommerceAccount({
    required this.currencyCode,
    required this.actualPaymentsMinor,
    required this.adjustmentsMinor,
    required this.obligationDebitsMinor,
    required this.obligationCreditsMinor,
    required this.writeOffsMinor,
    required this.balanceMinor,
    required this.debtMinor,
    required this.pendingMinor,
    required this.remainingObligationMinor,
  });

  final String currencyCode;
  final BigInt actualPaymentsMinor;
  final BigInt adjustmentsMinor;
  final BigInt obligationDebitsMinor;
  final BigInt obligationCreditsMinor;
  final BigInt writeOffsMinor;
  final BigInt balanceMinor;
  final BigInt debtMinor;
  final BigInt pendingMinor;
  final BigInt remainingObligationMinor;

  factory CommerceAccount.fromJson(Map<String, dynamic> json) {
    return CommerceAccount(
      currencyCode: json['currencyCode']?.toString() ?? '',
      actualPaymentsMinor: _commerceMinor(
        json['actualPaymentsMinor'],
        'actualPaymentsMinor',
      ),
      adjustmentsMinor: _commerceMinor(
        json['adjustmentsMinor'],
        'adjustmentsMinor',
      ),
      obligationDebitsMinor: _commerceMinor(
        json['obligationDebitsMinor'],
        'obligationDebitsMinor',
      ),
      obligationCreditsMinor: _commerceMinor(
        json['obligationCreditsMinor'],
        'obligationCreditsMinor',
      ),
      writeOffsMinor: _commerceMinor(json['writeOffsMinor'], 'writeOffsMinor'),
      balanceMinor: _commerceMinor(json['balanceMinor'], 'balanceMinor'),
      debtMinor: _commerceMinor(json['debtMinor'], 'debtMinor'),
      pendingMinor: _commerceOptionalMinor(json['pendingMinor']),
      remainingObligationMinor: _commerceOptionalMinor(
        json['remainingObligationMinor'],
      ),
    );
  }

  Map<String, dynamic> toLegacyBalance(String studentId) =>
      const CommerceLegacyMapAdapter().balance(this, studentId);
}

class CommerceSubscription {
  const CommerceSubscription({
    required this.id,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.units,
    required this.financial,
    required this.terms,
    required this.installments,
  });

  final String id;
  final String status;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final CommerceSubscriptionUnits units;
  final CommerceSubscriptionFinancial financial;
  final CommerceSubscriptionTerms terms;
  final List<CommerceInstallment> installments;

  factory CommerceSubscription.fromJson(Map<String, dynamic> json) {
    return CommerceSubscription(
      id: _commerceRequiredString(json, 'id'),
      status: _commerceRequiredString(json, 'status'),
      startsAt: _commerceDate(json['startsAt'], 'startsAt'),
      expiresAt: json['expiresAt'] == null
          ? null
          : _commerceDate(json['expiresAt'], 'expiresAt'),
      units: CommerceSubscriptionUnits.fromJson(
        _commerceMap(json['units'], 'units'),
      ),
      financial: CommerceSubscriptionFinancial.fromJson(
        _commerceMap(json['financial'], 'financial'),
      ),
      terms: CommerceSubscriptionTerms.fromJson(
        _commerceMap(json['terms'], 'terms'),
      ),
      installments: _commerceMaps(
        json['installments'],
      ).map(CommerceInstallment.fromJson).toList(growable: false),
    );
  }

  Map<String, dynamic> toLegacyMap(String studentId) =>
      const CommerceLegacyMapAdapter().subscription(this, studentId);
}

class CommerceSubscriptionUnits {
  const CommerceSubscriptionUnits({
    required this.total,
    required this.used,
    required this.reserved,
    required this.paid,
    required this.available,
    required this.remaining,
  });

  final num total;
  final num used;
  final num reserved;
  final num paid;
  final num available;
  final num remaining;

  factory CommerceSubscriptionUnits.fromJson(Map<String, dynamic> json) {
    return CommerceSubscriptionUnits(
      total: _commerceNumber(json['total'], 'units.total'),
      used: _commerceNumber(json['used'], 'units.used'),
      reserved: _commerceNumber(json['reserved'], 'units.reserved'),
      paid: _commerceNumber(json['paid'], 'units.paid'),
      available: _commerceNumber(json['available'], 'units.available'),
      remaining: _commerceNumber(json['remaining'], 'units.remaining'),
    );
  }
}

class CommerceSubscriptionFinancial {
  const CommerceSubscriptionFinancial({
    required this.actualPaidMinor,
    required this.obligationMinor,
    required this.debtMinor,
    required this.pendingMinor,
    required this.remainingObligationMinor,
    required this.overpaymentMinor,
    required this.nextPaymentAt,
  });

  final BigInt actualPaidMinor;
  final BigInt obligationMinor;
  final BigInt debtMinor;
  final BigInt pendingMinor;
  final BigInt remainingObligationMinor;
  final BigInt overpaymentMinor;
  final DateTime? nextPaymentAt;

  factory CommerceSubscriptionFinancial.fromJson(Map<String, dynamic> json) {
    return CommerceSubscriptionFinancial(
      actualPaidMinor: _commerceMinor(
        json['actualPaidMinor'],
        'financial.actualPaidMinor',
      ),
      obligationMinor: _commerceMinor(
        json['obligationMinor'],
        'financial.obligationMinor',
      ),
      debtMinor: _commerceMinor(json['debtMinor'], 'financial.debtMinor'),
      pendingMinor: _commerceOptionalMinor(json['pendingMinor']),
      remainingObligationMinor: _commerceOptionalMinor(
        json['remainingObligationMinor'],
      ),
      overpaymentMinor: _commerceMinor(
        json['overpaymentMinor'],
        'financial.overpaymentMinor',
      ),
      nextPaymentAt: json['nextPaymentAt'] == null
          ? null
          : _commerceDate(json['nextPaymentAt'], 'financial.nextPaymentAt'),
    );
  }
}

class CommerceSubscriptionTerms {
  const CommerceSubscriptionTerms({
    required this.displayName,
    required this.validityDays,
    required this.basePriceMinor,
    required this.finalPriceMinor,
    required this.currencyCode,
    required this.discount,
    required this.surcharge,
  });

  final String displayName;
  final int? validityDays;
  final BigInt basePriceMinor;
  final BigInt finalPriceMinor;
  final String currencyCode;
  final CommerceDiscount discount;
  final CommerceSurcharge surcharge;

  factory CommerceSubscriptionTerms.fromJson(Map<String, dynamic> json) {
    final rawValidity = json['validityDays'];
    return CommerceSubscriptionTerms(
      displayName: _commerceRequiredString(json, 'displayName'),
      validityDays: rawValidity == null
          ? null
          : _commerceInt(rawValidity, 'validityDays'),
      basePriceMinor: _commerceMinor(json['basePriceMinor'], 'basePriceMinor'),
      finalPriceMinor: _commerceMinor(
        json['finalPriceMinor'],
        'finalPriceMinor',
      ),
      currencyCode: _commerceRequiredString(json, 'currencyCode'),
      discount: CommerceDiscount.fromJson(
        _commerceMap(json['discount'], 'discount'),
      ),
      surcharge: CommerceSurcharge.fromJson(
        json['surcharge'] is Map
            ? Map<String, dynamic>.from(json['surcharge'] as Map)
            : const <String, dynamic>{'type': 'none'},
      ),
    );
  }
}

class CommerceSurcharge {
  const CommerceSurcharge({required this.amountMinor, this.reason});

  final BigInt amountMinor;
  final String? reason;

  factory CommerceSurcharge.fromJson(Map<String, dynamic> json) {
    if (json['type']?.toString() != 'fixed') {
      return CommerceSurcharge(amountMinor: BigInt.zero);
    }
    return CommerceSurcharge(
      amountMinor: _commerceMinor(json['amountMinor'], 'surcharge.amountMinor'),
      reason: json['reason']?.toString(),
    );
  }
}

enum CommerceDiscountKind { none, percent, fixed }

class CommerceDiscount {
  const CommerceDiscount({
    required this.kind,
    this.percentBasisPoints,
    this.fixedMinor,
    this.reason,
  });

  final CommerceDiscountKind kind;
  final int? percentBasisPoints;
  final BigInt? fixedMinor;

  /// Intentionally optional: the Client projection never contains the reason.
  final String? reason;

  factory CommerceDiscount.fromJson(Map<String, dynamic> json) {
    final reason = json['reason']?.toString();
    return switch (json['type']?.toString()) {
      'none' => const CommerceDiscount(kind: CommerceDiscountKind.none),
      'percent' => CommerceDiscount(
        kind: CommerceDiscountKind.percent,
        percentBasisPoints: _commerceInt(
          json['percentBasisPoints'],
          'percentBasisPoints',
        ),
        reason: reason,
      ),
      'fixed' => CommerceDiscount(
        kind: CommerceDiscountKind.fixed,
        fixedMinor: _commerceMinor(json['fixedMinor'], 'fixedMinor'),
        reason: reason,
      ),
      final value => throw FormatException(
        'Unknown commerce discount type: $value',
      ),
    };
  }
}

class CommerceInstallment {
  const CommerceInstallment({
    required this.installmentNumber,
    required this.dueAt,
    required this.amountMinor,
    required this.currencyCode,
    required this.status,
  });

  final int installmentNumber;
  final DateTime dueAt;
  final BigInt amountMinor;
  final String currencyCode;
  final String status;

  factory CommerceInstallment.fromJson(Map<String, dynamic> json) {
    return CommerceInstallment(
      installmentNumber: _commerceInt(
        json['installmentNumber'],
        'installmentNumber',
      ),
      dueAt: _commerceDate(json['dueAt'], 'dueAt'),
      amountMinor: _commerceMinor(json['amountMinor'], 'amountMinor'),
      currencyCode: _commerceRequiredString(json, 'currencyCode'),
      status: _commerceRequiredString(json, 'status'),
    );
  }
}

enum CommerceMovementKind {
  payment('payment'),
  paymentRecord('payment_record'),
  refund('refund'),
  adjustment('adjustment'),
  obligation('obligation'),
  lessonCharge('lesson_charge');

  const CommerceMovementKind(this.apiValue);
  final String apiValue;

  factory CommerceMovementKind.fromJson(Object? raw) {
    final value = raw?.toString();
    return CommerceMovementKind.values.firstWhere(
      (kind) => kind.apiValue == value,
      orElse: () =>
          throw FormatException('Unknown commerce movement kind: $value'),
    );
  }
}

enum CommerceMovementDirection {
  credit('credit'),
  debit('debit');

  const CommerceMovementDirection(this.apiValue);
  final String apiValue;

  factory CommerceMovementDirection.fromJson(Object? raw) {
    final value = raw?.toString();
    return CommerceMovementDirection.values.firstWhere(
      (direction) => direction.apiValue == value,
      orElse: () =>
          throw FormatException('Unknown commerce movement direction: $value'),
    );
  }
}

class CommerceMovement {
  const CommerceMovement({
    required this.id,
    required this.kind,
    required this.direction,
    required this.amountMinor,
    required this.currencyCode,
    required this.occurredAt,
    required this.method,
    required this.factType,
    required this.chargeType,
    required this.branchId,
    required this.branchName,
    required this.comment,
    required this.invoiceIdentifier,
    required this.status,
    required this.acceptedByName,
    required this.issuedSubscriptionId,
    required this.subscriptionName,
    required this.sourcePaymentId,
    this.adjustmentVersion,
    required this.paymentRecordVersion,
    required this.installmentId,
    required this.dueAt,
  });

  final String id;
  final CommerceMovementKind kind;
  final CommerceMovementDirection direction;
  final BigInt amountMinor;
  final String currencyCode;
  final DateTime occurredAt;
  final String? method;
  final String? factType;
  final String? chargeType;
  final String? branchId;
  final String? branchName;
  final String? comment;
  final String? invoiceIdentifier;
  final String? status;
  final String? acceptedByName;
  final String? issuedSubscriptionId;
  final String? subscriptionName;
  final String? sourcePaymentId;
  final int? adjustmentVersion;
  final int? paymentRecordVersion;
  final String? installmentId;
  final DateTime? dueAt;

  factory CommerceMovement.fromJson(Map<String, dynamic> json) {
    return CommerceMovement(
      id: _commerceRequiredString(json, 'id'),
      kind: CommerceMovementKind.fromJson(json['kind']),
      direction: CommerceMovementDirection.fromJson(json['direction']),
      amountMinor: _commerceMinor(json['amountMinor'], 'amountMinor'),
      currencyCode: _commerceRequiredString(json, 'currencyCode'),
      occurredAt: _commerceDate(json['occurredAt'], 'occurredAt'),
      method: json['method']?.toString(),
      factType: json['factType']?.toString(),
      chargeType: json['chargeType']?.toString(),
      branchId: json['branchId']?.toString(),
      branchName: json['branchName']?.toString(),
      comment: json['comment']?.toString(),
      invoiceIdentifier: json['invoiceIdentifier']?.toString(),
      status: json['status']?.toString(),
      acceptedByName: json['acceptedByName']?.toString(),
      issuedSubscriptionId: json['issuedSubscriptionId']?.toString(),
      subscriptionName: json['subscriptionName']?.toString(),
      sourcePaymentId: json['sourcePaymentId']?.toString(),
      adjustmentVersion: json['adjustmentVersion'] == null
          ? null
          : _commerceInt(json['adjustmentVersion'], 'adjustmentVersion'),
      paymentRecordVersion: json['paymentRecordVersion'] == null
          ? null
          : _commerceInt(json['paymentRecordVersion'], 'paymentRecordVersion'),
      installmentId: json['installmentId']?.toString(),
      dueAt: json['dueAt'] == null
          ? null
          : _commerceDate(json['dueAt'], 'dueAt'),
    );
  }

  Map<String, dynamic> toLegacyPayment(String studentId) =>
      const CommerceLegacyMapAdapter().payment(this, studentId);
}

class CommerceTechnicalFinanceEvent {
  const CommerceTechnicalFinanceEvent({
    required this.id,
    required this.eventType,
    required this.paymentRecordId,
    required this.previousStatus,
    required this.amountMinor,
    required this.currencyCode,
    required this.reason,
    required this.actorName,
    required this.occurredAt,
  });

  final String id;
  final String eventType;
  final String? paymentRecordId;
  final String? previousStatus;
  final BigInt amountMinor;
  final String currencyCode;
  final String reason;
  final String? actorName;
  final DateTime occurredAt;

  factory CommerceTechnicalFinanceEvent.fromJson(Map<String, dynamic> json) {
    return CommerceTechnicalFinanceEvent(
      id: _commerceRequiredString(json, 'id'),
      eventType: _commerceRequiredString(json, 'eventType'),
      paymentRecordId: json['paymentRecordId']?.toString(),
      previousStatus: json['previousStatus']?.toString(),
      amountMinor: _commerceMinor(json['amountMinor'], 'amountMinor'),
      currencyCode: _commerceRequiredString(json, 'currencyCode'),
      reason: _commerceRequiredString(json, 'reason'),
      actorName: json['actorName']?.toString(),
      occurredAt: _commerceDate(json['occurredAt'], 'occurredAt'),
    );
  }
}

class CommerceLessonBalance {
  const CommerceLessonBalance({
    required this.activeSubscriptionCount,
    required this.total,
    required this.used,
    required this.reserved,
    required this.paid,
    required this.available,
    required this.debts,
    required this.nextPaymentAt,
    required this.expiresAt,
  });

  final int activeSubscriptionCount;
  final num total;
  final num used;
  final num reserved;
  final num paid;
  final num available;
  final List<CommerceLessonDebt> debts;
  final DateTime? nextPaymentAt;
  final DateTime? expiresAt;

  factory CommerceLessonBalance.fromJson(Map<String, dynamic> json) {
    return CommerceLessonBalance(
      activeSubscriptionCount: _commerceInt(
        json['activeSubscriptionCount'],
        'lessonBalance.activeSubscriptionCount',
      ),
      total: _commerceNumber(json['total'], 'lessonBalance.total'),
      used: _commerceNumber(json['used'], 'lessonBalance.used'),
      reserved: _commerceNumber(json['reserved'], 'lessonBalance.reserved'),
      paid: _commerceNumber(json['paid'], 'lessonBalance.paid'),
      available: _commerceNumber(json['available'], 'lessonBalance.available'),
      debts: _commerceMaps(
        json['debts'],
      ).map(CommerceLessonDebt.fromJson).toList(growable: false),
      nextPaymentAt: json['nextPaymentAt'] == null
          ? null
          : _commerceDate(json['nextPaymentAt'], 'lessonBalance.nextPaymentAt'),
      expiresAt: json['expiresAt'] == null
          ? null
          : _commerceDate(json['expiresAt'], 'lessonBalance.expiresAt'),
    );
  }
}

class CommerceLessonDebt {
  const CommerceLessonDebt({
    required this.currencyCode,
    required this.amountMinor,
  });

  final String currencyCode;
  final BigInt amountMinor;

  factory CommerceLessonDebt.fromJson(Map<String, dynamic> json) {
    return CommerceLessonDebt(
      currencyCode: _commerceRequiredString(json, 'currencyCode'),
      amountMinor: _commerceMinor(json['amountMinor'], 'amountMinor'),
    );
  }
}

List<Map<String, dynamic>> _commerceMaps(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

Map<String, dynamic> _commerceMap(Object? raw, String field) {
  if (raw is! Map) {
    throw FormatException('Commerce field $field must be an object');
  }
  return Map<String, dynamic>.from(raw);
}

String _commerceRequiredString(Map<String, dynamic> json, String field) {
  final value = json[field]?.toString() ?? '';
  if (value.isEmpty) {
    throw FormatException('Commerce field $field is required');
  }
  return value;
}

BigInt _commerceMinor(Object? raw, String field) {
  final value = BigInt.tryParse(raw?.toString() ?? '');
  if (value == null) {
    throw FormatException('Commerce field $field must be an integer string');
  }
  return value;
}

BigInt _commerceOptionalMinor(Object? raw) =>
    raw == null ? BigInt.zero : BigInt.parse(raw.toString());

int _commerceInt(Object? raw, String field) {
  final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  if (value == null) {
    throw FormatException('Commerce field $field must be an integer');
  }
  return value;
}

num _commerceNumber(Object? raw, String field) {
  final value = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  if (value == null) {
    throw FormatException('Commerce field $field must be numeric');
  }
  return value;
}

DateTime _commerceDate(Object? raw, String field) {
  final value = DateTime.tryParse(raw?.toString() ?? '');
  if (value == null) {
    throw FormatException('Commerce field $field must be an ISO timestamp');
  }
  return value;
}

num _commerceMajor(BigInt minor) {
  final whole = minor ~/ BigInt.from(100);
  final remainder = minor.remainder(BigInt.from(100)).abs();
  if (remainder == BigInt.zero) return whole.toInt();
  return minor.toInt() / 100;
}
