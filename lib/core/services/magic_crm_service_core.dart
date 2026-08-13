part of 'magic_crm_service.dart';

/// Core: current-user summary, students, teachers, staff, activity log.
extension MagicCrmCore on MagicCrmService {
  Future<ClientInternalNote> getClientInternalNote({
    required String clientType,
    required String clientId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/clients/$clientType/$clientId/internal-note',
    );
    return ClientInternalNote.fromJson(response);
  }

  Future<ClientInternalNote> updateClientInternalNote({
    required String clientType,
    required String clientId,
    required String body,
    required int expectedVersion,
  }) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/crm/clients/$clientType/$clientId/internal-note',
      data: {'body': body, 'expectedVersion': expectedVersion},
    );
    return ClientInternalNote.fromJson(response);
  }

  Future<ClientOperationalHistoryPage> getClientOperationalHistory({
    required String clientType,
    required String clientId,
    String? cursor,
    int limit = 30,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/clients/$clientType/$clientId/operational-history',
      queryParameters: {'limit': limit, 'cursor': ?cursor},
    );
    return ClientOperationalHistoryPage.fromJson(response);
  }

  Future<StudentFunnelConfiguration> getClientPipeline({
    required String clientType,
    String? branchId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/client-pipelines',
      queryParameters: {'clientType': clientType, 'branchId': ?branchId},
    );
    return StudentFunnelConfiguration.fromJson(response);
  }

  Future<List<Map<String, dynamic>>> listClientPipelineRevisions({
    required String clientType,
    String? branchId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/client-pipelines/revisions',
      queryParameters: {'clientType': clientType, 'branchId': ?branchId},
    );
    return (response['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> previewClientPipeline({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required List<StudentFunnelStage> stages,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/client-pipelines/preview',
      data: {
        'clientType': clientType,
        'branchId': ?branchId,
        'expectedVersion': expectedVersion,
        'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
      },
    );
  }

  Future<Map<String, dynamic>> publishClientPipeline({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required String reason,
    required List<StudentFunnelStage> stages,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/client-pipelines/publish',
      data: {
        'clientType': clientType,
        'branchId': ?branchId,
        'expectedVersion': expectedVersion,
        'reason': reason.trim(),
        'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
      },
    );
  }

  Future<Map<String, dynamic>> rollbackClientPipeline({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required int targetVersion,
    required String reason,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/client-pipelines/rollback',
      data: {
        'clientType': clientType,
        'branchId': ?branchId,
        'expectedVersion': expectedVersion,
        'targetVersion': targetVersion,
        'reason': reason.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> getMySummary() {
    return _api.get<Map<String, dynamic>>('/crm/me');
  }

  Future<List<Map<String, dynamic>>> listMyStudents() async {
    final response = await getMySummary();
    final students = response['students'];
    if (students is! List) return const <Map<String, dynamic>>[];
    return students
        .whereType<Map<String, dynamic>>()
        .map(_legacyStudent)
        .toList();
  }

  Future<Map<String, dynamic>> getOverviewStats() async {
    final response = await _api.get<Map<String, dynamic>>('/crm/overview');
    return _legacyOverviewStats(response);
  }

  Future<Map<String, dynamic>> getManagerDashboard({
    String? from,
    String? to,
    String? branchId,
  }) async {
    final queryParameters = <String, dynamic>{};
    if (from != null && from.trim().isNotEmpty) {
      queryParameters['from'] = from.trim();
    }
    if (to != null && to.trim().isNotEmpty) {
      queryParameters['to'] = to.trim();
    }
    if (branchId != null && branchId.trim().isNotEmpty) {
      queryParameters['branchId'] = branchId.trim();
    }
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/dashboard/manager',
      queryParameters: queryParameters,
    );
    return _legacyManagerDashboard(response);
  }

  Future<Map<String, dynamic>> getFinanceReport({
    String? from,
    String? to,
  }) async {
    final queryParameters = <String, dynamic>{};
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/reports/finance',
      queryParameters: queryParameters,
    );
    return _legacyFinanceReport(response);
  }

  Future<List<Map<String, dynamic>>> listStudents({int limit = 50}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/students',
      queryParameters: {'limit': limit},
    );
    return _items(response).map(_legacyStudent).toList();
  }

  Future<Map<String, dynamic>> searchStudents({
    String? q,
    String? status,
    String? branchId,
    String? groupId,
    String? discipline,
    String? level,
    String? category,
    String? from,
    String? to,
    bool? linkedUser,
    bool? noEmail,
    bool? noOpenTasks,
    bool? noBranch,
    String? cursor,
    int limit = 50,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('q', q);
    addString('status', status);
    addString('branchId', branchId);
    addString('groupId', groupId);
    addString('discipline', discipline);
    addString('level', level);
    addString('category', category);
    addString('from', from);
    addString('to', to);
    if (linkedUser != null) queryParameters['linkedUser'] = linkedUser;
    if (noEmail != null) queryParameters['noEmail'] = noEmail;
    if (noOpenTasks != null) queryParameters['noOpenTasks'] = noOpenTasks;
    if (noBranch != null) queryParameters['noBranch'] = noBranch;
    addString('cursor', cursor);

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/students/search',
      queryParameters: queryParameters,
    );
    return {
      'items': _items(response).map(_legacyStudentSearchItem).toList(),
      'total_count': response['totalCount'] ?? 0,
      'next_cursor': response['nextCursor'],
    };
  }

  Future<Map<String, dynamic>> inviteStudent(String studentId) async {
    return _api.post<Map<String, dynamic>>('/crm/students/$studentId/invite');
  }

  Future<Map<String, dynamic>> createStudent({
    required String firstName,
    String? lastName,
    String? phone,
    String? email,
    String status = 'active',
    String? leadId,
    Map<String, dynamic>? customDataPatch,
  }) async {
    final data = <String, dynamic>{
      'firstName': firstName.trim(),
      'status': status,
    };
    if (lastName != null && lastName.trim().isNotEmpty) {
      data['lastName'] = lastName.trim();
    }
    if (phone != null && phone.trim().isNotEmpty) data['phone'] = phone.trim();
    if (email != null && email.trim().isNotEmpty) data['email'] = email.trim();
    if (leadId != null && leadId.trim().isNotEmpty) {
      data['leadId'] = leadId.trim();
    }
    if (customDataPatch != null) data['customDataPatch'] = customDataPatch;

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/students',
      data: data,
    );
    return _legacyStudent(response);
  }

  Future<Map<String, dynamic>> getStudent(String id) async {
    final response = await _api.get<Map<String, dynamic>>('/crm/students/$id');
    return _legacyStudent(response);
  }

  Future<Map<String, dynamic>> getStudentCard(String id) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/students/$id/card',
    );
    return {
      'student': _legacyStudent(
        response['student'] is Map<String, dynamic>
            ? response['student'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      'groups': _mapList(response['groups'], _legacyGroup),
      'lessons': _mapList(response['lessons'], _legacyLesson),
      'payments': _mapList(response['payments'], _legacyPayment),
      'tasks': _mapList(response['tasks'], _legacyTask),
      'comments': _mapList(response['comments'], _legacyComment),
      'balance': response['balance'] is Map<String, dynamic>
          ? _legacyStudentBalance(response['balance'] as Map<String, dynamic>)
          : null,
      'subscriptions': _mapList(response['subscriptions'], _legacySubscription),
      'links': _mapList(response['links'], _legacyCrmLink),
      'timeline': _mapList(response['timeline'], _legacyTimelineItem),
      'custom_field_values': response['customFieldValues'] is Map
          ? Map<String, dynamic>.from(response['customFieldValues'] as Map)
          : <String, dynamic>{},
    };
  }

  Future<List<Map<String, dynamic>>> listStudentGroups(
    String studentId, {
    int limit = 50,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/students/$studentId/groups',
      queryParameters: {'limit': limit},
    );
    return _items(response).map(_legacyGroup).toList();
  }

  Future<Map<String, dynamic>> updateStudent(
    String id, {
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? status,
    String? sourceId,
    bool clearResponsible = false,
    Map<String, dynamic>? customDataPatch,
    List<Map<String, dynamic>>? customFields,
  }) async {
    final data = <String, dynamic>{};
    if (firstName != null) data['firstName'] = firstName.trim();
    if (lastName != null) data['lastName'] = lastName.trim();
    if (phone != null) data['phone'] = phone.trim();
    if (email != null) data['email'] = email.trim();
    if (status != null) data['status'] = status.trim();
    if (sourceId != null) data['sourceId'] = sourceId;
    if (clearResponsible) data['clearResponsible'] = true;
    if (customDataPatch != null) data['customDataPatch'] = customDataPatch;
    if (customFields != null) data['customFields'] = customFields;

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/students/$id',
      data: data,
    );
    return _legacyStudent(response);
  }

  Future<List<Map<String, dynamic>>> listTeachers({
    String? q,
    String? status,
    String? branchId,
    String? discipline,
    String? level,
    String? category,
    String? appRole,
    String? authorization,
    num? ratingFrom,
    num? ratingTo,
    int? birthdayMonth,
    int limit = 50,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('q', q);
    addString('status', status);
    addString('branchId', branchId);
    addString('discipline', discipline);
    addString('level', level);
    addString('category', category);
    addString('appRole', appRole);
    addString('authorization', authorization);
    if (ratingFrom != null) queryParameters['ratingFrom'] = ratingFrom;
    if (ratingTo != null) queryParameters['ratingTo'] = ratingTo;
    if (birthdayMonth != null) {
      queryParameters['birthdayMonth'] = birthdayMonth;
    }

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/teachers',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyTeacher).toList();
  }

  /// One teacher by id. Callers holding only an id (a task pointing at a
  /// teacher) can't use listTeachers: it is capped, so the row may be absent.
  Future<Map<String, dynamic>> getTeacher(String id) async {
    final response = await _api.get<Map<String, dynamic>>('/crm/teachers/$id');
    return _legacyTeacher(response);
  }

  Future<Map<String, dynamic>> createTeacher({
    required String firstName,
    String? lastName,
    String? phone,
    String? email,
    String? password,
    String accessRole = 'teacher',
    required List<String> branchIds,
    List<String> disciplineIds = const [],
    String status = 'active',
    Map<String, dynamic>? customDataPatch,
    num? salary,
    num? rate,
    String? rateEffectiveFrom,
  }) async {
    final data = <String, dynamic>{
      'firstName': firstName.trim(),
      'branchIds': branchIds,
      'disciplineIds': disciplineIds,
      'status': status,
      'accessRole': accessRole,
    };
    if (email != null && email.trim().isNotEmpty) data['email'] = email.trim();
    if (password != null && password.isNotEmpty) data['password'] = password;
    if (lastName != null && lastName.trim().isNotEmpty) {
      data['lastName'] = lastName.trim();
    }
    if (phone != null && phone.trim().isNotEmpty) data['phone'] = phone.trim();
    if (customDataPatch != null && customDataPatch.isNotEmpty) {
      data['customDataPatch'] = customDataPatch;
    }
    if (salary != null) data['salary'] = salary;
    if (rate != null) data['rate'] = rate;
    if (rateEffectiveFrom != null && rateEffectiveFrom.isNotEmpty) {
      data['rateEffectiveFrom'] = rateEffectiveFrom;
    }
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/teachers',
      data: data,
    );
    return _legacyTeacher(response);
  }

  Future<Map<String, dynamic>> provisionTeacherAccess({
    required String teacherId,
    String? email,
    String? password,
  }) async {
    final data = <String, dynamic>{};
    if (email != null && email.trim().isNotEmpty) data['email'] = email.trim();
    if (password != null && password.isNotEmpty) data['password'] = password;
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/teachers/$teacherId/access',
      data: data,
    );
    return _legacyTeacher(response);
  }

  Future<Map<String, dynamic>> updateTeacher(
    String id, {
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? status,
    // KVA-238: патч custom-полей (birthday, workStartDate, level, category,
    // isPartTime, isBlacklisted), оклад и явные связи карточки педагога.
    Map<String, dynamic>? customDataPatch,
    num? salary,
    List<String>? disciplineIds,
    List<String>? branchIds,
    num? rate,
    String? rateEffectiveFrom,
    int? payrollExpectedVersion,
    String? payrollReasonText,
  }) async {
    final data = <String, dynamic>{};
    if (firstName != null) data['firstName'] = firstName.trim();
    if (lastName != null) data['lastName'] = lastName.trim();
    if (phone != null) data['phone'] = phone.trim();
    if (email != null) data['email'] = email.trim();
    if (status != null) data['status'] = status.trim();
    if (customDataPatch != null && customDataPatch.isNotEmpty) {
      data['customDataPatch'] = customDataPatch;
    }
    if (salary != null) data['salary'] = salary;
    if (disciplineIds != null) data['disciplineIds'] = disciplineIds;
    if (branchIds != null) data['branchIds'] = branchIds;
    if (rate != null) data['rate'] = rate;
    if (rateEffectiveFrom != null && rateEffectiveFrom.isNotEmpty) {
      data['rateEffectiveFrom'] = rateEffectiveFrom;
    }
    if (payrollExpectedVersion != null) {
      data['payrollExpectedVersion'] = payrollExpectedVersion;
    }
    if (payrollReasonText != null && payrollReasonText.trim().isNotEmpty) {
      data['payrollReasonText'] = payrollReasonText.trim();
    }

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/teachers/$id',
      data: data,
    );
    return _legacyTeacher(response);
  }

  /// KVA-238: сводка по зарплате педагога — начислено/выплачено/задолженность,
  /// актуальная ставка, история ставок и список выплат.
  Future<Map<String, dynamic>> getTeacherPayroll(String teacherId) {
    return _api.get<Map<String, dynamic>>('/crm/teachers/$teacherId/payroll');
  }

  /// KVA-238: выплата преподавателю. kind: payout — выплата задолженности,
  /// bonus — доплата, deduction — вычет. amount всегда положительный.
  Future<Map<String, dynamic>> createTeacherPayout({
    required String teacherId,
    required String kind,
    required num amount,
    required int expectedVersion,
    required String reasonText,
    String? comment,
  }) async {
    final data = <String, dynamic>{
      'kind': kind,
      'amount': amount,
      'expectedVersion': expectedVersion,
      'reasonText': reasonText.trim(),
    };
    final trimmed = comment?.trim();
    if (trimmed != null && trimmed.isNotEmpty) data['comment'] = trimmed;
    return _api.post<Map<String, dynamic>>(
      '/crm/teachers/$teacherId/payouts',
      data: data,
    );
  }

  /// KVA-238: новая ставка педагога (₽ за астр. час, 0 = «входит в оклад»)
  /// с датой начала действия; история сохраняется на бекенде.
  Future<Map<String, dynamic>> setTeacherHourRate({
    required String teacherId,
    required num rate,
    required int expectedVersion,
    required String reasonText,
    String? effectiveFrom,
  }) async {
    final data = <String, dynamic>{
      'rate': rate,
      'expectedVersion': expectedVersion,
      'reasonText': reasonText.trim(),
    };
    if (effectiveFrom != null) data['effectiveFrom'] = effectiveFrom;
    return _api.post<Map<String, dynamic>>(
      '/crm/teachers/$teacherId/rates',
      data: data,
    );
  }

  Future<Map<String, dynamic>> updateTeacherRateEntry({
    required String teacherId,
    required String entryId,
    required num rate,
    required String effectiveFrom,
    required int expectedVersion,
    required String reasonText,
  }) {
    return _api.patch<Map<String, dynamic>>(
      '/crm/teachers/$teacherId/rates/$entryId',
      data: {
        'rate': rate,
        'effectiveFrom': effectiveFrom,
        'expectedVersion': expectedVersion,
        'reasonText': reasonText.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> deleteTeacherRateEntry({
    required String teacherId,
    required String entryId,
    required int expectedVersion,
    required String reasonText,
  }) {
    return _api.delete<Map<String, dynamic>>(
      '/crm/teachers/$teacherId/rates/$entryId',
      data: {
        'expectedVersion': expectedVersion,
        'reasonText': reasonText.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> updateTeacherPayoutEntry({
    required String teacherId,
    required String entryId,
    required String kind,
    required num amount,
    required String paidAt,
    required int expectedVersion,
    required String reasonText,
    String? comment,
  }) {
    return _api.patch<Map<String, dynamic>>(
      '/crm/teachers/$teacherId/payouts/$entryId',
      data: {
        'kind': kind,
        'amount': amount,
        'paidAt': paidAt,
        'comment': comment?.trim(),
        'expectedVersion': expectedVersion,
        'reasonText': reasonText.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> deleteTeacherPayoutEntry({
    required String teacherId,
    required String entryId,
    required int expectedVersion,
    required String reasonText,
  }) {
    return _api.delete<Map<String, dynamic>>(
      '/crm/teachers/$teacherId/payouts/$entryId',
      data: {
        'expectedVersion': expectedVersion,
        'reasonText': reasonText.trim(),
      },
    );
  }

  /// KVA-238: отчёт «Статистика преподавателей» — учебные единицы, дни, часы,
  /// ставка, начислено/оплачено.
  /// unitType: individual | group | trial | individual_trial | group_trial.
  Future<Map<String, dynamic>> getTeacherStatsReport({
    String? from,
    String? to,
    String? branchId,
    String? teacherId,
    String? unitType,
    String? status,
    String? discipline,
    String? category,
  }) {
    return _api.get<Map<String, dynamic>>(
      '/crm/reports/teacher-stats',
      queryParameters: _teacherStatsQuery(
        from: from,
        to: to,
        branchId: branchId,
        teacherId: teacherId,
        unitType: unitType,
        status: status,
        discipline: discipline,
        category: category,
      ),
    );
  }

  /// The same report as CSV (see «Экспорт»); the caller saves the bytes.
  Future<String> exportTeacherStatsReport({
    String? from,
    String? to,
    String? branchId,
    String? teacherId,
    String? unitType,
    String? status,
    String? discipline,
    String? category,
  }) {
    return _api.get<String>(
      '/crm/reports/teacher-stats/export',
      queryParameters: _teacherStatsQuery(
        from: from,
        to: to,
        branchId: branchId,
        teacherId: teacherId,
        unitType: unitType,
        status: status,
        discipline: discipline,
        category: category,
      ),
    );
  }

  Map<String, dynamic> _teacherStatsQuery({
    String? from,
    String? to,
    String? branchId,
    String? teacherId,
    String? unitType,
    String? status,
    String? discipline,
    String? category,
  }) {
    final queryParameters = <String, dynamic>{};
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;
    if (branchId != null) queryParameters['branchId'] = branchId;
    if (teacherId != null) queryParameters['teacherId'] = teacherId;
    if (unitType != null) queryParameters['unitType'] = unitType;
    if (status != null) queryParameters['status'] = status;
    if (discipline != null) queryParameters['discipline'] = discipline;
    if (category != null) queryParameters['category'] = category;
    return queryParameters;
  }

  Future<Map<String, dynamic>> createStaff({
    required String firstName,
    required String lastName,
    String? email,
    String? password,
    String? phone,
    String accessRole = 'admin',
    required List<String> branchIds,
  }) async {
    final data = <String, dynamic>{
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'accessRole': accessRole,
      'branchIds': branchIds,
    };
    if (email != null && email.trim().isNotEmpty) data['email'] = email.trim();
    if (password != null && password.isNotEmpty) data['password'] = password;
    if (phone != null && phone.trim().isNotEmpty) data['phone'] = phone.trim();

    return _api.post<Map<String, dynamic>>('/crm/staff', data: data);
  }

  Future<Map<String, dynamic>> provisionStaffAccess({
    required String staffId,
    String? email,
    String? password,
  }) async {
    final data = <String, dynamic>{};
    if (email != null && email.trim().isNotEmpty) data['email'] = email.trim();
    if (password != null && password.isNotEmpty) data['password'] = password;
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/staff/$staffId/access',
      data: data,
    );
    return _legacyStaff(response);
  }

  Future<Map<String, dynamic>> previewPersonLifecycle({
    required String personType,
    required String personId,
  }) {
    final path = personType == 'teacher' ? 'teachers' : 'staff';
    return _api.get<Map<String, dynamic>>(
      '/crm/$path/$personId/lifecycle-preview',
    );
  }

  Future<Map<String, dynamic>> changePersonLifecycle({
    required String personType,
    required String personId,
    required bool restore,
    required int expectedVersion,
    required String reasonText,
  }) {
    final path = personType == 'teacher' ? 'teachers' : 'staff';
    return _api.post<Map<String, dynamic>>(
      '/crm/$path/$personId/${restore ? 'restore' : 'offboard'}',
      data: {
        'expectedVersion': expectedVersion,
        'reasonText': reasonText.trim(),
        'confirm': true,
      },
    );
  }

  Future<Map<String, dynamic>> updateStaff(
    String id, {
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? position,
    String? status,
    List<String>? branchIds,
    Map<String, dynamic>? customDataPatch,
  }) async {
    final data = <String, dynamic>{};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        data[key] = trimmed;
      }
    }

    addString('firstName', firstName);
    addString('lastName', lastName);
    addString('phone', phone);
    addString('email', email);
    addString('position', position);
    addString('status', status);
    if (branchIds != null) data['branchIds'] = branchIds;
    if (customDataPatch != null && customDataPatch.isNotEmpty) {
      data['customDataPatch'] = customDataPatch;
    }

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/staff/$id',
      data: data,
    );
    return _legacyStaff(response);
  }

  Future<List<Map<String, dynamic>>> listStaff({
    String? q,
    String? branchId,
    String? role,
    String? status,
    String? appRole,
    String? authorization,
    int? birthdayMonth,
    int limit = 50,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('q', q);
    addString('branchId', branchId);
    addString('role', role);
    addString('status', status);
    addString('appRole', appRole);
    addString('authorization', authorization);
    if (birthdayMonth != null) {
      queryParameters['birthdayMonth'] = birthdayMonth;
    }

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/staff',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyStaff).toList();
  }

  Future<List<Map<String, dynamic>>> listActivityLog({
    String? q,
    String? actorUserId,
    String? entityType,
    String? entityId,
    String? branchId,
    String? role,
    String? historyType,
    String? from,
    String? to,
    int limit = 50,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('q', q);
    addString('actorUserId', actorUserId);
    addString('entityType', entityType);
    addString('entityId', entityId);
    addString('branchId', branchId);
    addString('role', role);
    addString('historyType', historyType);
    addString('from', from);
    addString('to', to);

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/activity',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyActivityLog).toList();
  }
}
