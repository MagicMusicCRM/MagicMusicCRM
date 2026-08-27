part of 'magic_crm_service.dart';

enum ClientPaymentStatus {
  unpaid('unpaid'),
  postedPending('posted_pending'),
  paid('paid');

  const ClientPaymentStatus(this.apiValue);
  final String apiValue;
}

class CreateClientPaymentRecordInput {
  const CreateClientPaymentRecordInput({
    required this.amountMinor,
    required this.status,
    required this.reason,
    this.issuedSubscriptionId,
    this.currencyCode = 'RUB',
    this.dueAt,
    this.method,
    this.externalIdentifier,
    this.occurredAt,
    this.branchId,
    this.verificationNote,
  });

  final String? issuedSubscriptionId;
  final BigInt amountMinor;
  final String currencyCode;
  final ClientPaymentStatus status;
  final DateTime? dueAt;
  final SubscriptionPaymentMethod? method;
  final String? externalIdentifier;
  final DateTime? occurredAt;
  final String? branchId;
  final String? verificationNote;
  final String reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (issuedSubscriptionId != null)
      'issuedSubscriptionId': issuedSubscriptionId,
    'amountMinor': amountMinor.toString(),
    'currencyCode': currencyCode,
    'status': status.apiValue,
    if (dueAt != null) 'dueAt': dueAt!.toUtc().toIso8601String(),
    if (method != null) 'method': method!.apiValue,
    if (externalIdentifier?.trim().isNotEmpty == true)
      'externalIdentifier': externalIdentifier!.trim(),
    if (occurredAt != null) 'occurredAt': occurredAt!.toUtc().toIso8601String(),
    if (branchId != null) 'branchId': branchId,
    if (verificationNote?.trim().isNotEmpty == true)
      'verificationNote': verificationNote!.trim(),
    'reason': reason.trim(),
  };
}

class TransitionClientPaymentRecordInput {
  const TransitionClientPaymentRecordInput({
    required this.expectedVersion,
    required this.targetStatus,
    required this.reason,
    this.method,
    this.externalIdentifier,
    this.occurredAt,
    this.branchId,
    this.verificationNote,
  });

  final int expectedVersion;
  final ClientPaymentStatus targetStatus;
  final SubscriptionPaymentMethod? method;
  final String? externalIdentifier;
  final DateTime? occurredAt;
  final String? branchId;
  final String? verificationNote;
  final String reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'expectedVersion': expectedVersion,
    'targetStatus': targetStatus.apiValue,
    if (method != null) 'method': method!.apiValue,
    if (externalIdentifier?.trim().isNotEmpty == true)
      'externalIdentifier': externalIdentifier!.trim(),
    if (occurredAt != null) 'occurredAt': occurredAt!.toUtc().toIso8601String(),
    if (branchId != null) 'branchId': branchId,
    if (verificationNote?.trim().isNotEmpty == true)
      'verificationNote': verificationNote!.trim(),
    'reason': reason.trim(),
  };
}

class PaymentReversalPreview {
  const PaymentReversalPreview({
    required this.paymentRecordId,
    required this.status,
    required this.amountMinor,
    required this.currencyCode,
    required this.walletDeltaMinor,
    required this.walletBalanceMinor,
    required this.resultingBalanceMinor,
    required this.negativeBalanceWarning,
    required this.operation,
    required this.previewToken,
  });

  final String paymentRecordId;
  final ClientPaymentStatus status;
  final BigInt amountMinor;
  final String currencyCode;
  final BigInt walletDeltaMinor;
  final BigInt walletBalanceMinor;
  final BigInt resultingBalanceMinor;
  final bool negativeBalanceWarning;
  final String operation;
  final String previewToken;

  factory PaymentReversalPreview.fromJson(Map<String, dynamic> json) {
    final status = ClientPaymentStatus.values.firstWhere(
      (item) => item.apiValue == json['status'],
    );
    return PaymentReversalPreview(
      paymentRecordId: json['paymentRecordId'].toString(),
      status: status,
      amountMinor: _replacementMinor(json['amountMinor']),
      currencyCode: json['currencyCode'].toString(),
      walletDeltaMinor: _replacementMinor(json['walletDeltaMinor']),
      walletBalanceMinor: _replacementMinor(json['walletBalanceMinor']),
      resultingBalanceMinor: _replacementMinor(json['resultingBalanceMinor']),
      negativeBalanceWarning: json['negativeBalanceWarning'] == true,
      operation: json['operation'].toString(),
      previewToken: json['previewToken'].toString(),
    );
  }
}

class PaymentCorrectionInput {
  const PaymentCorrectionInput({
    required this.expectedVersion,
    required this.amountMinor,
    required this.status,
    this.dueAt,
    this.method,
    this.externalIdentifier,
    this.occurredAt,
    this.branchId,
    this.verificationNote,
  });

  final int expectedVersion;
  final BigInt amountMinor;
  final ClientPaymentStatus status;
  final DateTime? dueAt;
  final SubscriptionPaymentMethod? method;
  final String? externalIdentifier;
  final DateTime? occurredAt;
  final String? branchId;
  final String? verificationNote;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'expectedVersion': expectedVersion,
    'amountMinor': amountMinor.toString(),
    'status': status.apiValue,
    if (dueAt != null) 'dueAt': dueAt!.toUtc().toIso8601String(),
    if (method != null) 'method': method!.apiValue,
    if (externalIdentifier?.trim().isNotEmpty == true)
      'externalIdentifier': externalIdentifier!.trim(),
    if (occurredAt != null) 'occurredAt': occurredAt!.toUtc().toIso8601String(),
    if (branchId != null) 'branchId': branchId,
    if (verificationNote?.trim().isNotEmpty == true)
      'verificationNote': verificationNote!.trim(),
  };
}

class PaymentCorrectionValues {
  const PaymentCorrectionValues({
    required this.amountMinor,
    required this.status,
    required this.dueAt,
    required this.method,
    required this.externalIdentifier,
    required this.occurredAt,
    required this.branchId,
    required this.verificationNote,
  });

  final BigInt amountMinor;
  final ClientPaymentStatus status;
  final DateTime? dueAt;
  final SubscriptionPaymentMethod? method;
  final String? externalIdentifier;
  final DateTime? occurredAt;
  final String? branchId;
  final String? verificationNote;

  factory PaymentCorrectionValues.fromJson(Map<String, dynamic> json) {
    return PaymentCorrectionValues(
      amountMinor: _replacementMinor(json['amountMinor']),
      status: ClientPaymentStatus.values.firstWhere(
        (item) => item.apiValue == json['status'],
      ),
      dueAt: json['dueAt'] == null
          ? null
          : DateTime.parse(json['dueAt'].toString()),
      method: json['method'] == null
          ? null
          : SubscriptionPaymentMethod.values.firstWhere(
              (item) => item.apiValue == json['method'],
            ),
      externalIdentifier: json['externalIdentifier']?.toString(),
      occurredAt: json['occurredAt'] == null
          ? null
          : DateTime.parse(json['occurredAt'].toString()),
      branchId: json['branchId']?.toString(),
      verificationNote: json['verificationNote']?.toString(),
    );
  }
}

