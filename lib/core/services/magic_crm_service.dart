import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

final magicCrmServiceProvider = Provider<MagicCrmService>((ref) {
  return MagicCrmService(ref.watch(magicApiClientProvider));
});

final magicCurrentStudentIdProvider = FutureProvider<String?>((ref) async {
  final students = await ref.watch(magicCrmServiceProvider).listMyStudents();
  return students.isEmpty ? null : students.first['id']?.toString();
});

class MagicCrmService {
  final MagicApiClient _api;

  const MagicCrmService(this._api);

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

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/students/search',
      queryParameters: queryParameters,
    );
    return {
      'items': _items(response).map(_legacyStudentSearchItem).toList(),
      'total_count': response['totalCount'] ?? 0,
    };
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
      'expected_payments': _mapList(
        response['expectedPayments'],
        _legacyExpectedPayment,
      ),
      'balance': response['balance'] is Map<String, dynamic>
          ? _legacyStudentBalance(response['balance'] as Map<String, dynamic>)
          : null,
      'links': _mapList(response['links'], _legacyCrmLink),
      'timeline': _mapList(response['timeline'], _legacyTimelineItem),
    };
  }

  Future<Map<String, dynamic>> inviteStudent(String id) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/students/$id/invite',
    );
    return {
      'student_id': response['studentId'],
      'email': response['email'],
      'status': response['status'],
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
    Map<String, dynamic>? customDataPatch,
  }) async {
    final data = <String, dynamic>{};
    if (firstName != null) data['firstName'] = firstName.trim();
    if (lastName != null) data['lastName'] = lastName.trim();
    if (phone != null) data['phone'] = phone.trim();
    if (email != null) data['email'] = email.trim();
    if (status != null) data['status'] = status.trim();
    if (customDataPatch != null) data['customDataPatch'] = customDataPatch;

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

  Future<Map<String, dynamic>> createTeacher({
    required String firstName,
    String? lastName,
    String? phone,
    String? email,
    String? specialization,
    String status = 'active',
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
    if (specialization != null && specialization.trim().isNotEmpty) {
      data['specialization'] = specialization.trim();
    }

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/teachers',
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
    String? specialization,
    String? status,
  }) async {
    final data = <String, dynamic>{};
    if (firstName != null) data['firstName'] = firstName.trim();
    if (lastName != null) data['lastName'] = lastName.trim();
    if (phone != null) data['phone'] = phone.trim();
    if (email != null) data['email'] = email.trim();
    if (specialization != null) {
      data['specialization'] = specialization.trim();
    }
    if (status != null) data['status'] = status.trim();

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/teachers/$id',
      data: data,
    );
    return _legacyTeacher(response);
  }

  Future<Map<String, dynamic>> createStaff({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    required String role,
  }) async {
    final data = <String, dynamic>{
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      'role': role,
    };
    if (phone != null && phone.trim().isNotEmpty) data['phone'] = phone.trim();

    return _api.post<Map<String, dynamic>>('/crm/staff', data: data);
  }

  Future<Map<String, dynamic>> updateStaff(
    String id, {
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? role,
    String? position,
    String? status,
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
    addString('role', role);
    addString('position', position);
    addString('status', status);
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

  Future<List<Map<String, dynamic>>> listBranches({int limit = 100}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches',
      queryParameters: {'limit': limit},
    );
    return _items(response).map(_legacyBranch).toList();
  }

  Future<Map<String, dynamic>> updateBranch(
    String id, {
    String? name,
    String? address,
    int? utcOffsetMinutes,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name.trim();
    if (address != null) data['address'] = address.trim();
    if (utcOffsetMinutes != null) data['utcOffsetMinutes'] = utcOffsetMinutes;
    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/branches/$id',
      data: data,
    );
    return _legacyBranch(response);
  }

  Future<List<Map<String, dynamic>>> listRooms({
    String? branchId,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (branchId != null) queryParameters['branchId'] = branchId;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/rooms',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyRoom).toList();
  }

  Future<Map<String, dynamic>> listRoomAvailability({
    String? branchId,
    String? roomId,
    String? teacherId,
    String? date,
    String? from,
    String? to,
    int? durationMinutes,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        queryParameters[key] = trimmed;
      }
    }

    addString('branchId', branchId);
    addString('roomId', roomId);
    addString('teacherId', teacherId);
    addString('date', date);
    addString('from', from);
    addString('to', to);
    if (durationMinutes != null) {
      queryParameters['durationMinutes'] = durationMinutes;
    }

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/rooms/availability',
      queryParameters: queryParameters,
    );
    return {
      'date_from': response['dateFrom'],
      'date_to': response['dateTo'],
      'slot_from': response['slotFrom'],
      'slot_to': response['slotTo'],
      'items': _mapList(response['items'], _legacyRoomAvailability),
    };
  }

  Future<Map<String, dynamic>> createRoom({
    required String name,
    String? branchId,
    int? capacity,
  }) async {
    final data = <String, dynamic>{'name': name.trim()};
    if (branchId != null) data['branchId'] = branchId;
    if (capacity != null) data['capacity'] = capacity;

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/rooms',
      data: data,
    );
    return _legacyRoom(response);
  }

  Future<Map<String, dynamic>> updateRoom(
    String id, {
    String? name,
    String? branchId,
    int? capacity,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name.trim();
    if (branchId != null) data['branchId'] = branchId;
    if (capacity != null) data['capacity'] = capacity;

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/rooms/$id',
      data: data,
    );
    return _legacyRoom(response);
  }

  Future<void> deleteRoom(String id) async {
    await _api.delete<Map<String, dynamic>>('/crm/rooms/$id');
  }

  Future<List<Map<String, dynamic>>> listGroups({
    String? branchId,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (branchId != null) queryParameters['branchId'] = branchId;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/groups',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyGroup).toList();
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    String? teacherId,
    String? branchId,
    String? roomId,
    num? pricePerLesson,
  }) async {
    final data = <String, dynamic>{'name': name.trim()};
    if (teacherId != null && teacherId.trim().isNotEmpty) {
      data['teacherId'] = teacherId.trim();
    }
    if (branchId != null && branchId.trim().isNotEmpty) {
      data['branchId'] = branchId.trim();
    }
    if (roomId != null && roomId.trim().isNotEmpty) {
      data['roomId'] = roomId.trim();
    }
    if (pricePerLesson != null) data['pricePerLesson'] = pricePerLesson;

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/groups',
      data: data,
    );
    return _legacyGroup(response);
  }

  Future<List<Map<String, dynamic>>> listGroupStudents(
    String groupId, {
    int limit = 100,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/groups/$groupId/students',
      queryParameters: {'limit': limit},
    );
    return _items(response).map(_legacyStudent).toList();
  }

  Future<void> addGroupStudent({
    required String groupId,
    required String studentId,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/crm/groups/$groupId/students',
      data: {'studentId': studentId},
    );
  }

  Future<void> removeGroupStudent({
    required String groupId,
    required String studentId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/crm/groups/$groupId/students/$studentId',
    );
  }

  Future<List<Map<String, dynamic>>> listLeadStatuses({int limit = 100}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/lead-statuses',
      queryParameters: {'limit': limit},
    );
    return _items(response).map(_legacyLeadStatus).toList();
  }

  Future<List<Map<String, dynamic>>> listLeads({int limit = 100}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads',
      queryParameters: {'limit': limit},
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
    String? notes,
    Map<String, dynamic>? customDataPatch,
  }) async {
    final data = <String, dynamic>{};
    if (firstName != null) data['firstName'] = firstName.trim();
    if (lastName != null) data['lastName'] = lastName.trim();
    if (phone != null) data['phone'] = phone.trim();
    if (email != null) data['email'] = email.trim();
    if (source != null) data['source'] = source.trim();
    if (statusId != null) data['statusId'] = statusId.trim();
    if (notes != null) data['notes'] = notes.trim();
    if (customDataPatch != null) data['customDataPatch'] = customDataPatch;

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/leads/$id',
      data: data,
    );
    return _legacyLead(response);
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

  Future<Map<String, dynamic>> getScheduleMatrix({
    String? from,
    String? to,
    String? branchId,
    String? roomId,
    String? teacherId,
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
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;
    if (studentId != null) queryParameters['studentId'] = studentId;
    if (teacherId != null) queryParameters['teacherId'] = teacherId;
    if (isTrial != null) queryParameters['isTrial'] = isTrial;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/lessons',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyLesson).toList();
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
    if (notes != null && notes.trim().isNotEmpty) {
      data['notes'] = notes.trim();
    }

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/lessons',
      data: data,
    );
    return _legacyLesson(response);
  }

  Future<Map<String, dynamic>> updateLesson(
    String id, {
    String? studentId,
    String? groupId,
    String? teacherId,
    String? branchId,
    String? roomId,
    String? scheduledAt,
    int? durationMinutes,
    String? status,
    bool? isTrial,
    String? notes,
  }) async {
    final data = <String, dynamic>{};
    if (studentId != null) data['studentId'] = studentId;
    if (groupId != null) data['groupId'] = groupId;
    if (teacherId != null) data['teacherId'] = teacherId;
    if (branchId != null) data['branchId'] = branchId;
    if (roomId != null) data['roomId'] = roomId;
    if (scheduledAt != null) data['scheduledAt'] = scheduledAt;
    if (durationMinutes != null) data['durationMinutes'] = durationMinutes;
    if (status != null) data['status'] = status;
    if (isTrial != null) data['isTrial'] = isTrial;
    if (notes != null) data['notes'] = notes.trim();

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/lessons/$id',
      data: data,
    );
    return _legacyLesson(response);
  }

  Future<void> deleteLesson(String id) async {
    await _api.delete<Map<String, dynamic>>('/crm/lessons/$id');
  }

  Future<Map<String, dynamic>> getLessonAttendance(String lessonId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/lessons/$lessonId/attendance',
    );
    return _legacyAttendance(response);
  }

  Future<Map<String, dynamic>> saveLessonAttendance(
    String lessonId,
    List<Map<String, dynamic>> participations,
  ) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/lessons/$lessonId/attendance',
      data: {
        'items': participations
            .map(
              (item) => {
                'studentId': item['student_id'],
                'status': item['is_present'] == false ? 'absent' : 'present',
                'passReason': item['pass_reason']?.toString().trim() ?? '',
              },
            )
            .toList(),
      },
    );
    return _legacyAttendance(response);
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

  Future<Map<String, dynamic>> createTask({
    required String entityType,
    required String entityId,
    required String title,
    String? description,
    String status = 'open',
    String? dueAt,
    String? assignedTo,
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

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/tasks/$id',
      data: data,
    );
    return _legacyTask(response);
  }

  Future<List<Map<String, dynamic>>> listComments({
    required String entityType,
    required String entityId,
    bool progressOnly = false,
    int limit = 50,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/comments',
      queryParameters: {
        'entityType': entityType,
        'entityId': entityId,
        'progressOnly': progressOnly,
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
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/comments',
      data: {
        'entityType': entityType,
        'entityId': entityId,
        'body': body.trim(),
        'progress': progress,
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
    final queryParameters = <String, dynamic>{'limit': limit};
    if (studentId != null) queryParameters['studentId'] = studentId;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/subscriptions',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacySubscription).toList();
  }

  Future<List<Map<String, dynamic>>> listPayments({
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
    return _items(response).map(_legacyPayment).toList();
  }

  /// Like [listPayments] but also returns the server-side period totals
  /// (`totalAmount`, `totalCount`) over the full filtered set, so the UI can
  /// show a correct «Итого» rather than summing a truncated page.
  Future<({List<Map<String, dynamic>> items, num totalAmount, int totalCount})>
  listPaymentsWithTotal({String? from, String? to, String? studentId, int limit = 100}) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (studentId != null) queryParameters['studentId'] = studentId;
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/payments',
      queryParameters: queryParameters,
    );
    final items = _items(response).map(_legacyPayment).toList();
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

  Future<Map<String, dynamic>> createPayment({
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
    return _legacyPayment(response);
  }

  Future<void> updateTaskStatus(String id, String status) async {
    await updateTask(id, status: status);
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
    final items = response['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _mapList(
    Object? raw,
    Map<String, dynamic> Function(Map<String, dynamic>) mapper,
  ) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map<String, dynamic>>().map(mapper).toList();
  }

  Map<String, dynamic> _legacyLeadBoard(Map<String, dynamic> item) {
    final columns = item['columns'] is List
        ? item['columns'] as List
        : const [];
    return {
      'columns': columns.whereType<Map<String, dynamic>>().map((column) {
        final status = _legacyLeadStatus(column);
        final rawItems = column['items'] is List ? column['items'] as List : [];
        return {
          ...status,
          'total_count': column['totalCount'] ?? rawItems.length,
          'items': rawItems
              .whereType<Map<String, dynamic>>()
              .map(_legacyLeadBoardItem)
              .toList(),
        };
      }).toList(),
      'total_count': item['totalCount'] ?? 0,
      'next_cursor': item['nextCursor'],
    };
  }

  Map<String, dynamic> _legacyStudent(Map<String, dynamic> item) {
    final customData = item['customData'] is Map<String, dynamic>
        ? item['customData'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return {
      'id': item['id'],
      'lead_id': item['leadId'],
      'status': item['status'],
      'custom_data': customData,
      'profile_id': item['profileId'],
      'profile_user_id': item['profileUserId'],
      'first_name': item['firstName'],
      'last_name': item['lastName'],
      'middle_name': customData['middleName'] ?? customData['middle_name'],
      'hollihop_id': customData['hollihopId'] ?? customData['hollihop_id'],
      'birthday': customData['birthday'],
      'gender': customData['gender'],
      'individual_price':
          customData['individualPrice'] ?? customData['individual_price'],
      'contract_url':
          customData['legacyContractUrl'] ?? customData['contract_url'],
      'email': item['email'],
      'phone': item['phone'],
      'created_at': item['createdAt'],
      'profiles': {
        'id': item['profileId'],
        'user_id': item['profileUserId'],
        'first_name': item['firstName'],
        'last_name': item['lastName'],
        'phone': item['phone'],
      },
    };
  }

  Map<String, dynamic> _legacyStudentSearchItem(Map<String, dynamic> item) {
    final student = _legacyStudent(item);
    return {
      ...student,
      'branch_id': item['branchId'] ?? student['branch_id'],
      'branch_name': item['branchName'],
      'groups_count': item['groupsCount'] ?? 0,
      'open_tasks_count': item['openTasksCount'] ?? 0,
      'lessons_count': item['lessonsCount'] ?? 0,
      'payments_total': item['paymentsTotal'] ?? 0,
      'linked_user_id': item['linkedUserId'],
      'linked_user_email': item['linkedUserEmail'],
      'is_app_account': item['isAppAccount'] ?? false,
    };
  }

  Map<String, dynamic> _legacyOverviewStats(Map<String, dynamic> item) {
    return {
      'students': item['students'] ?? 0,
      'teachers': item['teachers'] ?? 0,
      'branches': item['branches'] ?? 0,
      'today_lessons': item['todayLessons'] ?? 0,
      'lessons_done': item['monthCompletedLessons'] ?? 0,
      'tasks_open': item['openTasks'] ?? 0,
      'leads_new': item['newLeads'] ?? 0,
      'revenue': item['revenueMonth'] ?? 0,
    };
  }

  Map<String, dynamic> _legacyManagerDashboard(Map<String, dynamic> item) {
    final kpis = item['kpis'] is Map<String, dynamic>
        ? item['kpis'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return {
      'from': item['from'],
      'to': item['to'],
      'branch_id': item['branchId'],
      'kpis': {
        'revenue': kpis['revenue'] ?? 0,
        'expected_payments': kpis['expectedPayments'] ?? 0,
        'debt_students': kpis['debtStudents'] ?? 0,
        'active_students': kpis['activeStudents'] ?? 0,
        'new_leads': kpis['newLeads'] ?? 0,
        'open_tasks': kpis['openTasks'] ?? 0,
        'overdue_tasks': kpis['overdueTasks'] ?? 0,
        'trial_lessons': kpis['trialLessons'] ?? 0,
        'schedule_issues': kpis['scheduleIssues'] ?? 0,
        'room_load_lessons': kpis['roomLoadLessons'] ?? 0,
        'staff_activity': kpis['staffActivity'] ?? 0,
      },
      'sources': item['sources'] ?? const <String, dynamic>{},
    };
  }

  Map<String, dynamic> _legacyFinanceReport(Map<String, dynamic> item) {
    final summary = item['summary'] is Map<String, dynamic>
        ? item['summary'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final monthly = item['monthly'] is List
        ? item['monthly'] as List
        : const [];
    final teachers = item['teachers'] is List
        ? item['teachers'] as List
        : const [];
    final rooms = item['rooms'] is List ? item['rooms'] as List : const [];

    return {
      'from': item['from'],
      'to': item['to'],
      'summary': {
        'attendance': summary['attendance'] ?? 0,
        'revenue': summary['revenue'] ?? 0,
        'total_lessons': summary['totalLessons'] ?? 0,
        'total_completed': summary['totalCompleted'] ?? 0,
      },
      'monthly': monthly
          .whereType<Map<String, dynamic>>()
          .map(
            (row) => {
              'month_start': row['monthStart'],
              'lessons': row['lessons'] ?? 0,
              'completed': row['completedLessons'] ?? 0,
              'new_students': row['newStudents'] ?? 0,
              'revenue': row['revenue'] ?? 0,
              'expenses': row['expenses'] ?? 0,
            },
          )
          .toList(),
      'teachers': teachers
          .whereType<Map<String, dynamic>>()
          .map(
            (row) => {
              'teacher_id': row['teacherId'],
              'name': row['teacherName'] ?? 'Без имени',
              'completed': row['completedLessons'] ?? 0,
              'revenue': row['revenue'] ?? 0,
            },
          )
          .toList(),
      'rooms': rooms
          .whereType<Map<String, dynamic>>()
          .map(
            (row) => {
              'room_id': row['roomId'],
              'name': row['roomName'] ?? 'Без аудитории',
              'lessons': row['lessons'] ?? 0,
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> _legacyTeacher(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'status': item['status'],
      'specialization': item['specialization'],
      'profile_id': item['profileId'],
      'profile_user_id': item['profileUserId'],
      'app_role': item['appRole'],
      'is_app_account': item['isAppAccount'],
      'first_name': item['firstName'],
      'last_name': item['lastName'],
      'email': item['email'],
      'phone': item['phone'],
      'custom_data': item['customData'] ?? const <String, dynamic>{},
      'branches': item['branches'] ?? const [],
      'students_count': item['studentsCount'] ?? 0,
      'lessons_count': item['lessonsCount'] ?? 0,
      'rating': item['rating'],
      'created_at': item['createdAt'],
      'profiles': {
        'first_name': item['firstName'],
        'last_name': item['lastName'],
        'phone': item['phone'],
      },
    };
  }

  Map<String, dynamic> _legacyStaff(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'role': item['role'],
      'position': item['position'],
      'status': item['status'],
      'custom_data': item['customData'] ?? const <String, dynamic>{},
      'profile_id': item['profileId'],
      'profile_user_id': item['profileUserId'],
      'app_role': item['appRole'],
      'is_app_account': item['isAppAccount'],
      'first_name': item['firstName'],
      'last_name': item['lastName'],
      'email': item['email'],
      'phone': item['phone'],
      'branches': item['branches'] ?? const [],
      'created_at': item['createdAt'],
      'profiles': {
        'first_name': item['firstName'],
        'last_name': item['lastName'],
        'phone': item['phone'],
      },
    };
  }

  Map<String, dynamic> _legacyActivityLog(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'actor_user_id': item['actorUserId'],
      'actor_name': item['actorName'],
      'actor_email': item['actorEmail'],
      'actor_role': item['actorRole'],
      'actor_staff_role': item['actorStaffRole'],
      'actor_position': item['actorPosition'],
      'actor_branches': item['actorBranches'] ?? const [],
      'action': item['action'],
      'entity_type': item['entityType'],
      'entity_id': item['entityId'],
      'history_type': item['historyType'],
      'description': item['description'],
      'branch_id': item['branchId'],
      'metadata': item['metadata'] ?? const <String, dynamic>{},
      'created_at': item['createdAt'],
    };
  }

  Map<String, dynamic> _legacyBranch(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'name': item['name'],
      'address': item['address'],
      'utc_offset_minutes': item['utcOffsetMinutes'] ?? 180,
      'created_at': item['createdAt'],
    };
  }

  Map<String, dynamic> _legacyRoom(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'branch_id': item['branchId'],
      'name': item['name'],
      'capacity': item['capacity'],
      'created_at': item['createdAt'],
      'branches': {'id': item['branchId'], 'name': item['branchName']},
    };
  }

  Map<String, dynamic> _legacyRoomAvailability(Map<String, dynamic> item) {
    return {
      'room_id': item['roomId'],
      'branch_id': item['branchId'],
      'branch_name': item['branchName'],
      'room_name': item['roomName'],
      'capacity': item['capacity'],
      'lessons': item['lessons'] ?? const [],
      'is_available': item['isAvailable'] ?? false,
      'conflict_types': item['conflictTypes'] ?? const [],
    };
  }

  Map<String, dynamic> _legacyScheduleLesson(Map<String, dynamic> item) {
    return {
      ..._legacyLesson(item),
      'conflict_types': item['conflictTypes'] ?? const [],
    };
  }

  Map<String, dynamic> _legacyScheduleGroup(Map<String, dynamic> item) {
    return {
      'key': item['key'],
      'label': item['label'],
      'items': _mapList(item['items'], _legacyScheduleLesson),
    };
  }

  Map<String, dynamic> _legacyScheduleConflict(Map<String, dynamic> item) {
    return {
      'type': item['type'],
      'lesson_id': item['lessonId'],
      'scheduled_at': item['scheduledAt'],
      'room_id': item['roomId'],
      'teacher_id': item['teacherId'],
    };
  }

  Map<String, dynamic> _legacyGroup(Map<String, dynamic> item) {
    final teacherParts = _splitName(item['teacherName']?.toString() ?? '');
    return {
      'id': item['id'],
      'teacher_id': item['teacherId'],
      'branch_id': item['branchId'],
      'room_id': item['roomId'],
      'name': item['name'],
      'price_per_lesson': item['pricePerLesson'],
      'created_at': item['createdAt'],
      'teachers': {
        'id': item['teacherId'],
        'name': item['teacherName'],
        'first_name': teacherParts.$1,
        'last_name': teacherParts.$2,
      },
      'branches': {'id': item['branchId'], 'name': item['branchName']},
      'rooms': {'id': item['roomId'], 'name': item['roomName']},
    };
  }

  Map<String, dynamic> _legacyLeadStatus(Map<String, dynamic> item) {
    final id = item['id'];
    final name = item['name'] ?? item['label'] ?? 'Без названия';
    return {
      'id': id,
      'key': id,
      'name': name,
      'label': name,
      'color': item['color'] ?? '8B5CF6',
      'sort_order': item['sortOrder'],
      'created_at': item['createdAt'],
    };
  }

  Map<String, dynamic> _legacyLead(Map<String, dynamic> item) {
    final firstName = item['firstName'];
    final lastName = item['lastName'];
    final statusId = item['statusId'];
    final statusName = item['statusName'];
    final customData = item['customData'] is Map<String, dynamic>
        ? item['customData'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return {
      'id': item['id'],
      'status_id': statusId,
      'status': statusId ?? statusName ?? 'new',
      'status_label': statusName,
      'name': firstName,
      'first_name': firstName,
      'last_name': lastName,
      'phone': item['phone'],
      'email': item['email'],
      'source': item['source'],
      'notes': item['notes'],
      'assigned_to': item['assignedTo'],
      'custom_data': customData,
      'hollihop_id':
          customData['hollihopId'] ??
          customData['hollihop_id'] ??
          item['hollihopId'],
      'branch_id': customData['branchId'] ?? customData['branch_id'],
      'created_by': item['createdBy'],
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
    };
  }

  Map<String, dynamic> _legacyLeadBoardItem(Map<String, dynamic> item) {
    final lead = _legacyLead(item);
    return {
      ...lead,
      'status_color': item['statusColor'],
      'status_sort_order': item['statusSortOrder'],
      'assigned_name': item['assignedName'],
      'branch_id': item['branchId'] ?? lead['branch_id'],
      'branch_name': item['branchName'],
      'linked_student_id': item['linkedStudentId'],
      'open_tasks_count': item['openTasksCount'] ?? 0,
      'comments_count': item['commentsCount'] ?? 0,
      'trial_lessons_count': item['trialLessonsCount'] ?? 0,
    };
  }

  Map<String, dynamic> _legacyLesson(Map<String, dynamic> item) {
    final teacherParts = _splitName(item['teacherName']?.toString() ?? '');
    final studentParts = _splitName(item['studentName']?.toString() ?? '');
    return {
      'id': item['id'],
      'student_id': item['studentId'],
      'group_id': item['groupId'],
      'lead_id': item['leadId'],
      'teacher_id': item['teacherId'],
      'branch_id': item['branchId'],
      'room_id': item['roomId'],
      'scheduled_at': item['scheduledAt'],
      'duration_minutes': item['durationMinutes'],
      'status': item['status'],
      'is_trial': item['isTrial'],
      'notes': item['notes'],
      'student_name': item['studentName'],
      'teacher_name': item['teacherName'],
      'branch_name': item['branchName'],
      'room_name': item['roomName'],
      'group_name': item['groupName'],
      'group_price_per_lesson': item['groupPricePerLesson'],
      'student_first_name': studentParts.$1,
      'student_last_name': studentParts.$2,
      'teacher_first_name': teacherParts.$1,
      'teacher_last_name': teacherParts.$2,
      'teacher_profile_first_name': teacherParts.$1,
      'teacher_profile_last_name': teacherParts.$2,
      'groups': {
        'id': item['groupId'],
        'name': item['groupName'],
        'price_per_lesson': item['groupPricePerLesson'],
      },
      'rooms': {
        'id': item['roomId'],
        'name': item['roomName'],
        'branches': {'id': item['branchId'], 'name': item['branchName']},
      },
      'branches': {'id': item['branchId'], 'name': item['branchName']},
    };
  }

  Map<String, dynamic> _legacyAttendance(Map<String, dynamic> item) {
    final students = item['students'] is List ? item['students'] as List : [];
    final legacyStudents = <Map<String, dynamic>>[];
    final legacyParticipations = <Map<String, dynamic>>[];

    for (final raw in students.whereType<Map<String, dynamic>>()) {
      final studentId = raw['studentId'];
      final status = raw['status']?.toString() ?? 'present';
      legacyStudents.add({
        'id': studentId,
        'name': raw['studentName'] ?? 'Без имени',
      });
      legacyParticipations.add({
        'lesson_id': item['lessonId'],
        'student_id': studentId,
        'is_present': status != 'absent',
        'pass_reason': raw['passReason'] ?? '',
      });
    }

    return {
      'lesson_id': item['lessonId'],
      'students': legacyStudents,
      'participations': legacyParticipations,
    };
  }

  Map<String, dynamic> _legacyTask(Map<String, dynamic> item) {
    final entityType = item['entityType'];
    final entityId = item['entityId'];
    final entityName = item['entityName'];
    final assignedName = item['assignedName'];
    final entityParts = _splitName(entityName?.toString() ?? '');
    final assignedParts = _splitName(assignedName?.toString() ?? '');
    return {
      'id': item['id'],
      'entity_type': entityType,
      'entity_id': entityId,
      'student_id': entityType == 'student' ? entityId : null,
      'assigned_to': item['assignedTo'],
      'assigned_name': assignedName,
      'entity_name': entityName,
      'title': item['title'],
      'description': item['description'],
      'status': item['status'],
      'due_at': item['dueAt'],
      'due_date': item['dueAt'],
      'created_by': item['createdBy'],
      'creator_name': item['creatorName'],
      'branch_id': item['branchId'],
      'branch_name': item['branchName'],
      'created_at': item['createdAt'],
      'profiles': {
        'id': item['assignedTo'],
        'first_name': assignedParts.$1,
        'last_name': assignedParts.$2,
      },
      'students': entityType == 'student'
          ? {
              'id': entityId,
              'first_name': entityParts.$1,
              'last_name': entityParts.$2,
            }
          : null,
      'teachers': entityType == 'teacher'
          ? {
              'id': entityId,
              'first_name': entityParts.$1,
              'last_name': entityParts.$2,
            }
          : null,
      'leads': entityType == 'lead'
          ? {'id': entityId, 'name': entityName}
          : null,
      'groups': entityType == 'group'
          ? {'id': entityId, 'name': entityName}
          : null,
    };
  }

  Map<String, dynamic> _legacyComment(Map<String, dynamic> item) {
    final content = item['body'];
    return {
      'id': item['id'],
      'entity_type': item['entityType'],
      'entity_id': item['entityId'],
      'author_id': item['authorId'],
      'author_name': item['authorName'],
      'body': content,
      'content': content,
      'created_at': item['createdAt'],
      'profiles': {
        'first_name': _splitName(item['authorName']?.toString() ?? '').$1,
        'last_name': _splitName(item['authorName']?.toString() ?? '').$2,
      },
    };
  }

  Map<String, dynamic> _legacyTimelineItem(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'type': item['type'],
      'title': item['title'],
      'body': item['body'],
      'status': item['status'],
      'amount': item['amount'],
      'actor_user_id': item['actorUserId'],
      'actor_name': item['actorName'],
      'occurred_at': item['occurredAt'],
    };
  }

  Map<String, dynamic> _legacyCrmLink(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'user_id': item['userId'],
      'email': item['email'],
      'phone': item['phone'],
      'link_source': item['linkSource'],
      'confirmed_at': item['confirmedAt'],
      'created_at': item['createdAt'],
    };
  }

  Map<String, dynamic> _legacyDuplicateCandidate(Map<String, dynamic> item) {
    final entityA = item['entityA'] is Map<String, dynamic>
        ? item['entityA'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final entityB = item['entityB'] is Map<String, dynamic>
        ? item['entityB'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return {
      'id': item['id'],
      'entity_type_a': item['entityTypeA'],
      'entity_id_a': item['entityIdA'],
      'entity_type_b': item['entityTypeB'],
      'entity_id_b': item['entityIdB'],
      'match_type': item['matchType'],
      'match_value': item['matchValue'],
      'confidence': item['confidence'],
      'source': item['source'],
      'status': item['status'],
      'decided_at': item['decidedAt'],
      'decided_by': item['decidedBy'],
      'decision_notes': item['decisionNotes'],
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
      'entity_a': {
        'name': entityA['name'],
        'phone': entityA['phone'],
        'email': entityA['email'],
      },
      'entity_b': {
        'name': entityB['name'],
        'phone': entityB['phone'],
        'email': entityB['email'],
      },
    };
  }

  Map<String, dynamic> _legacySubscription(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'student_id': item['studentId'],
      'lessons_total': item['lessonsTotal'],
      'lessons_used': item['lessonsUsed'],
      'starts_at': item['startsAt'],
      'expires_at': item['expiresAt'],
      'valid_until': item['expiresAt'],
      'status': item['status'],
      'type': item['status'] == 'active' ? 'Абонемент' : item['status'],
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
    };
  }

  Map<String, dynamic> _legacyPayment(Map<String, dynamic> item) {
    final studentName = item['studentName']?.toString() ?? '';
    final studentParts = _splitName(studentName);
    return {
      'id': item['id'],
      'student_id': item['studentId'],
      'amount': item['amount'],
      'currency': item['currency'],
      'payment_date': item['paymentDate'],
      'method': item['method'],
      'type': item['method'],
      'external_id': item['externalId'],
      'notes': item['notes'],
      'description': item['notes'] ?? item['description'],
      'created_by': item['createdBy'],
      'created_at': item['createdAt'],
      'students': {
        'id': item['studentId'],
        'first_name': studentParts.$1,
        'last_name': studentParts.$2,
      },
    };
  }

  Map<String, dynamic> _legacyExpectedPayment(Map<String, dynamic> item) {
    final studentName = item['studentName']?.toString() ?? '';
    final studentParts = _splitName(studentName);
    return {
      'id': item['id'],
      'student_id': item['studentId'],
      'amount': item['amount'],
      'due_date': item['dueDate'],
      'status': item['status'],
      'description': item['description'],
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
      'students': {
        'id': item['studentId'],
        'first_name': studentParts.$1,
        'last_name': studentParts.$2,
      },
    };
  }

  Map<String, dynamic> _legacyStudentBalance(Map<String, dynamic> item) {
    final student = item['student'];
    final studentMap = student is Map<String, dynamic>
        ? student
        : const <String, dynamic>{};
    return {
      'student_id': item['studentId'],
      'balance': item['balance'],
      'total_paid': item['totalPaid'],
      'total_cost': item['totalCost'],
      'updated_at': item['updatedAt'],
      'students': {
        'profiles': {
          'first_name': studentMap['firstName'],
          'last_name': studentMap['lastName'],
          'phone': studentMap['phone'],
        },
      },
    };
  }

  (String, String) _splitName(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.skip(1).join(' '));
  }
}
