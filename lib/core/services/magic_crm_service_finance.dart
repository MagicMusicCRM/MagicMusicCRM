part of 'magic_crm_service.dart';

/// Finance: adjustments, payments, expenses, subscription packages,
/// homework, task status, analytics.
extension MagicCrmFinance on MagicCrmService {
  /// KVA-235: ручная операция личного счёта (возврат/корректировка).
  Future<Map<String, dynamic>> createAdjustment({
    required String studentId,
    required String kind,
    required num amount,
    String? direction,
    String? description,
    String? method,
  }) async {
    final data = <String, dynamic>{'kind': kind, 'amount': amount};
    if (direction != null) data['direction'] = direction;
    final trimmed = description?.trim();
    if (trimmed != null && trimmed.isNotEmpty) data['description'] = trimmed;
    if (method != null) data['method'] = method;
    return _api.post<Map<String, dynamic>>(
      '/crm/students/$studentId/adjustments',
      data: data,
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
  }) async {
    final data = <String, dynamic>{
      'studentId': studentId,
      'amount': amount,
      'paymentDate': paymentDate,
      'currency': currency,
    };
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
  }) async {
    final query = <String, dynamic>{};
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (limit != null) query['limit'] = limit;
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
    bool? isActive,
    int? sortOrder,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'lessonsTotal': lessonsTotal,
      'price': price,
    };
    if (disciplineId != null) data['disciplineId'] = disciplineId;
    if (branchId != null) data['branchId'] = branchId;
    if (validityDays != null) data['validityDays'] = validityDays;
    if (isActive != null) data['isActive'] = isActive;
    if (sortOrder != null) data['sortOrder'] = sortOrder;
    return _api.post<Map<String, dynamic>>(
      '/crm/subscription-packages',
      data: data,
    );
  }

  Future<Map<String, dynamic>> updateSubscriptionPackage(
    String id,
    Map<String, dynamic> patch,
  ) async {
    return _api.patch<Map<String, dynamic>>(
      '/crm/subscription-packages/$id',
      data: patch,
    );
  }

  Future<void> deleteSubscriptionPackage(String id) async {
    await _api.delete<Map<String, dynamic>>('/crm/subscription-packages/$id');
  }

  Future<Map<String, dynamic>> issueSubscription(
    String studentId,
    String packageId,
  ) async {
    return _api.post<Map<String, dynamic>>(
      '/crm/students/$studentId/subscriptions/issue',
      data: {'packageId': packageId},
    );
  }

  // ── Homework (P5c) ───────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listHomeworks({
    String? studentId,
    String? lessonId,
    String? status,
    int? limit,
  }) async {
    final q = <String, dynamic>{};
    if (studentId != null) q['studentId'] = studentId;
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
    required String studentId,
    required String title,
    String? lessonId,
    String? description,
    String? dueAt,
  }) async {
    final data = <String, dynamic>{'studentId': studentId, 'title': title};
    if (lessonId != null) data['lessonId'] = lessonId;
    if (description != null && description.trim().isNotEmpty) {
      data['description'] = description.trim();
    }
    if (dueAt != null) data['dueAt'] = dueAt;
    return _api.post<Map<String, dynamic>>('/crm/homeworks', data: data);
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