class PaymentCorrectionPreview {
  const PaymentCorrectionPreview({
    required this.paymentRecordId,
    required this.expectedVersion,
    required this.currencyCode,
    required this.before,
    required this.after,
    required this.walletDeltaMinor,
    required this.walletBalanceMinor,
    required this.resultingBalanceMinor,
    required this.negativeBalanceWarning,
    required this.previewToken,
    required this.expiresAt,
  });

  final String paymentRecordId;
  final int expectedVersion;
  final String currencyCode;
  final PaymentCorrectionValues before;
  final PaymentCorrectionValues after;
  final BigInt walletDeltaMinor;
  final BigInt walletBalanceMinor;
  final BigInt resultingBalanceMinor;
  final bool negativeBalanceWarning;
  final String previewToken;
  final DateTime expiresAt;

  factory PaymentCorrectionPreview.fromJson(Map<String, dynamic> json) {
    return PaymentCorrectionPreview(
      paymentRecordId: json['paymentRecordId'].toString(),
      expectedVersion: _replacementInt(json['expectedVersion']),
      currencyCode: json['currencyCode'].toString(),
      before: PaymentCorrectionValues.fromJson(
        Map<String, dynamic>.from(json['before'] as Map),
      ),
      after: PaymentCorrectionValues.fromJson(
        Map<String, dynamic>.from(json['after'] as Map),
      ),
      walletDeltaMinor: _replacementMinor(json['walletDeltaMinor']),
      walletBalanceMinor: _replacementMinor(json['walletBalanceMinor']),
      resultingBalanceMinor: _replacementMinor(json['resultingBalanceMinor']),
      negativeBalanceWarning: json['negativeBalanceWarning'] == true,
      previewToken: json['previewToken'].toString(),
      expiresAt: DateTime.parse(json['expiresAt'].toString()),
    );
  }
}

class AccountAdjustmentReversalPreview {
  const AccountAdjustmentReversalPreview({
    required this.adjustmentId,
    required this.kind,
    required this.amountMinor,
    required this.currencyCode,
    required this.walletDeltaMinor,
    required this.walletBalanceMinor,
    required this.resultingBalanceMinor,
    required this.negativeBalanceWarning,
    required this.previewToken,
  });

  final String adjustmentId;
  final String kind;
  final BigInt amountMinor;
  final String currencyCode;
  final BigInt walletDeltaMinor;
  final BigInt walletBalanceMinor;
  final BigInt resultingBalanceMinor;
  final bool negativeBalanceWarning;
  final String previewToken;

  factory AccountAdjustmentReversalPreview.fromJson(
    Map<String, dynamic> json,
  ) => AccountAdjustmentReversalPreview(
    adjustmentId: json['adjustmentId'].toString(),
    kind: json['kind'].toString(),
    amountMinor: _replacementMinor(json['amountMinor']),
    currencyCode: json['currencyCode'].toString(),
    walletDeltaMinor: _replacementMinor(json['walletDeltaMinor']),
    walletBalanceMinor: _replacementMinor(json['walletBalanceMinor']),
    resultingBalanceMinor: _replacementMinor(json['resultingBalanceMinor']),
    negativeBalanceWarning: json['negativeBalanceWarning'] == true,
    previewToken: json['previewToken'].toString(),
  );
}

enum PaymentAdjustmentKind { refund, correction }

class RecordPaymentAdjustmentInput {
  const RecordPaymentAdjustmentInput({
    required this.sourcePaymentId,
    required this.kind,
    required this.amountMinor,
    required this.occurredAt,
    required this.reason,
    this.direction,
  });

  final String sourcePaymentId;
  final PaymentAdjustmentKind kind;
  final BigInt amountMinor;
  final DateTime occurredAt;
  final String reason;
  final String? direction;

  Map<String, dynamic> toJson() => {
    'sourcePaymentId': sourcePaymentId,
    'kind': kind.name,
    'amountMinor': amountMinor.toString(),
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'reason': reason.trim(),
    if (direction != null) 'direction': direction,
  };
}

enum SubscriptionFinancialPositionKind { debt, overpayment, settled }

class SubscriptionReplacementPackage {
  const SubscriptionReplacementPackage({
    required this.id,
    required this.version,
    required this.name,
    required this.unitCount,
  });

  final String id;
  final int version;
  final String name;
  final num unitCount;

  factory SubscriptionReplacementPackage.fromJson(Map<String, dynamic> json) {
    return SubscriptionReplacementPackage(
      id: json['id'].toString(),
      version: _replacementInt(json['version']),
      name: json['name'].toString(),
      unitCount: _replacementNum(json['unitCount']),
    );
  }
}

class SubscriptionReplacementUsage {
  const SubscriptionReplacementUsage({
    required this.usedUnits,
    required this.reservedLessonCount,
    required this.reservedUnits,
    required this.transferableReservationCount,
    required this.transferableReservationUnits,
    required this.releasedReservationCount,
    required this.releasedReservationUnits,
    required this.futureLessonCount,
    required this.futureUnits,
  });

  final String usedUnits;
  final int reservedLessonCount;
  final String reservedUnits;
  final int transferableReservationCount;
  final String transferableReservationUnits;
  final int releasedReservationCount;
  final String releasedReservationUnits;
  final int futureLessonCount;
  final String futureUnits;

  factory SubscriptionReplacementUsage.fromJson(Map<String, dynamic> json) {
    return SubscriptionReplacementUsage(
      usedUnits: json['usedUnits'].toString(),
      reservedLessonCount: _replacementInt(json['reservedLessonCount']),
      reservedUnits: json['reservedUnits'].toString(),
      transferableReservationCount: _replacementInt(
        json['transferableReservationCount'],
      ),
      transferableReservationUnits: json['transferableReservationUnits']
          .toString(),
      releasedReservationCount: _replacementInt(
        json['releasedReservationCount'],
      ),
      releasedReservationUnits: json['releasedReservationUnits'].toString(),
      futureLessonCount: _replacementInt(json['futureLessonCount']),
      futureUnits: json['futureUnits'].toString(),
    );
  }
}

class SubscriptionReplacementPosition {
  const SubscriptionReplacementPosition({
    required this.kind,
    required this.amountMinor,
  });

  final SubscriptionFinancialPositionKind kind;
  final BigInt amountMinor;

  factory SubscriptionReplacementPosition.fromJson(Map<String, dynamic> json) {
    final kind = switch (json['kind']?.toString()) {
      'debt' => SubscriptionFinancialPositionKind.debt,
      'overpayment' => SubscriptionFinancialPositionKind.overpayment,
      _ => SubscriptionFinancialPositionKind.settled,
    };
    return SubscriptionReplacementPosition(
      kind: kind,
      amountMinor: _replacementMinor(json['amountMinor']),
    );
  }
}

