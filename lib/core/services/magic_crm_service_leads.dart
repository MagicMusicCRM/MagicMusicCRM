part of 'magic_crm_service.dart';

/// Leads: pipeline, cards, family, data-quality, duplicates, linking.
extension MagicCrmLeads on MagicCrmService {
  Future<List<Map<String, dynamic>>> listLeadStatuses({int limit = 100}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/lead-statuses',
      queryParameters: {'limit': limit},
    );
    return _items(response).map(_legacyLeadStatus).toList();
  }

  Future<List<Map<String, dynamic>>> listLeads({
    int limit = 100,
    String? q,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads',
      queryParameters: {
        'limit': limit,
        // Server-side name/phone filter — the endpoint has always accepted it.
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      },
    );
    return _items(response).map(_legacyLead).toList();
  }

  Future<Map<String, dynamic>> listLeadBoard({
    String? q,
    String? statusId,
    String? branchId,
    String? assignedTo,
    String? source,
    String? discipline,
    String? level,
    String? category,
    String? requestType,
    String? goal,
    String? gender,
    String? preferredSchedule,
    String quick = 'all',
    bool? openTasks,
    String? from,
    String? to,
    String? cursor,
    int limit = 25,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit, 'quick': quick};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('q', q);
    addString('statusId', statusId);
    addString('branchId', branchId);
    addString('assignedTo', assignedTo);
    addString('source', source);
    addString('discipline', discipline);
    addString('level', level);
    addString('category', category);
    addString('requestType', requestType);
    addString('goal', goal);
    addString('gender', gender);
    addString('preferredSchedule', preferredSchedule);
    addString('from', from);
    addString('to', to);
    addString('cursor', cursor);
    if (openTasks != null) queryParameters['openTasks'] = openTasks;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads/board',
      queryParameters: queryParameters,
    );
    return _legacyLeadBoard(response);
  }

  Future<Map<String, dynamic>> getLeadCard(String id) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads/$id/card',
    );
    return {
      'lead': _legacyLeadBoardItem(
        response['lead'] is Map<String, dynamic>
            ? response['lead'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      'linked_students': _mapList(response['linkedStudents'], _legacyStudent),
      'other_leads': _mapList(response['otherLeads'], _legacyLead),
      'comments': _mapList(response['comments'], _legacyComment),
      'tasks': _mapList(response['tasks'], _legacyTask),
      'trials': _mapList(response['trials'], _legacyLesson),
      'timeline': _mapList(response['timeline'], _legacyTimelineItem),
    };
  }

  /// Ручное «Прикрепить к ученику»: связывает лида с уже существующим учеником.
  /// Бросит ошибку, если ученик уже привязан к другому лиду — молча перевесить
  /// связь нельзя.
  Future<Map<String, dynamic>> linkStudentToLead({
    required String leadId,
    required String studentId,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/crm/leads/$leadId/link-student',
      data: {'studentId': studentId},
    );
  }

  /// Чёрный список = бан (✔ решение владельца 17.07): карточка красится, и
  /// клиенту закрываются чаты школы и админов.
  ///
  /// Отдельный вызов, а не поле в `updateLead`/`updateStudent`: бан снимает
  /// человеку доступ, и такое не должно уезжать вместе с патчем произвольных
  /// полей карточки — в том числе случайно.
  ///
  /// [entity] — 'students' или 'leads': аккаунт клиента цепляется к любой из
  /// половин карточки, поэтому банить нужно ту, которая есть.
  Future<Map<String, dynamic>> setClientBlacklist({
    required String entity,
    required String id,
    required bool blacklisted,
    String? reason,
  }) async {
    return _api.patch<Map<String, dynamic>>(
      '/crm/$entity/$id/blacklist',
      data: {
        'blacklisted': blacklisted,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getLeadStatusHistory(String leadId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads/$leadId/status-history',
    );
    return _mapList(response['items'], _legacyStatusHistoryItem);
  }

  /// KVA-234: заявки лида (app.lead_applications) — секция «Заявки».
  Future<List<Map<String, dynamic>>> listLeadApplications(String leadId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads/$leadId/applications',
    );
    return _items(response).map((item) {
      return {
        'id': item['id'],
        'applied_at': item['appliedAt'],
        'channel': item['channel'],
        'office': item['office'],
        'discipline': item['discipline'],
        'status': item['status'],
        'utm': item['utm'] is Map
            ? Map<String, dynamic>.from(item['utm'] as Map)
            : const <String, dynamic>{},
      };
    }).toList();
  }

  Future<Map<String, dynamic>> getFamilyForEntity({
    required String entityType,
    required String entityId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/families/by-entity/$entityType/$entityId',
    );
    final family = response['family'];
    return {
      'family': family is Map<String, dynamic>
          ? {
              'id': family['id'],
              'name': family['name'],
              'branch_id': family['branchId'],
              'primary_payer_member_id': family['primaryPayerMemberId'],
            }
          : null,
      'members': _mapList(response['members'], _legacyFamilyMember),
    };
  }

  // ── Family writes (P3-9; backend already exists) ─────────────────────────
  Future<Map<String, dynamic>> createFamily(Map<String, dynamic> data) async {
    return _api.post<Map<String, dynamic>>('/crm/families', data: data);
  }

  Future<Map<String, dynamic>> addFamilyMember(
    String familyId, {
    required String entityType,
    required String entityId,
    required String role,
    bool? isPrimaryContact,
  }) async {
    final data = <String, dynamic>{
      'entityType': entityType,
      'entityId': entityId,
      'role': role,
    };
    if (isPrimaryContact != null) data['isPrimaryContact'] = isPrimaryContact;
    return _api.post<Map<String, dynamic>>(
      '/crm/families/$familyId/members',
      data: data,
    );
  }

  Future<void> removeFamilyMember(String memberId) async {
    await _api.delete<Map<String, dynamic>>('/crm/family-members/$memberId');
  }

  // ── Data quality: phone review + lead merge (P5-7) ───────────────────────
  Future<int> countPhoneReviewQueue() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/crm/phone-review-queue/count',
    );
    return (res['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> listPhoneReviewQueue({int? limit}) async {
    final q = <String, dynamic>{};
    if (limit != null) q['limit'] = limit;
    final res = await _api.get<Map<String, dynamic>>(
      '/crm/phone-review-queue',
      queryParameters: q,
    );
    return _items(res).whereType<Map<String, dynamic>>().toList();
  }

  Future<List<Map<String, dynamic>>> listMergeCandidates({int? limit}) async {
    final q = <String, dynamic>{};
    if (limit != null) q['limit'] = limit;
    final res = await _api.get<Map<String, dynamic>>(
      '/crm/merge-candidates',
      queryParameters: q,
    );
    return _items(res).whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> mergeLeads({
    required String winnerId,
    required String loserId,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/crm/leads/$winnerId/merge/$loserId',
      data: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> undoMerge(String mergeLogId) async {
    return _api.post<Map<String, dynamic>>(
      '/crm/merges/$mergeLogId/undo',
      data: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> createLead({
    required String firstName,
    String? lastName,
    String? phone,
    String? email,
    String? source,
    String? statusId,
    String? notes,
    Map<String, dynamic>? customDataPatch,
  }) async {
    final data = <String, dynamic>{'firstName': firstName.trim()};
    if (lastName != null && lastName.trim().isNotEmpty) {
      data['lastName'] = lastName.trim();
    }
    if (phone != null && phone.trim().isNotEmpty) data['phone'] = phone.trim();
    if (email != null && email.trim().isNotEmpty) data['email'] = email.trim();
    if (source != null && source.trim().isNotEmpty) {
      data['source'] = source.trim();
    }
    if (statusId != null && statusId.trim().isNotEmpty) {
      data['statusId'] = statusId.trim();
    }
    if (notes != null && notes.trim().isNotEmpty) data['notes'] = notes.trim();
    if (customDataPatch != null) data['customDataPatch'] = customDataPatch;

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/leads',
      data: data,
    );
    return _legacyLead(response);
  }

  Future<Map<String, dynamic>> updateLead(
    String id, {
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? source,
    String? statusId,
    bool clearStatus = false,
    String? notes,
    Map<String, dynamic>? customDataPatch,
    // P3-7: when moving to a requires_reason (terminal) status, capture why.
    String? reasonId,
    String? statusComment,
  }) async {
    final data = <String, dynamic>{};
    if (firstName != null) data['firstName'] = firstName.trim();
    if (lastName != null) data['lastName'] = lastName.trim();
    if (phone != null) data['phone'] = phone.trim();
    if (email != null) data['email'] = email.trim();
    if (source != null) data['source'] = source.trim();
    if (statusId != null) data['statusId'] = statusId.trim();
    // Explicit request to un-assign the lead's status ("Без статуса" column);
    // the backend treats this as set-to-null rather than coalesce-preserve.
    if (clearStatus) data['clearStatus'] = true;
    if (notes != null) data['notes'] = notes.trim();
    if (customDataPatch != null) data['customDataPatch'] = customDataPatch;
    if (reasonId != null) data['reasonId'] = reasonId;
    if (statusComment != null && statusComment.trim().isNotEmpty) {
      data['statusComment'] = statusComment.trim();
    }

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/leads/$id',
      data: data,
    );
    return _legacyLead(response);
  }

  /// P3-7: lead loss/pause reasons dictionary (for the terminal-status picker).
  Future<List<Map<String, dynamic>>> listLossReasons() async {
    final response = await _api.get<Map<String, dynamic>>('/crm/loss-reasons');
    return _items(response).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> deleteLead(String id) async {
    await _api.delete<Map<String, dynamic>>('/crm/leads/$id');
  }

  /// Resolve the messenger user behind a lead (via crm-link or phone match)
  /// so staff can jump into a chat. Returns `{userId, name}` (userId may be null).
  Future<Map<String, dynamic>> resolveLeadChatUser(String leadId) async {
    return _api.get<Map<String, dynamic>>('/crm/leads/$leadId/chat-user');
  }

  /// Reverse lookup: given a chat partner user, find their CRM lead/student.
  /// Returns `{studentId, leadId}` (either may be null).
  Future<Map<String, dynamic>> resolveContactForUser(String userId) async {
    return _api.get<Map<String, dynamic>>('/crm/contacts/by-user/$userId');
  }

  /// Save a chat partner into the CRM as a lead or student, linking the entity
  /// to that user. Idempotent — returns the existing one if already saved.
  /// Response: `{leadId|studentId, created}`.
  Future<Map<String, dynamic>> saveContactFromChat({
    required String userId,
    required String as,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/crm/contacts/save-from-chat',
      data: {'userId': userId, 'as': as},
    );
  }

  // ── Client ↔ app-user linking (shared lead/student panel) ────────────────
  /// App users already linked to this CRM entity (own account or staff-linked).
  /// [entityType] is exactly 'lead' or 'student'. Each item: `{userId, name,
  /// phone, linkSource}`.
  Future<List<Map<String, dynamic>>> getClientLinkedUsers(
    String entityType,
    String entityId,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/clients/$entityType/$entityId/linked-users',
    );
    return _items(response);
  }

  /// App users whose phone matches this entity and can be linked to it. Each
  /// item: `{userId, name, phone, email}`.
  Future<List<Map<String, dynamic>>> listClientUserCandidates(
    String entityType,
    String entityId,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/clients/$entityType/$entityId/user-candidates',
    );
    return _items(response);
  }

  /// Links [userId] to this entity. Returns the updated linked-users list.
  Future<List<Map<String, dynamic>>> linkUserToClient(
    String entityType,
    String entityId,
    String userId,
  ) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/clients/$entityType/$entityId/link-user',
      data: {'userId': userId},
    );
    return _items(response);
  }

  Future<Map<String, dynamic>> createLeadStatus({
    required String key,
    required String label,
    required String color,
    required int sortOrder,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/lead-statuses',
      data: {
        'key': key.trim(),
        'label': label.trim(),
        'color': color.trim(),
        'sortOrder': sortOrder,
      },
    );
    return _legacyLeadStatus(response);
  }

  Future<void> deleteLeadStatus(String id) async {
    await _api.delete<Map<String, dynamic>>('/crm/lead-statuses/$id');
  }

  /// Persists a new funnel column order. [idsInOrder] is the ordered list of
  /// lead-status ids; the backend writes their sort_order as 0..N accordingly.
  Future<void> reorderLeadStatuses(List<String> idsInOrder) async {
    await _api.patch<Map<String, dynamic>>(
      '/crm/lead-statuses/order',
      data: {'statusIds': idsInOrder},
    );
  }

  Future<List<Map<String, dynamic>>> listDuplicateCandidates({
    String status = 'pending',
    String? leadId,
    int limit = 50,
  }) async {
    final queryParameters = <String, dynamic>{'status': status, 'limit': limit};
    if (leadId != null && leadId.trim().isNotEmpty) {
      queryParameters['leadId'] = leadId.trim();
    }
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/duplicates',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyDuplicateCandidate).toList();
  }

  Future<Map<String, dynamic>> decideDuplicateCandidate(
    String id, {
    required String status,
    String? notes,
  }) async {
    final data = <String, dynamic>{'status': status};
    if (notes != null && notes.trim().isNotEmpty) {
      data['notes'] = notes.trim();
    }
    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/duplicates/$id',
      data: data,
    );
    return _legacyDuplicateCandidate(response);
  }
}
