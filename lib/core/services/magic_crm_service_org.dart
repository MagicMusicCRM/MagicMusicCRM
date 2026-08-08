part of 'magic_crm_service.dart';

/// Org: branches, disciplines, rooms, room availability, groups.
extension MagicCrmOrg on MagicCrmService {
  Future<List<Map<String, dynamic>>> listBranches({int limit = 100}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches',
      queryParameters: {'limit': limit},
    );
    return _items(response).map(_legacyBranch).toList();
  }

  Future<int> getAppLeadsCount() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads/app-count',
    );
    final raw = response['count'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<List<Map<String, dynamic>>> listBranchDisciplines(
    String branchId,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches/$branchId/disciplines',
    );
    return _items(response).map((item) {
      return {
        'id': item['id'],
        'discipline_id': item['disciplineId'],
        'name': item['name'],
        'sort_order': (item['sortOrder'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listDisciplines() async {
    final response = await _api.get<Map<String, dynamic>>('/crm/disciplines');
    return _items(
      response,
    ).map((item) => {'id': item['id'], 'name': item['name']}).toList();
  }

  Future<void> assignBranchDiscipline({
    required String branchId,
    required String disciplineId,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/crm/branches/$branchId/disciplines',
      data: {'disciplineId': disciplineId},
    );
  }

  Future<Map<String, dynamic>> createBranch({
    required String name,
    String? address,
    int? utcOffsetMinutes,
  }) async {
    final data = <String, dynamic>{'name': name.trim()};
    final trimmedAddress = address?.trim();
    if (trimmedAddress != null && trimmedAddress.isNotEmpty) {
      data['address'] = trimmedAddress;
    }
    if (utcOffsetMinutes != null) data['utcOffsetMinutes'] = utcOffsetMinutes;
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/branches',
      data: data,
    );
    return _legacyBranch(response);
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
    required String branchId,
    int? capacity,
  }) async {
    final data = <String, dynamic>{'name': name.trim(), 'branchId': branchId};
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

  /// One group by id. Callers holding only an id (a task pointing at a group)
  /// can't use listGroups: it is capped, so the group may simply not be there.
  Future<Map<String, dynamic>> getGroup(String id) async {
    final response = await _api.get<Map<String, dynamic>>('/crm/groups/$id');
    return _legacyGroup(response);
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    required String teacherId,
    required String branchId,
    required String roomId,
    num? pricePerLesson,
    // KVA-238: переопределение ставки педагога (0 = «входит в оклад»).
    num? teacherRate,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'teacherId': teacherId.trim(),
      'branchId': branchId.trim(),
      'roomId': roomId.trim(),
    };
    if (pricePerLesson != null) data['pricePerLesson'] = pricePerLesson;
    if (teacherRate != null) data['teacherRate'] = teacherRate;

    final response = await _api.post<Map<String, dynamic>>(
      '/crm/groups',
      data: data,
    );
    return _legacyGroup(response);
  }

  /// KVA-238: частичное обновление группы. [teacherRate] отправляется только
  /// при [setTeacherRate] = true; null при выставленном флаге сбрасывает
  /// переопределение («брать ставку педагога»), 0 — «входит в оклад».
  Future<Map<String, dynamic>> updateGroup(
    String id, {
    String? name,
    String? teacherId,
    String? branchId,
    String? roomId,
    num? pricePerLesson,
    num? teacherRate,
    bool setTeacherRate = false,
  }) async {
    final data = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) data['name'] = name.trim();
    if (teacherId != null) data['teacherId'] = teacherId;
    if (branchId != null) data['branchId'] = branchId;
    if (roomId != null) data['roomId'] = roomId;
    if (pricePerLesson != null) data['pricePerLesson'] = pricePerLesson;
    if (setTeacherRate) data['teacherRate'] = teacherRate;

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/groups/$id',
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
}
