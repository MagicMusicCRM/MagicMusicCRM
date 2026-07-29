part of 'magic_crm_service.dart';

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

class IssueSubscriptionInput {
  const IssueSubscriptionInput({
    required this.packageId,
    this.discount,
    this.installments = const <SubscriptionInstallmentInput>[],
    this.paymentMethod,
  });

  final String packageId;
  final SubscriptionDiscountInput? discount;
  final List<SubscriptionInstallmentInput> installments;
  final SubscriptionPaymentMethod? paymentMethod;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'packageId': packageId,
    if (discount != null) 'discount': discount!.toJson(),
    if (installments.isNotEmpty)
      'installments': installments
          .map((installment) => installment.toJson())
          .toList(growable: false),
    if (paymentMethod != null) 'paymentMethod': paymentMethod!.apiValue,
  };
}

class RecordSubscriptionPaymentInput {
  const RecordSubscriptionPaymentInput({
    required this.amountMinor,
    required this.method,
    required this.occurredAt,
    this.issuedSubscriptionId,
    this.currencyCode,
  });

  final String? issuedSubscriptionId;
  final BigInt amountMinor;
  final SubscriptionPaymentMethod method;
  final DateTime occurredAt;
  final String? currencyCode;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (issuedSubscriptionId != null)
      'issuedSubscriptionId': issuedSubscriptionId,
    'amountMinor': amountMinor.toString(),
    'method': method.apiValue,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (currencyCode != null) 'currencyCode': currencyCode,
  };
}

/// Finance: adjustments, payments, expenses, subscription packages,
/// homework, task status, analytics.
extension MagicCrmFinance on MagicCrmService {
  /// Downloads the monthly finance report (`csv`/`xlsx`) as raw bytes through
  /// the shared authenticated client. The caller only persists the bytes — the
  /// Bearer token, base URL and refresh handling stay inside [MagicApiClient].
  Future<List<int>> exportFinanceMonthly({
    required String format,
    required DateTime from,
    required DateTime to,
  }) {
    return _api.downloadBytes(
      '/analytics/finance/monthly.$format',
      queryParameters: <String, dynamic>{
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
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

  Future<List<Payment>> listPayments({
    String? studentId,
    String? from,
    String? to,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (studentId != null) queryParameters['studentId'] = studentId;
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;

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
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (studentId != null) queryParameters['studentId'] = studentId;
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;

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

  Future<List<Map<String, dynamic>>> listExpectedPayments({
    required String studentId,
    int limit = 50,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/expected-payments',
      queryParameters: {'studentId': studentId, 'limit': limit},
    );
    return _items(response).map(_legacyExpectedPayment).toList();
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

  Future<Payment> createPayment({
    required String studentId,
    required num amount,
    required String paymentDate,
    String currency = 'RUB',
    String? method,
    String? externalId,
    String? notes,

    /// Занятие, за которое пришёл платёж (✔ владелец 17.07). Необязательно:
    /// пополнение счёта авансом ни к какому занятию не относится.
    String? lessonId,
  }) async {
    final data = <String, dynamic>{
      'studentId': studentId,
      'amount': amount,
      'paymentDate': paymentDate,
      'currency': currency,
    };
    if (lessonId != null && lessonId.trim().isNotEmpty) {
      data['lessonId'] = lessonId.trim();
    }
    if (method != null && method.trim().isNotEmpty) {
      data['method'] = method.trim();
    }
    if (externalId != null && externalId.trim().isNotEmpty) {
      data['externalId'] = externalId.trim();
    }
    if (notes != null && notes.trim().isNotEmpty) {
      data['notes'] = notes.trim();
    }

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/payments',
      data: data,
    );
    return Payment.fromMap(_legacyPayment(response));
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

  Future<Map<String, dynamic>> issueSubscription(
    String studentId, {
    required IssueSubscriptionInput input,
    required MagicMutationIdentity identity,
  }) async {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/subscriptions/issue',
      identity: identity,
      data: input.toJson(),
    );
  }

  Future<Map<String, dynamic>> recordSubscriptionPayment(
    String studentId, {
    required RecordSubscriptionPaymentInput input,
    required MagicMutationIdentity identity,
  }) async {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/students/$studentId/subscription-payments',
      identity: identity,
      data: input.toJson(),
    );
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

  Future<void> updateTaskStatus(String id, String status) async {
    await updateTask(id, status: status);
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
