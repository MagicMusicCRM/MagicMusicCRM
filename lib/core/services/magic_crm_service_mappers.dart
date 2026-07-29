part of 'magic_crm_service.dart';

// Response mappers: normalize backend payloads into the legacy map shape the
// widgets expect. Pure functions (no _api / no this) — shared across domains.
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
  final columns = item['columns'] is List ? item['columns'] as List : const [];
  return {
    'columns': columns.whereType<Map<String, dynamic>>().map((column) {
      final status = _legacyLeadStatus(column);
      final rawItems = column['items'] is List ? column['items'] as List : [];
      return {
        ...status,
        'total_count': column['totalCount'] ?? rawItems.length,
        'next_cursor': column['nextCursor'],
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
    'version': item['version'],
    'lifecycle_state': item['lifecycleState'],
    'lead_id': item['leadId'],
    'status': item['status'],
    'custom_data': customData,
    'profile_id': item['profileId'],
    'profile_user_id': item['profileUserId'],
    // HolliHop-imported clients have no linked profile, so their name/contact
    // live only in custom_data — fall back to it so the card isn't blank.
    'first_name':
        item['firstName'] ??
        customData['firstName'] ??
        customData['first_name'],
    'last_name':
        item['lastName'] ?? customData['lastName'] ?? customData['last_name'],
    'middle_name': customData['middleName'] ?? customData['middle_name'],
    'hollihop_id': customData['hollihopId'] ?? customData['hollihop_id'],
    'birthday': customData['birthday'],
    'gender': customData['gender'],
    'individual_price':
        customData['individualPrice'] ?? customData['individual_price'],
    'contract_url':
        customData['legacyContractUrl'] ?? customData['contract_url'],
    'email': item['email'] ?? customData['email'],
    'phone': item['phone'] ?? customData['phone'],
    'created_at': item['createdAt'],
    // Дата обращения, разрешённая сервером: явное значение → исходная дата
    // HolliHop → момент появления записи здесь. Считать её на клиенте нельзя —
    // правило одно для лида и ученика и живёт в appeal-date.ts.
    'appeal_at': item['appealAt'],
    'appeal_at_source': item['appealAtSource'],
    // Возраст, разрешённый сервером: дата рождения → вписанный руками.
    // Правило одно для лида и ученика и живёт в age.ts.
    'age': item['age'],
    'age_months': item['ageMonths'],
    'age_source': item['ageSource'],
    // Чёрный список = бан: карточка красится, чаты клиенту закрыты.
    'blacklisted': item['blacklisted'] == true,
    'blacklist_reason': item['blacklistReason'],
    'profiles': {
      'id': item['profileId'],
      'user_id': item['profileUserId'],
      'first_name':
          item['firstName'] ??
          customData['firstName'] ??
          customData['first_name'],
      'last_name':
          item['lastName'] ?? customData['lastName'] ?? customData['last_name'],
      'phone': item['phone'] ?? customData['phone'],
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
    'disciplines': item['disciplines'] ?? const <dynamic>[],
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
  final monthly = item['monthly'] is List ? item['monthly'] as List : const [];
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
  final customData = item['customData'] is Map<String, dynamic>
      ? item['customData'] as Map<String, dynamic>
      : const <String, dynamic>{};
  // Преподаватели без профиля хранят имя только в custom_data — берём оттуда,
  // чтобы карточка не показывалась пустой (как в _legacyStudent).
  final firstName =
      item['firstName'] ?? customData['firstName'] ?? customData['first_name'];
  final lastName =
      item['lastName'] ?? customData['lastName'] ?? customData['last_name'];
  return {
    'id': item['id'],
    'status': item['status'],
    'specialization': item['specialization'],
    'profile_id': item['profileId'],
    'profile_user_id': item['profileUserId'],
    'app_role': item['appRole'],
    'is_app_account': item['isAppAccount'],
    'first_name': firstName,
    'last_name': lastName,
    'email': item['email'],
    'phone': item['phone'],
    'custom_data': customData,
    'branches': item['branches'] ?? const [],
    'students_count': item['studentsCount'] ?? 0,
    'lessons_count': item['lessonsCount'] ?? 0,
    'rating': item['rating'],
    // KVA-238: зарплатные поля и явные связи карточки педагога.
    'salary': item['salary'],
    'current_rate': item['currentRate'],
    'disciplines': item['disciplines'] ?? const [],
    'assigned_branches': item['assignedBranches'] ?? const [],
    'created_at': item['createdAt'],
    'profiles': {
      'first_name': firstName,
      'last_name': lastName,
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
    // KVA-238: null = брать ставку педагога, 0 = «входит в оклад».
    'teacher_rate': item['teacherRate'],
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
    // См. комментарий в _legacyStudent: дату обращения и возраст разрешает сервер.
    'appeal_at': item['appealAt'],
    'appeal_at_source': item['appealAtSource'],
    'age': item['age'],
    'age_months': item['ageMonths'],
    'age_source': item['ageSource'],
    'blacklisted': item['blacklisted'] == true,
    'blacklist_reason': item['blacklistReason'],
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
    'teacher_rate': item['teacherRate'],
    // Rate actually paid for this lesson (lesson → group → history). null when
    // the caller may not see pay data.
    'applied_teacher_rate': item['appliedTeacherRate'],
    // «Оплаты по дням»: сколько пришло за этот день. null — платежа за него
    // нет (или роль его не видит), и это НЕ «оплачено 0».
    'paid_amount': item['paidAmount'],
    'student_name': item['studentName'],
    'teacher_name': item['teacherName'],
    // Пробное занятие лида: ученика/группы нет, подписывается именем лида.
    'lead_name': item['leadName'],
    'branch_name': item['branchName'],
    'room_name': item['roomName'],
    'group_name': item['groupName'],
    'group_price_per_lesson': item['groupPricePerLesson'],
    'completion_type': item['completionType'],
    'client_charge_type': item['clientChargeType'],
    'client_charge_value': item['clientChargeValue'],
    'teacher_compensation_type': item['teacherCompensationType'],
    'teacher_compensation_value': item['teacherCompensationValue'],
    'subscription_id': item['subscriptionId'],
    'snapshot_trial': item['snapshotTrial'],
    'snapshot_validation_state': item['snapshotValidationState'],
    'lifecycle_state': item['lifecycleState'],
    'reservation_state': item['reservationState'],
    'student_first_name': studentParts.$1,
    'student_last_name': studentParts.$2,
    'teacher_first_name': teacherParts.$1,
    'teacher_last_name': teacherParts.$2,
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
    'assigned_profile_id': item['assignedProfileId'],
    'creator_profile_id': item['creatorProfileId'],
    'assigned_name': assignedName,
    'entity_name': entityName,
    'title': item['title'],
    'description': item['description'],
    'status': item['status'],
    'priority': item['priority'] ?? 'medium',
    'due_at': item['dueAt'],
    'due_date': item['dueAt'],
    'due_all_day': item['dueAllDay'] ?? false,
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
    'leads': entityType == 'lead' ? {'id': entityId, 'name': entityName} : null,
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
    'kind': item['kind'],
    'progress': item['progress'],
    'created_at': item['createdAt'],
    // Заполнено только у комментариев к занятиям — см. Comment.isAboutLesson.
    'lesson_at': item['lessonAt'],
    'profiles': {
      'first_name': _splitName(item['authorName']?.toString() ?? '').$1,
      'last_name': _splitName(item['authorName']?.toString() ?? '').$2,
    },
  };
}

Map<String, dynamic> _legacyStatusHistoryItem(Map<String, dynamic> item) {
  return {
    'id': item['id'],
    'old_status': item['oldStatus'],
    'new_status': item['newStatus'],
    'old_owner_id': item['oldOwnerId'],
    'new_owner_id': item['newOwnerId'],
    'changed_by': item['changedBy'],
    'changed_by_name': item['changedByName'],
    'changed_at': item['changedAt'],
    'reason_id': item['reasonId'],
    'comment': item['comment'],
  };
}

Map<String, dynamic> _legacyTaskHistoryItem(Map<String, dynamic> item) {
  return {
    'id': item['id'],
    'field': item['field'],
    'old_value': item['oldValue'],
    'new_value': item['newValue'],
    'changed_at': item['changedAt'],
    'source': item['source'],
    'changed_by': item['changedBy'],
    'author_profile_id': item['authorProfileId'],
    'author_name': item['authorName'],
    'old_user_id': item['oldUserId'],
    'old_user_name': item['oldUserName'],
    'new_user_id': item['newUserId'],
    'new_user_name': item['newUserName'],
    // Only present in the cross-task supervisor feed.
    'task_id': item['taskId'],
    'task_title': item['taskTitle'],
    'task_entity_type': item['taskEntityType'],
    'task_entity_id': item['taskEntityId'],
  };
}

Map<String, dynamic> _legacyFamilyMember(Map<String, dynamic> item) {
  return {
    'id': item['id'],
    'entity_type': item['entityType'],
    'entity_id': item['entityId'],
    'role': item['role'],
    'is_primary_contact': item['isPrimaryContact'] == true,
    'name': item['name'],
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
    'package_name': item['packageName'],
    'package_price': item['packagePrice'],
    // «Оплачено» — приход личного счёта, которым закрыт абонемент.
    'paid_amount': item['paidAmount'],
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
