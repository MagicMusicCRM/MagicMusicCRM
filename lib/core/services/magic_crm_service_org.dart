part of 'magic_crm_service.dart';

/// Org: branches, disciplines, rooms, room availability, groups.
extension MagicCrmOrg on MagicCrmService {
  Future<List<Map<String, dynamic>>> listBranches({
    int limit = 100,
    bool includeArchived = false,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches',
      queryParameters: {
        'limit': limit,
        if (includeArchived) 'includeArchived': true,
      },
    );
    return _items(response).map(_legacyBranch).toList();
  }

  Future<Map<String, dynamic>> previewBranchClose(String id) {
    return _api.post<Map<String, dynamic>>(
      '/crm/branches/$id/close-preview',
      data: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> closeBranch(
    String id, {
    required int expectedVersion,
    required String reasonText,
    required String effectiveDate,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/branches/$id/close',
      data: {
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
        'effectiveDate': effectiveDate,
      },
    );
  }

  Future<Map<String, dynamic>> restoreBranch(
    String id, {
    required int expectedVersion,
    required String reasonText,
    required String effectiveDate,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/branches/$id/restore',
      data: {
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
        'effectiveDate': effectiveDate,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listBranchLifecycleHistory(
    String id,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches/$id/history',
    );
    return _items(response);
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
    String branchId, {
    bool includeArchived = false,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches/$branchId/disciplines',
      queryParameters: {if (includeArchived) 'includeArchived': true},
    );
    return _items(response).map((item) {
      return {
        'id': item['id'],
        'discipline_id': item['disciplineId'],
        'name': item['name'],
        'sort_order': (item['sortOrder'] as num?)?.toInt() ?? 0,
        'lifecycle_state': item['lifecycleState'] ?? 'active',
        'version': (item['version'] as num?)?.toInt() ?? 1,
        'archived_at': item['archivedAt'],
        'archive_reason': item['archiveReason'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listDisciplines({
    bool includeArchived = false,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/disciplines',
      queryParameters: {if (includeArchived) 'includeArchived': true},
    );
    return _items(response).map((item) {
      return {
        'id': item['id'],
        'name': item['name'],
        'lifecycle_state': item['lifecycleState'] ?? 'active',
        'version': (item['version'] as num?)?.toInt() ?? 1,
        'archived_at': item['archivedAt'],
        'archive_reason': item['archiveReason'],
        'active_usage': item['activeUsage'],
      };
    }).toList();
  }

  Future<Map<String, dynamic>> createDiscipline(String name) {
    return _api.post<Map<String, dynamic>>(
      '/crm/disciplines',
      data: {'name': name.trim()},
    );
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

  Future<Map<String, dynamic>> previewReferenceCatalogLifecycle({
    required String entityType,
    required String id,
  }) {
    return _api.post<Map<String, dynamic>>(
      '${_referenceCatalogPath(entityType, id)}/lifecycle-preview',
      data: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> renameReferenceCatalogItem({
    required String entityType,
    required String id,
    required String name,
    required int expectedVersion,
    required String reasonText,
  }) {
    return _api.patch<Map<String, dynamic>>(
      _referenceCatalogPath(entityType, id),
      data: {
        'name': name.trim(),
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> archiveReferenceCatalogItem({
    required String entityType,
    required String id,
    required int expectedVersion,
    required String reasonText,
  }) {
    final action = entityType == 'branch_discipline' ? 'unassign' : 'archive';
    return _api.post<Map<String, dynamic>>(
      '${_referenceCatalogPath(entityType, id)}/$action',
      data: {
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> restoreReferenceCatalogItem({
    required String entityType,
    required String id,
    required int expectedVersion,
    required String reasonText,
  }) {
    return _api.post<Map<String, dynamic>>(
      '${_referenceCatalogPath(entityType, id)}/restore',
      data: {
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> listReferenceCatalogHistory({
    required String entityType,
    required String id,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '${_referenceCatalogPath(entityType, id)}/history',
    );
    return _items(response);
  }

  String _referenceCatalogPath(String entityType, String id) {
    return switch (entityType) {
      'discipline' => '/crm/disciplines/$id',
      'loss_reason' => '/crm/loss-reasons/$id',
      'branch_discipline' => '/crm/branch-disciplines/$id',
      _ => throw ArgumentError.value(entityType, 'entityType'),
    };
  }

  Future<Map<String, dynamic>> createBranch({
    required String name,
    required List<Map<String, dynamic>> weeklyHours,
    String? address,
    int? utcOffsetMinutes,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'weeklyHours': weeklyHours,
    };
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
    bool includeArchived = false,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (branchId != null) queryParameters['branchId'] = branchId;
    if (includeArchived) queryParameters['includeArchived'] = true;

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
    bool clearCapacity = false,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name.trim();
    if (branchId != null) data['branchId'] = branchId;
    if (capacity != null || clearCapacity) data['capacity'] = capacity;

    final response = await _api.patch<Map<String, dynamic>>(
      '/crm/rooms/$id',
      data: data,
    );
    return _legacyRoom(response);
  }

  Future<Map<String, dynamic>> previewRoomArchive(String id) {
    return _api.post<Map<String, dynamic>>(
      '/crm/rooms/$id/archive-preview',
      data: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> archiveRoom(
    String id, {
    required int expectedVersion,
    required String reasonText,
    required String effectiveDate,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/rooms/$id/archive',
      data: {
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
        'effectiveDate': effectiveDate,
      },
    );
  }

  Future<Map<String, dynamic>> restoreRoom(
    String id, {
    required int expectedVersion,
    required String reasonText,
    required String effectiveDate,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/rooms/$id/restore',
      data: {
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
        'effectiveDate': effectiveDate,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listRoomLifecycleHistory(String id) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/rooms/$id/history',
    );
    return _items(response);
  }

  Future<List<Map<String, dynamic>>> listGroups({
    String? branchId,
    int limit = 100,
    bool includeArchived = false,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (branchId != null) queryParameters['branchId'] = branchId;
    if (includeArchived) queryParameters['includeArchived'] = true;

    final response = await _api.get<Map<String, dynamic>>(
      '/crm/groups',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyGroup).toList();
  }

  Future<Map<String, dynamic>> previewGroupArchive(String id) {
    return _api.post<Map<String, dynamic>>(
      '/crm/groups/$id/archive-preview',
      data: const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> archiveGroup(
    String id, {
    required int expectedVersion,
    required String reasonText,
    required String effectiveDate,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/groups/$id/archive',
      data: {
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
        'effectiveDate': effectiveDate,
      },
    );
  }

  Future<Map<String, dynamic>> restoreGroup(
    String id, {
    required int expectedVersion,
    required String reasonText,
    required String effectiveDate,
  }) {
    return _api.post<Map<String, dynamic>>(
      '/crm/groups/$id/restore',
      data: {
        'expectedVersion': expectedVersion,
        'confirm': true,
        'reasonText': reasonText.trim(),
        'effectiveDate': effectiveDate,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listGroupLifecycleHistory(
    String id,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/groups/$id/history',
    );
    return _items(response);
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
    int? expectedVersion,
  }) async {
    final data = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) data['name'] = name.trim();
    if (teacherId != null) data['teacherId'] = teacherId;
    if (branchId != null) data['branchId'] = branchId;
    if (roomId != null) data['roomId'] = roomId;
    if (pricePerLesson != null) data['pricePerLesson'] = pricePerLesson;
    if (setTeacherRate) {
      data['teacherRate'] = teacherRate;
      data['expectedVersion'] = expectedVersion;
    }

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
