part of 'magic_crm_service.dart';

/// Schedule & lessons: matrix, lessons, tasks, comments,
/// timeline, progress notes, subscriptions, ledger, schedule series.
extension MagicCrmSchedule on MagicCrmService {
  Future<StudentLessonTimelinePage> listStudentLessonTimeline({
    required String studentId,
    String? cursor,
    String direction = 'next',
    int limit = 24,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/students/${Uri.encodeComponent(studentId)}/lesson-timeline',
      queryParameters: {
        'cursor': ?cursor,
        'direction': direction,
        'limit': limit,
      },
    );
    return StudentLessonTimelinePage.fromJson(response);
  }

  Future<Map<String, dynamic>> getLessonDecisionCatalog({String? branchId}) =>
      _api.get<Map<String, dynamic>>(
        '/crm/configuration/lesson-decisions',
        queryParameters: {'branchId': branchId},
      );

  Future<Map<String, dynamic>> getLessonSettlementHistory(String lessonId) =>
      _api.get<Map<String, dynamic>>(
        '/crm/lessons/$lessonId/settlement-history',
      );

  Future<LessonScheduleAnalysis> analyzeLessonSchedule({
    required String clientType,
    required String clientId,
    required String teacherId,
    required String branchId,
    required String roomId,
    required String scheduledAt,
    required int durationMinutes,
    String? excludeLessonId,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/lessons/constraints/preview',
      data: {
        'clientRef': {'type': clientType, 'id': clientId},
        'teacherId': teacherId,
        'branchId': branchId,
        'roomId': roomId,
        'scheduledAt': scheduledAt,
        'durationMinutes': durationMinutes,
        'excludeLessonId': ?excludeLessonId,
      },
    );
    return LessonScheduleAnalysis.fromJson(response);
  }

  Future<Map<String, dynamic>> createLessonRaw(Map<String, dynamic> data) =>
      _api.post<Map<String, dynamic>>('/crm/lessons', data: data);

  Future<Map<String, dynamic>> updateLessonNotes({
    required String lessonId,
    required int expectedVersion,
    required String? notes,
    required MagicMutationIdentity identity,
  }) => _api.request<Map<String, dynamic>>(
    'PATCH',
    '/crm/lessons/$lessonId',
    data: {'expectedVersion': expectedVersion, 'notes': notes?.trim() ?? ''},
    mutationIdentity: identity,
  );

  Future<Map<String, dynamic>> previewLessonDecision({
    required String lessonId,
    required String operationKey,
    required Map<String, dynamic> data,
  }) => _api.post<Map<String, dynamic>>(
    '/crm/lessons/$lessonId/$operationKey/preview',
    data: data,
  );

  Future<Map<String, dynamic>> commitLessonDecision({
    required String lessonId,
    required String operationKey,
    required Map<String, dynamic> data,
    required MagicMutationIdentity identity,
    required bool usePut,
  }) => usePut
      ? _api.request<Map<String, dynamic>>(
          'PUT',
          '/crm/lessons/$lessonId/$operationKey',
          data: data,
          mutationIdentity: identity,
        )
      : _api.postIdempotent<Map<String, dynamic>>(
          '/crm/lessons/$lessonId/$operationKey',
          data: data,
          identity: identity,
        );

  Future<Map<String, dynamic>> getBranchScheduleHours(String branchId) {
    return _api.get<Map<String, dynamic>>(
      '/crm/schedule-reference/branches/$branchId/hours',
    );
  }

