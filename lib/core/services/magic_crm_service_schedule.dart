part of 'magic_crm_service.dart';

/// Schedule & lessons: matrix, lessons, tasks, comments,
/// timeline, progress notes, subscriptions, ledger, schedule series.
extension MagicCrmSchedule on MagicCrmService {
  Future<Map<String, dynamic>> listSharedTasks({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
    int limit = 100,
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
    int limit = 25,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/clients/search',
      queryParameters: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
        'limit': limit,
      },
    );
    return _items(response);
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
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/lessons/teacher-rate',
      data: {'lessonIds': lessonIds, 'teacherRate': teacherRate},
    );
    final updated = response['updated'];
    return updated is num ? updated.toInt() : 0;
  }

  Future<Map<String, dynamic>> updateLesson(
    String id, {
    required int expectedVersion,
    String? studentId,
    String? groupId,
    String? teacherId,
    String? branchId,
    String? roomId,
    String? scheduledAt,
    int? durationMinutes,
    bool? isTrial,
    String? notes,
    num? teacherRate,
  }) async {
    final data = <String, dynamic>{'expectedVersion': expectedVersion};
    if (studentId != null) data['studentId'] = studentId;
    if (groupId != null) data['groupId'] = groupId;
    if (teacherId != null) data['teacherId'] = teacherId;
    if (branchId != null) data['branchId'] = branchId;
    if (roomId != null) data['roomId'] = roomId;
    if (scheduledAt != null) data['scheduledAt'] = scheduledAt;
    if (durationMinutes != null) data['durationMinutes'] = durationMinutes;
    if (isTrial != null) data['isTrial'] = isTrial;
    if (notes != null) data['notes'] = notes.trim();
    if (teacherRate != null) data['teacherRate'] = teacherRate;

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/lessons/$id',
      data: data,
    );
    return _legacyLesson(response);
  }

  Future<void> deleteLesson(String id) async {
    await _api.delete<Map<String, dynamic>>('/crm/lessons/$id');
  }

  Future<List<Map<String, dynamic>>> listTasks({
    String? q,
    String? entityType,
    String? entityId,
    String? studentId,
    String? assignedTo,
    String? createdBy,
    String? branchId,
    String? status,
    String? priority,
    String? taskType,
    String? communicationMethod,
    String? from,
    String? to,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('q', q);
    addString('entityType', entityType);
    addString('entityId', entityId);
    addString('studentId', studentId);
    addString('assignedTo', assignedTo);
    addString('createdBy', createdBy);
    addString('branchId', branchId);
    addString('status', status);
    addString('priority', priority);
    addString('taskType', taskType);
    addString('communicationMethod', communicationMethod);
    addString('from', from);
    addString('to', to);

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/tasks',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyTask).toList();
  }

  /// Per-day task counts for the calendar grids, keyed by Moscow date
  /// ('yyyy-MM-dd' → count). Applies the same filters as [listTasks] so a
  /// day-cell count matches the list you get by opening that day.
  Future<Map<String, int>> taskCalendar({
    required String from,
    required String to,
    String? q,
    String? entityType,
    String? assignedTo,
    String? branchId,
    String? status,
    String? priority,
  }) async {
    final queryParameters = <String, dynamic>{'from': from, 'to': to};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('q', q);
    addString('entityType', entityType);
    addString('assignedTo', assignedTo);
    addString('branchId', branchId);
    addString('status', status);
    addString('priority', priority);

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/tasks/calendar',
      queryParameters: queryParameters,
    );
    final result = <String, int>{};
    for (final row in _items(response)) {
      final day = row['day']?.toString();
      final count = row['count'];
      if (day != null && count is int) result[day] = count;
    }
    return result;
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

  /// AmoCRM-style change feed for a single task: who changed what, when.
  Future<List<Map<String, dynamic>>> listTaskHistory(String taskId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/tasks/$taskId/history',
    );
    return _items(response).map(_legacyTaskHistoryItem).toList();
  }

  /// Supervisor control feed: every change of one field across tasks. Defaults
  /// server-side to due-date moves — the case the director needs to watch.
  Future<List<Map<String, dynamic>>> listTaskHistoryFeed({
    String? field,
    String? changedBy,
    String? from,
    String? to,
    int limit = 50,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (field != null && field.trim().isNotEmpty) {
      queryParameters['field'] = field.trim();
    }
    if (changedBy != null && changedBy.trim().isNotEmpty) {
      queryParameters['changedBy'] = changedBy.trim();
    }
    if (from != null && from.trim().isNotEmpty) {
      queryParameters['from'] = from.trim();
    }
    if (to != null && to.trim().isNotEmpty) {
      queryParameters['to'] = to.trim();
    }
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/tasks/history',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyTaskHistoryItem).toList();
  }

  Future<Map<String, dynamic>> createTask({
    required String entityType,
    required String entityId,
    required String title,
    String? description,
    String status = 'open',
    String? dueAt,
    String? assignedTo,
    String? priority,
    bool? dueAllDay,
  }) async {
    final data = <String, dynamic>{
      'entityType': entityType,
      'entityId': entityId,
      'title': title.trim(),
      'status': status,
    };
    if (description != null && description.trim().isNotEmpty) {
      data['description'] = description.trim();
    }
    if (dueAt != null) data['dueAt'] = dueAt;
    if (assignedTo != null) data['assignedTo'] = assignedTo;
    if (priority != null) data['priority'] = priority;
    if (dueAllDay != null) data['dueAllDay'] = dueAllDay;

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/tasks',
      data: data,
    );
    return _legacyTask(response);
  }

  Future<Map<String, dynamic>> updateTask(
    String id, {
    String? entityType,
    String? entityId,
    String? assignedTo,
    String? title,
    String? description,
    String? status,
    String? dueAt,
    String? priority,
    bool? dueAllDay,
  }) async {
    final data = <String, dynamic>{};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        data[key] = trimmed;
      }
    }

    addString('entityType', entityType);
    addString('entityId', entityId);
    addString('assignedTo', assignedTo);
    addString('title', title);
    addString('description', description);
    addString('status', status);
    addString('dueAt', dueAt);
    addString('priority', priority);
    if (dueAllDay != null) data['dueAllDay'] = dueAllDay;

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/tasks/$id',
      data: data,
    );
    return _legacyTask(response);
  }

  Future<void> deleteTask(String id) async {
    await _api.delete<Map<String, dynamic>>('/crm/tasks/$id');
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

  Future<Map<String, dynamic>> createScheduleSeries({
    String? clientType,
    String? clientId,
    String? studentId,
    String? groupId,
    String? teacherId,
    String? roomId,
    String? branchId,
    required int weekday,
    required String beginTime,
    int? durationMinutes,
    required String validFrom,
    String? validUntil,
    String? notes,
  }) async {
    final data = <String, dynamic>{
      'weekday': weekday,
      'beginTime': beginTime,
      'validFrom': validFrom,
    };
    if (clientType != null && clientId != null) {
      data['clientRef'] = {'type': clientType, 'id': clientId};
    }
    if (studentId != null) data['studentId'] = studentId;
    if (groupId != null) data['groupId'] = groupId;
    if (teacherId != null) data['teacherId'] = teacherId;
    if (roomId != null) data['roomId'] = roomId;
    if (branchId != null) data['branchId'] = branchId;
    if (durationMinutes != null) data['durationMinutes'] = durationMinutes;
    if (validUntil != null) data['validUntil'] = validUntil;
    if (notes != null && notes.trim().isNotEmpty) data['notes'] = notes.trim();
    return _api.post<Map<String, dynamic>>('/crm/schedule-series', data: data);
  }

  Future<Map<String, dynamic>> updateScheduleSeries(
    String id, {
    String? teacherId,
    String? roomId,
    int? weekday,
    String? beginTime,
    int? durationMinutes,
    String? validUntil,
    bool clearValidUntil = false,
    String? effectiveFrom,
    String? notes,
  }) async {
    final data = <String, dynamic>{};
    if (teacherId != null) data['teacherId'] = teacherId;
    if (roomId != null) data['roomId'] = roomId;
    if (weekday != null) data['weekday'] = weekday;
    if (beginTime != null) data['beginTime'] = beginTime;
    if (durationMinutes != null) data['durationMinutes'] = durationMinutes;
    if (clearValidUntil) {
      data['validUntil'] = null;
    } else if (validUntil != null) {
      data['validUntil'] = validUntil;
    }
    if (effectiveFrom != null) data['effectiveFrom'] = effectiveFrom;
    if (notes != null) data['notes'] = notes;
    return _api.patch<Map<String, dynamic>>(
      '/crm/schedule-series/$id',
      data: data,
    );
  }

  Future<Map<String, dynamic>> deleteScheduleSeries(
    String id, {
    String? from,
  }) async {
    return _api.delete<Map<String, dynamic>>(
      '/crm/schedule-series/$id',
      queryParameters: from != null ? {'from': from} : null,
    );
  }
}