class SubscriptionReplacementFinancial {
  const SubscriptionReplacementFinancial({
    required this.currencyCode,
    required this.oldFinalMinor,
    required this.newFinalMinor,
    required this.actualPaidMinor,
    required this.obligationDeltaMinor,
    required this.resultingPosition,
  });

  final String currencyCode;
  final BigInt oldFinalMinor;
  final BigInt newFinalMinor;
  final BigInt actualPaidMinor;
  final BigInt obligationDeltaMinor;
  final SubscriptionReplacementPosition resultingPosition;

  factory SubscriptionReplacementFinancial.fromJson(Map<String, dynamic> json) {
    return SubscriptionReplacementFinancial(
      currencyCode: json['currencyCode'].toString(),
      oldFinalMinor: _replacementMinor(json['oldFinalMinor']),
      newFinalMinor: _replacementMinor(json['newFinalMinor']),
      actualPaidMinor: _replacementMinor(json['actualPaidMinor']),
      obligationDeltaMinor: _replacementMinor(json['obligationDeltaMinor']),
      resultingPosition: SubscriptionReplacementPosition.fromJson(
        _replacementMap(json['resultingPosition']),
      ),
    );
  }
}

class SubscriptionReplacementWarning {
  const SubscriptionReplacementWarning({
    required this.code,
    required this.message,
    this.count,
    this.units,
  });

  final String code;
  final String message;
  final int? count;
  final String? units;

  factory SubscriptionReplacementWarning.fromJson(Map<String, dynamic> json) {
    return SubscriptionReplacementWarning(
      code: json['code'].toString(),
      message: json['message'].toString(),
      count: json['count'] == null ? null : _replacementInt(json['count']),
      units: json['units']?.toString(),
    );
  }
}

class SubscriptionReplacementPreview {
  const SubscriptionReplacementPreview({
    required this.issuedSubscriptionId,
    required this.expectedVersion,
    required this.oldPackageId,
    required this.newPackage,
    required this.usage,
    required this.financial,
    required this.warnings,
    required this.previewToken,
    required this.expiresAt,
  });

  final String issuedSubscriptionId;
  final int expectedVersion;
  final String oldPackageId;
  final SubscriptionReplacementPackage newPackage;
  final SubscriptionReplacementUsage usage;
  final SubscriptionReplacementFinancial financial;
  final List<SubscriptionReplacementWarning> warnings;
  final String previewToken;
  final DateTime expiresAt;

  factory SubscriptionReplacementPreview.fromJson(Map<String, dynamic> json) {
    final warningItems = json['warnings'] is List
        ? json['warnings'] as List
        : const <dynamic>[];
    return SubscriptionReplacementPreview(
      issuedSubscriptionId: json['issuedSubscriptionId'].toString(),
      expectedVersion: _replacementInt(json['expectedVersion']),
      oldPackageId: json['oldPackageId'].toString(),
      newPackage: SubscriptionReplacementPackage.fromJson(
        _replacementMap(json['newPackage']),
      ),
      usage: SubscriptionReplacementUsage.fromJson(
        _replacementMap(json['usage']),
      ),
      financial: SubscriptionReplacementFinancial.fromJson(
        _replacementMap(json['financial']),
      ),
      warnings: warningItems
          .map(
            (item) =>
                SubscriptionReplacementWarning.fromJson(_replacementMap(item)),
          )
          .toList(growable: false),
      previewToken: json['previewToken'].toString(),
      expiresAt: DateTime.parse(json['expiresAt'].toString()),
    );
  }
}

class ReplaceSubscriptionInput {
  const ReplaceSubscriptionInput({
    required this.expectedVersion,
    required this.previewToken,
    required this.reason,
  });

  final int expectedVersion;
  final String previewToken;
  final String reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'expectedVersion': expectedVersion,
    'previewToken': previewToken,
    'confirm': true,
    'reason': reason.trim(),
  };
}

class SubscriptionReplacementReference {
  const SubscriptionReplacementReference({
    required this.oldSubscriptionId,
    required this.oldSubscriptionVersion,
    required this.newSubscriptionId,
    required this.newSubscriptionVersion,
    required this.newPackageId,
    required this.newPackageVersion,
    required this.usedUnits,
    required this.transferredReservationCount,
    required this.transferredReservationUnits,
    required this.releasedReservationCount,
    required this.releasedReservationUnits,
    required this.deltaMinor,
    required this.positionKind,
    required this.positionMinor,
    required this.currencyCode,
    this.obligationFactId,
  });

  final String oldSubscriptionId;
  final int oldSubscriptionVersion;
  final String newSubscriptionId;
  final int newSubscriptionVersion;
  final String newPackageId;
  final int newPackageVersion;
  final String usedUnits;
  final int transferredReservationCount;
  final String transferredReservationUnits;
  final int releasedReservationCount;
  final String releasedReservationUnits;
  final BigInt deltaMinor;
  final SubscriptionFinancialPositionKind positionKind;
  final BigInt positionMinor;
  final String currencyCode;
  final String? obligationFactId;

  factory SubscriptionReplacementReference.fromJson(Map<String, dynamic> json) {
    return SubscriptionReplacementReference(
      oldSubscriptionId: json['oldSubscriptionId'].toString(),
      oldSubscriptionVersion: _replacementInt(json['oldSubscriptionVersion']),
      newSubscriptionId: json['newSubscriptionId'].toString(),
      newSubscriptionVersion: _replacementInt(json['newSubscriptionVersion']),
      newPackageId: json['newPackageId'].toString(),
      newPackageVersion: _replacementInt(json['newPackageVersion']),
      usedUnits: json['usedUnits'].toString(),
      transferredReservationCount: _replacementInt(
        json['transferredReservationCount'],
      ),
      transferredReservationUnits: json['transferredReservationUnits']
          .toString(),
      releasedReservationCount: _replacementInt(
        json['releasedReservationCount'],
      ),
      releasedReservationUnits: json['releasedReservationUnits'].toString(),
      deltaMinor: _replacementMinor(json['deltaMinor']),
      positionKind: switch (json['positionKind']?.toString()) {
        'debt' => SubscriptionFinancialPositionKind.debt,
        'overpayment' => SubscriptionFinancialPositionKind.overpayment,
        _ => SubscriptionFinancialPositionKind.settled,
      },
      positionMinor: _replacementMinor(json['positionMinor']),
      currencyCode: json['ccy'].toString(),
      obligationFactId: json['obligationFactId']?.toString(),
    );
  }
}

class SubscriptionReplacementResult {
  const SubscriptionReplacementResult({
    required this.replacement,
    required this.replayed,
    required this.auditId,
    required this.eventId,
  });