  Future<Map<String, dynamic>> getScheduleReference({
    required String branchId,
    required String teacherId,
  }) {
    final now = DateTime.now().toUtc();
    return _api.get<Map<String, dynamic>>(
      '/crm/schedule-reference',
      queryParameters: {
        'branchId': branchId,
        'teacherId': teacherId,
        'from': now.toIso8601String(),
        'to': now.add(const Duration(days: 31)).toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> replaceBranchHours({
    required String branchId,
    required int expectedVersion,
    required String timezone,
    required List<Map<String, dynamic>> weekly,
    required List<Map<String, dynamic>> exceptions,
  }) {
    return _api.put<Map<String, dynamic>>(
      '/crm/schedule-reference/branches/$branchId/hours',
      data: {
        'expectedVersion': expectedVersion,
        'timezone': timezone,
        'weekly': weekly,
        'exceptions': exceptions,
      },
    );
  }

  Future<Map<String, dynamic>> replaceTeacherBranches({
    required String teacherId,
    required int expectedVersion,
    required List<Map<String, dynamic>> assignments,
  }) {
    return _api.put<Map<String, dynamic>>(
      '/crm/schedule-reference/teachers/$teacherId/branches',
      data: {'expectedVersion': expectedVersion, 'assignments': assignments},
    );
  }

  Future<Map<String, dynamic>> replaceTeacherAvailability({
    required String teacherId,
    required int expectedVersion,
    required List<Map<String, dynamic>> rules,
  }) {
    return _api.put<Map<String, dynamic>>(
      '/crm/schedule-reference/teachers/$teacherId/availability',
      data: {'expectedVersion': expectedVersion, 'rules': rules},
    );
  }

  Future<Map<String, dynamic>> listSharedTasks({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
    String? q,
    String? priority,
    String? scope,
    String? from,
    String? to,
    int limit = 2000,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/shared-tasks',
      queryParameters: {
        'limit': limit,
        if (state != null && state.isNotEmpty) 'state': state,
        if (taskId != null && taskId.isNotEmpty) 'taskId': taskId,
        if (linkedEntityType != null && linkedEntityType.isNotEmpty)
          'linkedEntityType': linkedEntityType,
        if (linkedEntityId != null && linkedEntityId.isNotEmpty)
          'linkedEntityId': linkedEntityId,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (priority != null && priority.isNotEmpty) 'priority': priority,
        if (scope != null && scope.isNotEmpty) 'scope': scope,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
    );
    final items = response['items'];
    return {
      'items': items is List
          ? items.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[],
      'counters': response['counters'] is Map<String, dynamic>
          ? response['counters']
          : <String, dynamic>{'open': 0, 'overdue': 0},
    };
  }

  Future<Map<String, int>> sharedTaskCalendar({
    required String from,
    required String to,
    String? state,
    String? q,
    String? priority,
    String? scope,
    String? linkedEntityType,
    String? linkedEntityId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/shared-tasks/calendar',
      queryParameters: {
        'from': from,
        'to': to,
        if (state != null && state.isNotEmpty) 'state': state,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (priority != null && priority.isNotEmpty) 'priority': priority,
        if (scope != null && scope.isNotEmpty) 'scope': scope,
        if (linkedEntityType != null && linkedEntityType.isNotEmpty)
          'linkedEntityType': linkedEntityType,
        if (linkedEntityId != null && linkedEntityId.isNotEmpty)
          'linkedEntityId': linkedEntityId,
      },
    );
    return {
      for (final row in _items(response))
        if (row['day'] != null && row['count'] is num)
          row['day'].toString(): (row['count'] as num).toInt(),
    };
  }

  Future<List<Map<String, dynamic>>> listSharedTaskHistory(
    String taskId,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/shared-tasks/$taskId/history',
    );
    final items = response['items'];
    return items is List
        ? items.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> previewSharedTaskAudience(
    List<Map<String, dynamic>> audiences,
  ) {
    return _api.post<Map<String, dynamic>>(
      '/crm/shared-tasks/audience-preview',
      data: {'audiences': audiences},
    );
  }

  Future<Map<String, dynamic>> createSharedTask({
    required Map<String, dynamic> data,
    required MagicMutationIdentity identity,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/shared-tasks',
      identity: identity,
      data: data,
    );
  }

  Future<Map<String, dynamic>> updateSharedTask({
    required String taskId,
    required Map<String, dynamic> data,
    required MagicMutationIdentity identity,
  }) {
    return _api.request<Map<String, dynamic>>(
      'PATCH',
      '/crm/shared-tasks/$taskId',
      data: data,
      mutationIdentity: identity,
    );
  }

  Future<Map<String, dynamic>> closeSharedTask({
    required String taskId,
    required int expectedVersion,
    required MagicMutationIdentity identity,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/shared-tasks/$taskId/close',
      identity: identity,
      data: {'expectedVersion': expectedVersion},
    );
  }

  Future<Map<String, dynamic>> getScheduleMatrix({
    String? from,
    String? to,
    String? localDate,
    String? branchId,
    String? roomId,
    String? teacherId,
    String? studentId,
    String? leadId,
    bool? isTrial,
    String? groupBy,
    int limit = 300,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('from', from);
    addString('to', to);
    addString('localDate', localDate);
    addString('branchId', branchId);
    addString('roomId', roomId);
    addString('teacherId', teacherId);
    addString('studentId', studentId);
    addString('leadId', leadId);
    addString('groupBy', groupBy);
    if (isTrial != null) queryParameters['isTrial'] = isTrial;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/schedule/matrix',
      queryParameters: queryParameters,
    );
    return {
      'from': response['from'],
      'to': response['to'],
      'group_by': response['groupBy'],
      'items': _mapList(response['items'], _legacyScheduleLesson),
      'groups': _mapList(response['groups'], _legacyScheduleGroup),
      'conflicts': _mapList(response['conflicts'], _legacyScheduleConflict),
    };
  }

  /// Lightweight per-day lesson counts for the month calendar. Returns a list of
  /// `{ 'day': 'YYYY-MM-DD', 'count': int, 'room_ids': List<String> }` so the
  /// month view can render counts + room dots without fetching every lesson.
  Future<List<Map<String, dynamic>>> getScheduleMonthSummary({
    String? from,
    String? to,
    String? branchId,
  }) async {
    final queryParameters = <String, dynamic>{};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('from', from);
    addString('to', to);
    addString('branchId', branchId);

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/schedule/month-summary',
      queryParameters: queryParameters,
    );
    return _items(response).map((item) {
      final roomIds = item['roomIds'];
      return {
        'day': item['day']?.toString(),
        'count': item['count'] is int
            ? item['count']
            : int.tryParse('${item['count']}') ?? 0,
        'room_ids': roomIds is List
            ? roomIds.map((e) => e.toString()).toList()
            : const <String>[],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listLessons({
    String? lessonId,
    String? from,
    String? to,
    String? studentId,
    String? teacherId,
    bool? isTrial,
    // 'desc' — новейшие первыми (история: сервер режет limit ПОСЛЕ сортировки,
    // поэтому asc у давних учеников возвращал 50 самых СТАРЫХ занятий).
    String? order,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (lessonId != null) queryParameters['lessonId'] = lessonId;
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;
    if (studentId != null) queryParameters['studentId'] = studentId;
    if (teacherId != null) queryParameters['teacherId'] = teacherId;
    if (isTrial != null) queryParameters['isTrial'] = isTrial;
    if (order != null) queryParameters['order'] = order;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/lessons',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyLesson).toList();
  }

  /// Actor-scoped, typed Lead/Student lookup used by every v4 lesson form.
  ///
  /// The discriminator is deliberately preserved in `ref`; UUIDs from the two
  /// aggregates are never guessed from a legacy student/lead picker.
  Future<List<Map<String, dynamic>>> searchClientRefs({
    String? q,
    String? type,
    String? branchId,
    int limit = 25,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/clients/search',
      queryParameters: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
        if (branchId != null && branchId.trim().isNotEmpty)
          'branchId': branchId.trim(),
        'limit': limit,
      },
    );
    return _items(response);
  }

  Future<Map<String, dynamic>> resolveClientRef({
    required String type,
    required String id,
  }) {
    return _api.get<Map<String, dynamic>>(
      '/crm/clients/resolve',
      queryParameters: {'type': type, 'id': id},
    );
  }

  Future<Map<String, dynamic>> createLesson({
    String? studentId,
    String? groupId,
    String? leadId,
    String? teacherId,
    String? branchId,
    String? roomId,
    required String scheduledAt,
    int? durationMinutes,
    String status = 'scheduled',
    bool isTrial = false,
    String? notes,
    num? teacherRate,
  }) async {
    final data = <String, dynamic>{
      'scheduledAt': scheduledAt,
      'status': status,
      'isTrial': isTrial,
    };
    if (studentId != null) data['studentId'] = studentId;
    if (groupId != null) data['groupId'] = groupId;
    if (leadId != null) data['leadId'] = leadId;
    if (teacherId != null) data['teacherId'] = teacherId;
    if (branchId != null) data['branchId'] = branchId;
    if (roomId != null) data['roomId'] = roomId;
    if (durationMinutes != null) data['durationMinutes'] = durationMinutes;
    if (teacherRate != null) data['teacherRate'] = teacherRate;
    if (notes != null && notes.trim().isNotEmpty) {
      data['notes'] = notes.trim();
    }

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/lessons',
      data: data,
    );
    return _legacyLesson(response);
  }

  /// Applies one per-lesson teacher rate to many lessons at once.
  ///
  /// [teacherRate] `0` means «входит в оклад»; `null` clears the per-lesson
  /// override so the group/history rate applies again. One request, one
  /// transaction — the old per-lesson loop could fail halfway and leave the
  /// month half-repriced.
  Future<int> setLessonsTeacherRate({
    required List<String> lessonIds,
    required num? teacherRate,
    required String reasonText,
    required int expectedVersion,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/lessons/teacher-rate',
      data: {
        'expectedVersion': expectedVersion,
        'lessonIds': lessonIds,
        'teacherRate': teacherRate,
        'reasonText': reasonText.trim(),
      },
    );
    final updated = response['updated'];
    return updated is num ? updated.toInt() : 0;
  }

  Future<List<Map<String, dynamic>>> listTimeline({
    required String entityType,
    required String entityId,
    String? from,
    String? to,
    bool includeAudit = false,
    int limit = 80,
  }) async {
    final queryParameters = <String, dynamic>{
      'entityType': entityType,
      'entityId': entityId,
      'includeAudit': includeAudit,
      'limit': limit,
    };
    if (from != null && from.trim().isNotEmpty) {
      queryParameters['from'] = from.trim();
    }
    if (to != null && to.trim().isNotEmpty) {
      queryParameters['to'] = to.trim();
    }
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/timeline',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyTimelineItem).toList();
  }

  Future<List<Map<String, dynamic>>> listComments({
    required String entityType,
    required String entityId,
    bool progressOnly = false,
    String? kind,

    /// Подмешать комментарии к занятиям этого ученика (только для 'student').
    bool includeLessonComments = false,
    int limit = 50,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/comments',
      queryParameters: {
        'entityType': entityType,
        'entityId': entityId,
        'progressOnly': progressOnly,
        'kind': ?kind,
        if (includeLessonComments) 'includeLessonComments': true,
        'limit': limit,
      },
    );
    return _items(response).map(_legacyComment).toList();
  }

  Future<Map<String, dynamic>> createComment({
    required String entityType,
    required String entityId,
    required String body,
    bool progress = false,
    String? kind,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/comments',
      data: {
        'entityType': entityType,
        'entityId': entityId,
        'body': body.trim(),
        'progress': progress,
        'kind': ?kind,
      },
    );
    return _legacyComment(response);
  }

  /// Versioned toggle for the explicit Teacher-sharing flag. Comment kind is
  /// preserved; visibility is an independent audited fact.
  Future<Map<String, dynamic>> setCommentVisibility({
    required String commentId,
    required bool visibleToTeacher,
    required int expectedVersion,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/comments/$commentId/visibility',
      data: {
        'sharedWithTeacher': visibleToTeacher,
        'expectedVersion': expectedVersion,
        'reasonCode': 'crm.comment.teacher-sharing',
      },
    );
    return _legacyComment(response);
  }

  Future<List<Map<String, dynamic>>> listProgressNotes({
    required String studentId,
    int limit = 50,
  }) {
    return listComments(
      entityType: 'student',
      entityId: studentId,
      progressOnly: true,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> listSubscriptions({
    String? studentId,
    int limit = 20,
  }) async {
    // Lesson creation and other compatibility callers need one student's
    // subscriptions, not the school-wide list. Keep their legacy map contract
    // while sourcing it from the actor-scoped commerce projection.
    if (studentId != null) {
      final projection = await getStudentCommerceProjection(studentId);
      return projection.student.legacySubscriptions
          .take(limit)
          .toList(growable: false);
    }

    final queryParameters = <String, dynamic>{'limit': limit};

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/subscriptions',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacySubscription).toList();
  }

  /// KVA-235: лента личного счёта (платежи + списания за занятия + ручные
  /// операции) с итогами прихода/расхода.
  Future<Map<String, dynamic>> getStudentLedger(
    String studentId, {
    String? direction,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (direction != null) queryParameters['direction'] = direction;
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/students/$studentId/ledger',
      queryParameters: queryParameters,
    );
    return {
      'items': _items(response)
          .map(
            (item) => {
              'id': item['id'],
              'kind': item['kind'],
              'amount': item['amount'],
              'description': item['description'],
              'method': item['method'],
              'branch_name': item['branchName'],
              'author_name': item['authorName'],
              'occurred_at': item['occurredAt'],
            },
          )
          .toList(),
      'income_total': response['incomeTotal'],
      'outcome_total': response['outcomeTotal'],
    };
  }

  Future<List<SchedulePlan>> listSchedulePlans({
    String? studentId,
    String? groupId,
    bool includeEnded = true,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/schedule-plans',
      queryParameters: {
        'studentId': ?studentId,
        'groupId': ?groupId,
        if (includeEnded) 'includeEnded': 'true',
      },
    );
    return _items(response).map(SchedulePlan.fromMap).toList(growable: false);
  }

  Future<SchedulePlanTrayPage> getSchedulePlanTray(
    String planId, {
    String? cursor,
    String? direction,
    int limit = 24,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/schedule-plans/$planId/tray',
      queryParameters: {
        'cursor': ?cursor,
        if (cursor != null && direction != null) 'direction': direction,
        'limit': limit.clamp(1, 40),
      },
    );
    return SchedulePlanTrayPage.fromMap(response);
  }

  Future<Map<String, dynamic>> createSchedulePlan({
    required MagicMutationIdentity identity,
    required String title,
    String kind = 'individual',
    String? studentId,
    String? groupId,
    String? subscriptionId,
    List<Map<String, dynamic>> participants = const [],
    required String activeFrom,
    required String? activeUntil,
    required List<Map<String, dynamic>> rows,
    String? historyPreviewToken,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/schedule-plans',
      identity: identity,
      data: {
        'kind': kind,
        'title': title.trim(),
        if (kind == 'individual') 'studentId': studentId,
        if (kind == 'individual') 'subscriptionId': subscriptionId,
        if (kind == 'group') 'groupId': groupId,
        if (kind == 'group') 'participants': participants,
        'activeFrom': activeFrom,
        'activeUntil': activeUntil,
        'rows': rows,
        if (historyPreviewToken != null) ...{
          'previewToken': historyPreviewToken,
          'confirmHistorical': true,
        },
      },
    );
  }

  Future<Map<String, dynamic>> previewSchedulePlanConstraints({
    required String title,
    String kind = 'individual',
    String? studentId,
    String? groupId,
    String? subscriptionId,
    List<Map<String, dynamic>> participants = const [],
    required String activeFrom,
    required String? activeUntil,
    required List<Map<String, dynamic>> rows,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/schedule-plans/constraints/preview',
      data: {
        'kind': kind,
        'title': title.trim(),
        if (kind == 'individual') 'studentId': studentId,
        if (kind == 'individual') 'subscriptionId': subscriptionId,
        if (kind == 'group') 'groupId': groupId,
        if (kind == 'group') 'participants': participants,
        'activeFrom': activeFrom,
        'activeUntil': activeUntil,
        'rows': rows,
      },
    );
  }

  Future<Map<String, dynamic>> updateSchedulePlan(
    String planId, {
    required MagicMutationIdentity identity,
    required int expectedVersion,
    required String effectiveFrom,
    required String title,
    String? subscriptionId,
    List<Map<String, dynamic>>? participants,
    required String? activeUntil,
    required List<Map<String, dynamic>> rows,
    String? historyPreviewToken,
  }) {
    return _api.patchIdempotent<Map<String, dynamic>>(
      '/crm/schedule-plans/$planId',
      identity: identity,
      data: _schedulePlanUpdateData(
        expectedVersion: expectedVersion,
        effectiveFrom: effectiveFrom,
        title: title,
        subscriptionId: subscriptionId,
        participants: participants,
        activeUntil: activeUntil,
        rows: rows,
        historyPreviewToken: historyPreviewToken,
      ),
    );
  }

  Future<Map<String, dynamic>> previewSchedulePlanUpdateConstraints(
    String planId, {
    required int expectedVersion,
    required String effectiveFrom,
    required String title,
    String? subscriptionId,
    List<Map<String, dynamic>>? participants,
    required String? activeUntil,
    required List<Map<String, dynamic>> rows,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/schedule-plans/$planId/constraints/preview',
      data: _schedulePlanUpdateData(
        expectedVersion: expectedVersion,
        effectiveFrom: effectiveFrom,
        title: title,
        subscriptionId: subscriptionId,
        participants: participants,
        activeUntil: activeUntil,
        rows: rows,
      ),
    );
  }

  Map<String, dynamic> _schedulePlanUpdateData({
    required int expectedVersion,
    required String effectiveFrom,
    required String title,
    required String? subscriptionId,
    required List<Map<String, dynamic>>? participants,
    required String? activeUntil,
    required List<Map<String, dynamic>> rows,
    String? historyPreviewToken,
  }) => {
    'expectedVersion': expectedVersion,
    'effectiveFrom': effectiveFrom,
    'title': title.trim(),
    'subscriptionId': ?subscriptionId,
    'participants': ?participants,
    'activeUntil': activeUntil,
    'rows': rows,
    if (historyPreviewToken != null) ...{
      'previewToken': historyPreviewToken,
      'confirmHistorical': true,
    },
  };

  Future<SchedulePlanEndPreview> previewSchedulePlanEnd(
    String planId, {
    required int expectedVersion,
    required String lastDate,
    required String reasonText,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/schedule-plans/$planId/end/preview',
      data: {
        'expectedVersion': expectedVersion,
        'lastDate': lastDate,
        'reasonText': reasonText.trim(),
      },
    );
    return SchedulePlanEndPreview.fromMap(response);
  }

  Future<Map<String, dynamic>> endSchedulePlan(
    String planId, {
    required MagicMutationIdentity identity,
    required int expectedVersion,
    required String lastDate,
    required String reasonText,
    required String previewToken,
  }) {
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/schedule-plans/$planId/end',
      identity: identity,
      data: {
        'expectedVersion': expectedVersion,
        'lastDate': lastDate,
        'reasonText': reasonText.trim(),
        'previewToken': previewToken,
        'confirm': true,
      },
    );
  }

  /// KVA-236: серии постоянного расписания.
  Future<List<Map<String, dynamic>>> listScheduleSeries({
    String? clientType,
    String? clientId,
    String? studentId,
    String? groupId,
    bool includeExpired = false,
  }) async {
    final queryParameters = <String, dynamic>{};
    if (clientType != null) queryParameters['clientType'] = clientType;
    if (clientId != null) queryParameters['clientId'] = clientId;
    if (studentId != null) queryParameters['studentId'] = studentId;
    if (groupId != null) queryParameters['groupId'] = groupId;
    if (includeExpired) queryParameters['includeExpired'] = 'true';
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/schedule-series',
      queryParameters: queryParameters,
    );
    return _items(response)
        .map(
          (item) => {
            'id': item['id'],
            'client_type': item['clientType'],
            'client_id': item['clientId'],
            'student_id': item['studentId'],
            'group_id': item['groupId'],
            'teacher_id': item['teacherId'],
            'teacher_name': item['teacherName'],
            'room_id': item['roomId'],
            'room_name': item['roomName'],
            'branch_id': item['branchId'],
            'branch_name': item['branchName'],
            'weekday': item['weekday'],
            'begin_time': item['beginTime'],
            'duration_minutes': item['durationMinutes'],
            'valid_from': item['validFrom'],
            'valid_until': item['validUntil'],
            'notes': item['notes'],
          },
        )
        .toList();
  }
}