  final SubscriptionReplacementReference replacement;
  final bool replayed;
  final String auditId;
  final String eventId;

  factory SubscriptionReplacementResult.fromJson(Map<String, dynamic> json) {
    return SubscriptionReplacementResult(
      replacement: SubscriptionReplacementReference.fromJson(
        _replacementMap(json['replacement']),
      ),
      replayed: json['replayed'] == true,
      auditId: json['auditId'].toString(),
      eventId: json['eventId'].toString(),
    );
  }
}

class SubscriptionCancellationPackage {
  const SubscriptionCancellationPackage({
    required this.id,
    required this.name,
    required this.unitCount,
  });

  final String id;
  final String name;
  final num unitCount;

  factory SubscriptionCancellationPackage.fromJson(Map<String, dynamic> json) {
    return SubscriptionCancellationPackage(
      id: json['id'].toString(),
      name: json['name'].toString(),
      unitCount: _replacementNum(json['unitCount']),
    );
  }
}

class SubscriptionCancellationUsage {
  const SubscriptionCancellationUsage({required this.usedUnits});

  final String usedUnits;

  factory SubscriptionCancellationUsage.fromJson(Map<String, dynamic> json) {
    return SubscriptionCancellationUsage(
      usedUnits: json['usedUnits'].toString(),
    );
  }
}

class SubscriptionCancellationFinancial {
  const SubscriptionCancellationFinancial({
    required this.currencyCode,
    required this.finalMinor,
    required this.actualPaidMinor,
    required this.writeoffMinor,
    required this.balanceMinor,
    required this.recommendedRefundMinor,
    required this.maximumRefundMinor,
  });

  final String currencyCode;
  final BigInt finalMinor;
  final BigInt actualPaidMinor;
  final BigInt writeoffMinor;
  final BigInt balanceMinor;
  final BigInt recommendedRefundMinor;
  final BigInt maximumRefundMinor;

  factory SubscriptionCancellationFinancial.fromJson(
    Map<String, dynamic> json,
  ) {
    return SubscriptionCancellationFinancial(
      currencyCode: json['currencyCode'].toString(),
      finalMinor: _replacementMinor(json['finalMinor']),
      actualPaidMinor: _replacementMinor(json['actualPaidMinor']),
      writeoffMinor: _replacementMinor(json['writeoffMinor']),
      balanceMinor: _replacementMinor(json['balanceMinor']),
      recommendedRefundMinor: _replacementMinor(json['recommendedRefundMinor']),
      maximumRefundMinor: _replacementMinor(json['maximumRefundMinor']),
    );
  }
}

class SubscriptionCancellationFutureLesson {
  const SubscriptionCancellationFutureLesson({
    required this.lessonId,
    required this.scheduledAt,
    required this.units,
    required this.reserved,
  });

  final String lessonId;
  final DateTime scheduledAt;
  final String units;
  final bool reserved;

  factory SubscriptionCancellationFutureLesson.fromJson(
    Map<String, dynamic> json,
  ) {
    return SubscriptionCancellationFutureLesson(
      lessonId: json['lessonId'].toString(),
      scheduledAt: DateTime.parse(json['scheduledAt'].toString()),
      units: json['units'].toString(),
      reserved: json['reserved'] == true,
    );
  }
}

class SubscriptionCancellationFuture {
  const SubscriptionCancellationFuture({
    required this.lessonCount,
    required this.reservedLessonCount,
    required this.reservedUnits,
    required this.lessons,
  });

  final int lessonCount;
  final int reservedLessonCount;
  final String reservedUnits;
  final List<SubscriptionCancellationFutureLesson> lessons;

  factory SubscriptionCancellationFuture.fromJson(Map<String, dynamic> json) {
    final lessonItems = json['lessons'] is List
        ? json['lessons'] as List
        : const <dynamic>[];
    return SubscriptionCancellationFuture(
      lessonCount: _replacementInt(json['lessonCount']),
      reservedLessonCount: _replacementInt(json['reservedLessonCount']),
      reservedUnits: json['reservedUnits'].toString(),
      lessons: lessonItems
          .map(
            (item) => SubscriptionCancellationFutureLesson.fromJson(
              _replacementMap(item),
            ),
          )
          .toList(growable: false),
    );
  }
}

class SubscriptionCancellationWarning {
  const SubscriptionCancellationWarning({
    required this.code,
    required this.message,
    this.count,
    this.units,
  });

  final String code;
  final String message;
  final int? count;
  final String? units;

  factory SubscriptionCancellationWarning.fromJson(Map<String, dynamic> json) {
    return SubscriptionCancellationWarning(
      code: json['code'].toString(),
      message: json['message'].toString(),
      count: json['count'] == null ? null : _replacementInt(json['count']),
      units: json['units']?.toString(),
    );
  }
}

class SubscriptionCancellationPreview {
  const SubscriptionCancellationPreview({
    required this.issuedSubscriptionId,
    required this.expectedVersion,
    required this.package,
    required this.usage,
    required this.financial,
    required this.future,
    required this.warnings,
    required this.previewToken,
    required this.expiresAt,
  });

  final String issuedSubscriptionId;
  final int expectedVersion;
  final SubscriptionCancellationPackage package;
  final SubscriptionCancellationUsage usage;
  final SubscriptionCancellationFinancial financial;
  final SubscriptionCancellationFuture future;
  final List<SubscriptionCancellationWarning> warnings;
  final String previewToken;
  final DateTime expiresAt;

  factory SubscriptionCancellationPreview.fromJson(Map<String, dynamic> json) {
    final warningItems = json['warnings'] is List
        ? json['warnings'] as List
        : const <dynamic>[];
    return SubscriptionCancellationPreview(
      issuedSubscriptionId: json['issuedSubscriptionId'].toString(),
      expectedVersion: _replacementInt(json['expectedVersion']),
      package: SubscriptionCancellationPackage.fromJson(
        _replacementMap(json['package']),
      ),
      usage: SubscriptionCancellationUsage.fromJson(
        _replacementMap(json['usage']),
      ),
      financial: SubscriptionCancellationFinancial.fromJson(
        _replacementMap(json['financial']),
      ),
      future: SubscriptionCancellationFuture.fromJson(
        _replacementMap(json['future']),
      ),
      warnings: warningItems
          .map(
            (item) =>
                SubscriptionCancellationWarning.fromJson(_replacementMap(item)),
          )
          .toList(growable: false),
      previewToken: json['previewToken'].toString(),
      expiresAt: DateTime.parse(json['expiresAt'].toString()),
    );
  }
}

class CancelSubscriptionInput {
  const CancelSubscriptionInput({
    required this.expectedVersion,
    required this.previewToken,
    required this.reason,
    required this.refundMinor,
  });

  final int expectedVersion;
  final String previewToken;
  final String reason;
  final BigInt refundMinor;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'expectedVersion': expectedVersion,
    'previewToken': previewToken,
    'confirm': true,
    'reason': reason.trim(),
    'refundMinor': refundMinor.toString(),
  };
}

class SubscriptionCancellationReference {
  const SubscriptionCancellationReference({
    required this.issuedSubscriptionId,
    required this.version,
    required this.status,
    required this.releasedReservationCount,
    required this.releasedReservationUnits,
    required this.futureLessonCount,
  });

  final String issuedSubscriptionId;
  final int version;
  final String status;
  final int releasedReservationCount;
  final String releasedReservationUnits;
  final int futureLessonCount;

  factory SubscriptionCancellationReference.fromJson(
    Map<String, dynamic> json,
  ) {
    return SubscriptionCancellationReference(
      issuedSubscriptionId: json['issuedSubscriptionId'].toString(),
      version: _replacementInt(json['version']),
      status: json['status'].toString(),
      releasedReservationCount: _replacementInt(
        json['releasedReservationCount'],
      ),
      releasedReservationUnits: json['releasedReservationUnits'].toString(),
      futureLessonCount: _replacementInt(json['futureLessonCount']),
    );
  }
}

class SubscriptionCancellationResult {
  const SubscriptionCancellationResult({
    required this.cancellation,
    required this.replayed,
    required this.auditId,
    required this.eventId,
  });

  final SubscriptionCancellationReference cancellation;
  final bool replayed;
  final String auditId;
  final String eventId;

  factory SubscriptionCancellationResult.fromJson(Map<String, dynamic> json) {
    return SubscriptionCancellationResult(
      cancellation: SubscriptionCancellationReference.fromJson(
        _replacementMap(json['cancellation']),
      ),
      replayed: json['replayed'] == true,
      auditId: json['auditId'].toString(),
      eventId: json['eventId'].toString(),
    );
  }
}

Map<String, dynamic> _replacementMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw const FormatException('Некорректный ответ замены абонемента.');
}

int _replacementInt(Object? value) =>
    value is int ? value : int.parse(value.toString());

num _replacementNum(Object? value) =>
    value is num ? value : num.parse(value.toString());

BigInt _replacementMinor(Object? value) => BigInt.parse(value.toString());

/// Finance: adjustments, payments, expenses, subscription packages,
/// homework, task status, analytics.
extension MagicCrmFinance on MagicCrmService {
  Future<Map<String, dynamic>> getV4ClientStatusSummary({
    String? clientType,
    String? status,
    String? branchId,
    String? from,
    String? to,
    String? q,
  }) {
    return _api.get<Map<String, dynamic>>(
      '/analytics/v4/client-status/summary',
      queryParameters: _v4ReportQuery(
        clientType: clientType,
        status: status,
        branchId: branchId,
        from: from,
        to: to,
        q: q,
      ),
    );
  }

  Future<Map<String, dynamic>> getV4ClientStatusList({
    required Map<String, dynamic> filter,
    int limit = 50,
    int offset = 0,
  }) {
    return _api.get<Map<String, dynamic>>(
      '/analytics/v4/client-status/clients',
      queryParameters: {
        ..._v4ReportQuery(
          clientType: filter['clientType']?.toString(),
          status: filter['status']?.toString(),
          branchId: filter['branchId']?.toString(),
          from: filter['from']?.toString(),
          to: filter['to']?.toString(),
          q: filter['q']?.toString(),
        ),
        'limit': limit,
        'offset': offset,
      },
    );
  }

  Future<Map<String, dynamic>> getV4LessonSuccess({
    String? branchId,
    String? from,
    String? to,
  }) {
    return _api.get<Map<String, dynamic>>(
      '/analytics/v4/lesson-success',
      queryParameters: _v4ReportQuery(branchId: branchId, from: from, to: to),
    );
  }

  Future<Map<String, dynamic>> getV4LessonSuccessList({
    required Map<String, dynamic> filter,
    int limit = 50,
    int offset = 0,
  }) {
    return _api.get<Map<String, dynamic>>(
      '/analytics/v4/lesson-success/lessons',
      queryParameters: {
        ..._v4ReportQuery(
          branchId: filter['branchId']?.toString(),
          from: filter['from']?.toString(),
          to: filter['to']?.toString(),
        ),
        'limit': limit,
        'offset': offset,
      },
    );
  }

  Future<Map<String, dynamic>> getV4SchoolFinance({
    String? branchId,
    String? from,
    String? to,
  }) {
    return _api.get<Map<String, dynamic>>(
      '/analytics/v4/school-finance',
      queryParameters: _v4ReportQuery(branchId: branchId, from: from, to: to),
    );
  }

  Future<V4ReportExportResult> requestV4ReportExport({
    required String reportKey,
    required String format,
    Map<String, dynamic> filter = const {},
  }) async {
    final bytes = await _api.postBytes(
      '/analytics/v4/exports',
      data: {
        'reportKey': reportKey,
        'format': format,
        ..._v4ReportQuery(
          clientType: filter['clientType']?.toString(),
          status: filter['status']?.toString(),
          branchId: filter['branchId']?.toString(),
          from: filter['from']?.toString(),
          to: filter['to']?.toString(),
          q: filter['q']?.toString(),
        ),
      },
    );
    final json = _tryV4ExportJson(bytes);
    if (json != null && json['mode'] == 'async') {
      return V4ReportExportResult.async(
        jobId: json['jobId'].toString(),
        status: json['status']?.toString() ?? 'queued',
        rowCount: (json['rowCount'] as num?)?.toInt() ?? 0,
      );
    }
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final base = reportKey == 'school_finance'
        ? 'school-finance'
        : 'client-status';
    return V4ReportExportResult.sync(
      bytes: bytes,
      filename: '$base-$stamp.$format',
    );
  }

  Future<V4ReportExportJob> getV4ReportExportJob(String jobId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/analytics/v4/exports/$jobId',
    );
    return V4ReportExportJob.fromJson(json);
  }

  Future<List<int>> downloadV4ReportExport(String jobId) {
    return _api.downloadBytes('/analytics/v4/exports/$jobId/download');
  }

  /// Downloads the monthly finance report (`csv`/`xlsx`) as raw bytes through
  /// the shared authenticated client. The caller only persists the bytes — the
  /// Bearer token, base URL and refresh handling stay inside [MagicApiClient].
  Future<List<int>> exportFinanceMonthly({
    required String format,
    required DateTime from,
    required DateTime to,
    String? branchId,
  }) {
    return _api.downloadBytes(
      '/analytics/finance/monthly.$format',
      queryParameters: <String, dynamic>{
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'branchId': ?branchId,
      },
    );
  }

  /// KVA-235: ручная операция личного счёта (возврат/корректировка).
  Future<Map<String, dynamic>> createAdjustment({
    required String studentId,
    required String kind,
    required num amount,
    String? direction,
    String? description,
    String? method,
    String? invoiceNumber,
    String? status,
  }) async {
    final data = <String, dynamic>{'kind': kind, 'amount': amount};
    if (direction != null) data['direction'] = direction;
    final trimmed = description?.trim();
    if (trimmed != null && trimmed.isNotEmpty) data['description'] = trimmed;
    if (method != null) data['method'] = method;
    final invoice = invoiceNumber?.trim();
    if (invoice != null && invoice.isNotEmpty) data['invoiceNumber'] = invoice;
    if (status != null) data['status'] = status;
    return _api.post<Map<String, dynamic>>(
      '/crm/students/$studentId/adjustments',
      data: data,
    );
  }

  /// Правка записи личного счёта. Передаются только изменённые поля —
  /// остальные сервер оставляет как есть.
  Future<Map<String, dynamic>> updateAdjustment({
    required String studentId,
    required String adjustmentId,
    num? amount,
    String? direction,
    String? description,
    String? method,
    String? invoiceNumber,
    String? status,
  }) async {
    final data = <String, dynamic>{};
    if (amount != null) data['amount'] = amount;
    if (direction != null) data['direction'] = direction;
    if (description != null) data['description'] = description.trim();
    if (method != null) data['method'] = method;
    if (invoiceNumber != null) data['invoiceNumber'] = invoiceNumber.trim();
    if (status != null) data['status'] = status;
    return _api.patch<Map<String, dynamic>>(
      '/crm/students/$studentId/adjustments/$adjustmentId',
      data: data,
    );
  }

  /// Отмена (сторно) записи личного счёта. Строка не исчезает: она остаётся в
  /// ленте зачёркнутой, но выпадает из баланса — иначе не осталось бы следа,
  /// кто и что убрал с клиентского счёта.
  Future<Map<String, dynamic>> voidAdjustment({
    required String studentId,
    required String adjustmentId,
  }) async {
    return _api.delete<Map<String, dynamic>>(
      '/crm/students/$studentId/adjustments/$adjustmentId',
    );
  }

  /// Own read-only commerce projection for the signed-in Client. Staff and
  /// Teacher surfaces must not use this endpoint.
  Future<ClientCommerceProjection> getMyCommerceProjection() async {
    final response = await _api.get<Map<String, dynamic>>('/crm/me/commerce');
    return ClientCommerceProjection.fromJson(response);
  }

  /// Actor-scoped commerce projection for one student card. The backend
  /// derives the projection profile from the current actor and resource scope.
  Future<StudentCommerceProjection> getStudentCommerceProjection(
    String studentId,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/students/$studentId/commerce',
    );
    return StudentCommerceProjection.fromJson(response);
  }

  Future<List<Payment>> listPayments({
    String? studentId,
    String? from,
    String? to,
    String? branchId,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (studentId != null) queryParameters['studentId'] = studentId;
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;
    if (branchId != null) queryParameters['branchId'] = branchId;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/payments',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyPayment).map(Payment.fromMap).toList();
  }

  /// Like [listPayments] but also returns the server-side period totals
  /// (`totalAmount`, `totalCount`) over the full filtered set, so the UI can
  /// show a correct «Итого» rather than summing a truncated page.
  Future<({List<Payment> items, num totalAmount, int totalCount})>
  listPaymentsWithTotal({
    String? from,
    String? to,
    String? studentId,
    String? branchId,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (studentId != null) queryParameters['studentId'] = studentId;
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;
    if (branchId != null) queryParameters['branchId'] = branchId;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/payments',
      queryParameters: queryParameters,
    );
    final items = _items(
      response,
    ).map(_legacyPayment).map(Payment.fromMap).toList();
    final totalAmount = response['totalAmount'];
    final totalCount = response['totalCount'];
    return (
      items: items,
      totalAmount: totalAmount is num
          ? totalAmount
          : num.tryParse(totalAmount?.toString() ?? '') ?? 0,
      totalCount: totalCount is int
          ? totalCount
          : int.tryParse(totalCount?.toString() ?? '') ?? items.length,
    );
  }

  Future<List<Map<String, dynamic>>> listStudentBalances({
    bool debtOnly = false,
    String? studentId,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{
      'debtOnly': debtOnly,
      'limit': limit,
    };
    if (studentId != null) queryParameters['studentId'] = studentId;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/student-balances',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyStudentBalance).toList();
  }

  // ── Expenses (P5-5) ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listExpenses({
    String? branchId,
    String? category,
    String? from,
    String? to,
    int? limit,
  }) async {
    final q = <String, dynamic>{};
    if (branchId != null) q['branchId'] = branchId;
    if (category != null) q['category'] = category;
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    if (limit != null) q['limit'] = limit;
    return _api.get<Map<String, dynamic>>('/crm/expenses', queryParameters: q);
  }

  Future<Map<String, dynamic>> createExpense({
    required num amount,
    required String category,
    String? description,
    String? branchId,
  }) async {
    final data = <String, dynamic>{'amount': amount, 'category': category};
    if (description != null && description.trim().isNotEmpty) {
      data['description'] = description.trim();
    }
    if (branchId != null && branchId.isNotEmpty) data['branchId'] = branchId;
    return _api.post<Map<String, dynamic>>('/crm/expenses', data: data);
  }

  Future<Map<String, dynamic>> updateExpense({
    required String expenseId,
    required num amount,
    required String category,
    String? description,
    String? branchId,
  }) {
    final data = <String, dynamic>{
      'amount': amount,
      'category': category,
      // An explicit empty string clears an existing optional description.
      'description': description?.trim() ?? '',
    };
    if (branchId != null && branchId.isNotEmpty) data['branchId'] = branchId;
    return _api.patch<Map<String, dynamic>>(
      '/crm/expenses/$expenseId',
      data: data,
    );
  }

  Future<Map<String, dynamic>> deleteExpense(String expenseId) {
    return _api.delete<Map<String, dynamic>>('/crm/expenses/$expenseId');
  }

  // ── Subscription packages (P5b) ─────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listSubscriptionPackages({
    String? q,
    int? limit,
    bool includeArchived = false,
  }) async {
    final query = <String, dynamic>{};
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (limit != null) query['limit'] = limit;
    if (includeArchived) query['includeArchived'] = true;
    final res = await _api.get<Map<String, dynamic>>(
      '/crm/subscription-packages',
      queryParameters: query,
    );
    return (res['items'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const [];
  }

  Future<Map<String, dynamic>> createSubscriptionPackage({
    required String name,
    required num lessonsTotal, // hours of lessons (fractional allowed)
    required num price,
    String? disciplineId,
    String? branchId,
    int? validityDays,
    int? sortOrder,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'unitCount': lessonsTotal,
      'basePriceMinor': subscriptionPriceMinor(price),
      'currencyCode': 'RUB',
    };
    if (disciplineId != null) data['disciplineId'] = disciplineId;
    if (branchId != null) data['branchId'] = branchId;
    if (validityDays != null) data['validityDays'] = validityDays;
    if (sortOrder != null) data['sortOrder'] = sortOrder;
    return _api.post<Map<String, dynamic>>(
      '/crm/subscription-packages',
      data: data,
    );
  }

  Future<Map<String, dynamic>> updateSubscriptionPackage(
    String id,
    Map<String, dynamic> patch, {
    required int expectedVersion,
  }) async {
    final data = <String, dynamic>{
      ...patch,
      'expectedVersion': expectedVersion,
    };
    return _api.patch<Map<String, dynamic>>(
      '/crm/subscription-packages/$id',
      data: data,
    );
  }

  Future<Map<String, dynamic>> archiveSubscriptionPackage(
    String id, {
    required int expectedVersion,
  }) {
    return _api.delete<Map<String, dynamic>>(
      '/crm/subscription-packages/$id',
      queryParameters: {'expectedVersion': expectedVersion},
    );
  }

  Future<Map<String, dynamic>> restoreSubscriptionPackage(
    String id, {
    required int expectedVersion,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/subscription-packages/$id/restore',
      queryParameters: {'expectedVersion': expectedVersion},
      data: const <String, dynamic>{},
    );
  }

  Future<SubscriptionPurchasePreview> previewSubscriptionPurchase(
    String recipientStudentId, {
    required PurchaseSubscriptionInput input,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/students/$recipientStudentId/subscriptions/purchase/preview',
      data: input.toJson(),
    );
    return SubscriptionPurchasePreview.fromJson(response);
  }

  Future<Map<String, dynamic>> purchaseSubscription(
    String recipientStudentId, {
    required PurchaseSubscriptionInput input,
    required SubscriptionPurchasePreview preview,
    required MagicMutationIdentity identity,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$recipientStudentId/subscriptions/purchase',
      identity: identity,
      data: <String, dynamic>{
        ...input.toJson(),
        'previewToken': preview.previewToken,
        'confirm': true,
      },
    );
  }

  Future<Map<String, dynamic>> createClientPaymentRecord(
    String studentId, {
    required CreateClientPaymentRecordInput input,
    required MagicMutationIdentity identity,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/payment-records',
      identity: identity,
      data: input.toJson(),
    );
  }

  Future<Map<String, dynamic>> transitionClientPaymentRecord(
    String studentId, {
    required String paymentRecordId,
    required TransitionClientPaymentRecordInput input,
    required MagicMutationIdentity identity,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/payment-records/$paymentRecordId/transition',
      identity: identity,
      data: input.toJson(),
    );
  }

  Future<PaymentReversalPreview> previewClientPaymentReversal(
    String studentId, {
    required String paymentRecordId,
    required int expectedVersion,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/students/$studentId/payment-records/'
      '$paymentRecordId/reversal/preview',
      data: <String, dynamic>{'expectedVersion': expectedVersion},
    );
    return PaymentReversalPreview.fromJson(response);
  }

  Future<PaymentCorrectionPreview> previewClientPaymentCorrection(
    String studentId, {
    required String paymentRecordId,
    required PaymentCorrectionInput input,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/students/$studentId/payment-records/'
      '$paymentRecordId/correction/preview',
      data: input.toJson(),
    );
    return PaymentCorrectionPreview.fromJson(response);
  }

  Future<Map<String, dynamic>> correctClientPayment(
    String studentId, {
    required String paymentRecordId,
    required PaymentCorrectionPreview preview,
    required String reason,
    required MagicMutationIdentity identity,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/payment-records/$paymentRecordId/correction',
      identity: identity,
      data: <String, dynamic>{
        'previewToken': preview.previewToken,
        'confirm': true,
        'reason': reason.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> reverseClientPayment(
    String studentId, {
    required String paymentRecordId,
    required PaymentReversalPreview preview,
    required String reason,
    required MagicMutationIdentity identity,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/payment-records/$paymentRecordId/reversal',
      identity: identity,
      data: <String, dynamic>{
        'previewToken': preview.previewToken,
        'confirm': true,
        'reason': reason.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> recordPaymentAdjustment(
    String studentId, {
    required RecordPaymentAdjustmentInput input,
    required MagicMutationIdentity identity,
  }) async {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/adjustments',
      identity: identity,
      data: input.toJson(),
    );
  }

  Future<AccountAdjustmentReversalPreview> previewAccountAdjustmentReversal(
    String studentId, {
    required String adjustmentId,
    required int expectedVersion,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/students/$studentId/adjustments/$adjustmentId/reversal/preview',
      data: <String, dynamic>{'expectedVersion': expectedVersion},
    );
    return AccountAdjustmentReversalPreview.fromJson(response);
  }

  Future<Map<String, dynamic>> reverseAccountAdjustment(
    String studentId, {
    required String adjustmentId,
    required AccountAdjustmentReversalPreview preview,
    required String reason,
    required MagicMutationIdentity identity,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/adjustments/$adjustmentId/reversal',
      identity: identity,
      data: <String, dynamic>{
        'previewToken': preview.previewToken,
        'confirm': true,
        'reason': reason.trim(),
      },
    );
  }

  Future<SubscriptionReplacementPreview> previewSubscriptionReplacement(
    String studentId, {
    required String issuedSubscriptionId,
    required String newPackageId,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/students/$studentId/subscriptions/'
      '$issuedSubscriptionId/replace/preview',
      data: <String, dynamic>{'newPackageId': newPackageId},
    );
    return SubscriptionReplacementPreview.fromJson(response);
  }

  Future<SubscriptionReplacementResult> replaceSubscription(
    String studentId, {
    required String issuedSubscriptionId,
    required ReplaceSubscriptionInput input,
    required MagicMutationIdentity identity,
  }) async {
    final response = await _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/subscriptions/'
      '$issuedSubscriptionId/replace',
      identity: identity,
      data: input.toJson(),
    );
    return SubscriptionReplacementResult.fromJson(response);
  }

  Future<SubscriptionCancellationPreview> previewSubscriptionCancellation(
    String studentId, {
    required String issuedSubscriptionId,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/students/$studentId/subscriptions/'
      '$issuedSubscriptionId/cancel/preview',
      data: const <String, dynamic>{},
    );
    return SubscriptionCancellationPreview.fromJson(response);
  }

  Future<SubscriptionCancellationResult> cancelSubscription(
    String studentId, {
    required String issuedSubscriptionId,
    required CancelSubscriptionInput input,
    required MagicMutationIdentity identity,
  }) async {
    final response = await _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/subscriptions/'
      '$issuedSubscriptionId/cancel',
      identity: identity,
      data: input.toJson(),
    );
    return SubscriptionCancellationResult.fromJson(response);
  }

  /// Issues the first subscription for a lead and converts it to a student in
  /// the same server transaction.  Keeping this separate from
  /// [issueSubscription] makes the product rule explicit: booking a trial (or
  /// assigning trial homework) never converts the lead; choosing the paid
  /// package does.
  Future<Map<String, dynamic>> issueLeadSubscription(
    String leadId,
    String packageId,
  ) async {
    return _api.post<Map<String, dynamic>>(
      '/crm/leads/$leadId/subscriptions/issue',
      data: {'packageId': packageId},
    );
  }

  // ── Homework (P5c) ───────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listHomeworks({
    String? studentId,
    String? leadId,
    String? lessonId,
    String? status,
    int? limit,
  }) async {
    final q = <String, dynamic>{};
    if (studentId != null) q['studentId'] = studentId;
    if (leadId != null) q['leadId'] = leadId;
    if (lessonId != null) q['lessonId'] = lessonId;
    if (status != null) q['status'] = status;
    if (limit != null) q['limit'] = limit;
    final res = await _api.get<Map<String, dynamic>>(
      '/crm/homeworks',
      queryParameters: q,
    );
    return (res['items'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const [];
  }

  Future<Map<String, dynamic>> createHomework({
    String? studentId,
    String? leadId,
    required String title,
    String? lessonId,
    String? description,
    String? dueAt,
  }) async {
    assert(
      (studentId == null) != (leadId == null),
      'Exactly one of studentId or leadId is required.',
    );
    final data = <String, dynamic>{'title': title};
    if (studentId != null) data['studentId'] = studentId;
    if (leadId != null) data['leadId'] = leadId;
    if (lessonId != null) data['lessonId'] = lessonId;
    if (description != null && description.trim().isNotEmpty) {
      data['description'] = description.trim();
    }
    if (dueAt != null) data['dueAt'] = dueAt;
    return _api.post<Map<String, dynamic>>('/crm/homeworks', data: data);
  }

  Future<Map<String, dynamic>> updateHomeworkStatus(
    String id,
    String status,
  ) async {
    return _api.patch<Map<String, dynamic>>(
      '/crm/homeworks/$id',
      data: {'status': status},
    );
  }

  Future<Map<String, dynamic>> submitHomework(String id) async {
    return _api.post<Map<String, dynamic>>(
      '/crm/homeworks/$id/submit',
      data: const <String, dynamic>{},
    );
  }

  // ── Analytics endpoints ───────────────────────────────────────────────

  Future<Map<String, dynamic>> getAnalyticsFunnel({
    String? from,
    String? to,
    String? branchId,
  }) async {
    final q = <String, dynamic>{};
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/funnel',
      queryParameters: q,
    );
  }

  // ── Analytics orphans wired (P5-7): sources / data-quality / responsible ──
  Future<Map<String, dynamic>> getAnalyticsSources({
    String? from,
    String? to,
    String? branchId,
  }) async {
    final q = <String, dynamic>{};
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/sources',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsDataQuality({
    String? branchId,
  }) async {
    final q = <String, dynamic>{};
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/data-quality',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsResponsible({
    String? from,
    String? to,
    String? branchId,
  }) async {
    final q = <String, dynamic>{};
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/responsible',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsFinanceMonthly({
    String? from,
    String? to,
    String? branchId,
  }) async {
    final q = <String, dynamic>{};
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/finance/monthly',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsBranches({
    String? from,
    String? to,
  }) async {
    final q = <String, dynamic>{};
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    return _api.get<Map<String, dynamic>>(
      '/analytics/branches',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsLossReasons({
    String? from,
    String? to,
    String? branchId,
  }) async {
    final q = <String, dynamic>{};
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/loss-reasons',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsDebts({String? branchId}) async {
    final q = <String, dynamic>{};
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/debts',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsForecast({String? branchId}) async {
    final q = <String, dynamic>{};
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/forecast',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsChurn({
    int? inactiveDays,
    String? branchId,
  }) async {
    final q = <String, dynamic>{};
    if (inactiveDays != null) q['inactiveDays'] = inactiveDays;
    if (branchId != null) q['branchId'] = branchId;
    return _api.get<Map<String, dynamic>>(
      '/analytics/churn-risk',
      queryParameters: q,
    );
  }

  Future<Map<String, dynamic>> getAnalyticsChatSla({
    String? from,
    String? to,
  }) async {
    final q = <String, dynamic>{};
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    return _api.get<Map<String, dynamic>>(
      '/analytics/chats/sla',
      queryParameters: q,
    );
  }
}

Map<String, dynamic> _v4ReportQuery({
  String? clientType,
  String? status,
  String? branchId,
  String? from,
  String? to,
  String? q,
}) {
  final result = <String, dynamic>{};
  void add(String key, String? value) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) result[key] = normalized;
  }

  add('clientType', clientType);
  add('status', status);
  add('branchId', branchId);
  add('from', from);
  add('to', to);
  add('q', q);
  return result;
}

Map<String, dynamic>? _tryV4ExportJson(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
  if (!text.startsWith('{')) return null;
  final decoded = jsonDecode(text);
  if (decoded is! Map) return null;
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

class V4ReportExportResult {
  const V4ReportExportResult._({
    required this.mode,
    this.bytes,
    this.filename,
    this.jobId,
    this.status,
    this.rowCount = 0,
  });

  const V4ReportExportResult.sync({
    required List<int> bytes,
    required String filename,
  }) : this._(mode: 'sync', bytes: bytes, filename: filename);

  const V4ReportExportResult.async({
    required String jobId,
    required String status,
    required int rowCount,
  }) : this._(mode: 'async', jobId: jobId, status: status, rowCount: rowCount);

  final String mode;
  final List<int>? bytes;
  final String? filename;
  final String? jobId;
  final String? status;
  final int rowCount;

  bool get isAsync => mode == 'async';
}

class V4ReportExportJob {
  const V4ReportExportJob({
    required this.id,
    required this.status,
    required this.rowCount,
    required this.downloadReady,
    this.filename,
    this.errorCode,
  });

  factory V4ReportExportJob.fromJson(Map<String, dynamic> json) {
    return V4ReportExportJob(
      id: json['id'].toString(),
      status: json['status']?.toString() ?? 'failed',
      rowCount: (json['rowCount'] as num?)?.toInt() ?? 0,
      downloadReady: json['downloadReady'] == true,
      filename: json['filename']?.toString(),
      errorCode: json['errorCode']?.toString(),
    );
  }

  final String id;
  final String status;
  final int rowCount;
  final bool downloadReady;
  final String? filename;
  final String? errorCode;
}

String subscriptionPriceMinor(num rubles) {
  final fixed = rubles.toStringAsFixed(2);
  return fixed.replaceAll('.', '');
}

List<Map<String, dynamic>> activeSubscriptionPackages(
  Iterable<Map<String, dynamic>> packages,
) {
  return packages
      .where((item) {
        final archivedAt = item['archivedAt'] ?? item['archived_at'];
        final active =
            item['active'] ?? item['isActive'] ?? item['is_active'] ?? true;
        return archivedAt == null && active == true;
      })
      .toList(growable: false);
}
