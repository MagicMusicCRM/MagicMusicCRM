import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

void main() {
  group('MagicCrmService', () {
    test('maps overview stats to legacy dashboard keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/overview',
          statusCode: 200,
          body: {
            'students': 12,
            'teachers': 3,
            'branches': 2,
            'todayLessons': 5,
            'monthCompletedLessons': 18,
            'openTasks': 4,
            'newLeads': 6,
            'revenueMonth': 125000.5,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final stats = await service.getOverviewStats();

      expect(stats['students'], 12);
      expect(stats['today_lessons'], 5);
      expect(stats['lessons_done'], 18);
      expect(stats['tasks_open'], 4);
      expect(stats['leads_new'], 6);
      expect(stats['revenue'], 125000.5);
    });

    test('maps manager dashboard KPI contract', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/dashboard/manager',
          statusCode: 200,
          body: {
            'from': '2026-06-01T00:00:00.000Z',
            'to': '2026-07-01T00:00:00.000Z',
            'branchId': 'branch-a',
            'kpis': {
              'revenue': 120000.5,
              'expectedPayments': 35000,
              'debtStudents': 4,
              'activeStudents': 120,
              'newLeads': 18,
              'openTasks': 9,
              'overdueTasks': 3,
              'trialLessons': 7,
              'scheduleIssues': 2,
              'roomLoadLessons': 46,
              'staffActivity': 31,
            },
            'sources': {'tasks': '/crm/tasks'},
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final dashboard = await service.getManagerDashboard(
        from: '2026-06-01T00:00:00.000Z',
        to: '2026-07-01T00:00:00.000Z',
        branchId: 'branch-a',
      );

      expect(dashboard['kpis']['schedule_issues'], 2);
      expect(dashboard['kpis']['staff_activity'], 31);
      expect(dashboard['sources']['tasks'], '/crm/tasks');
      expect(adapter.requests.single.queryParameters['branchId'], 'branch-a');
    });

    test('maps finance report to report widget legacy keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/reports/finance',
          statusCode: 200,
          body: {
            'from': '2026-06-01T00:00:00.000Z',
            'to': '2026-07-01T00:00:00.000Z',
            'summary': {
              'attendance': 75,
              'revenue': 12000.5,
              'totalLessons': 4,
              'totalCompleted': 3,
            },
            'monthly': [
              {
                'monthStart': '2026-06-01T00:00:00.000Z',
                'lessons': 4,
                'completedLessons': 3,
                'newStudents': 2,
                'revenue': 12000.5,
                'expenses': 3000,
              },
            ],
            'teachers': [
              {
                'teacherId': 'teacher-a',
                'teacherName': 'Иван Петров',
                'completedLessons': 3,
                'revenue': 9000,
              },
            ],
            'rooms': [
              {'roomId': 'room-a', 'roomName': '101', 'lessons': 4},
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final report = await service.getFinanceReport(
        from: '2026-06-01T00:00:00.000Z',
        to: '2026-07-01T00:00:00.000Z',
      );

      expect(report['summary']['total_lessons'], 4);
      expect(report['monthly'].single['completed'], 3);
      expect(report['monthly'].single['expenses'], 3000);
      expect(report['teachers'].single['name'], 'Иван Петров');
      expect(report['rooms'].single['lessons'], 4);
      expect(
        adapter.requests.single.queryParameters['from'],
        '2026-06-01T00:00:00.000Z',
      );
    });

    test('maps CRM reference data to legacy keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/branches',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'branch-a',
                'name': 'Центр',
                'address': 'Москва',
                'createdAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/rooms',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'room-a',
                'branchId': 'branch-a',
                'branchName': 'Центр',
                'name': '101',
                'capacity': 4,
                'createdAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/groups',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'group-a',
                'teacherId': 'teacher-a',
                'branchId': 'branch-a',
                'roomId': 'room-a',
                'name': 'Гитара',
                'pricePerLesson': 2500,
                'teacherName': 'Иван Петров',
                'branchName': 'Центр',
                'roomName': '101',
                'createdAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final branches = await service.listBranches();
      final rooms = await service.listRooms(branchId: 'branch-a');
      final groups = await service.listGroups(branchId: 'branch-a');

      expect(branches.single['created_at'], '2026-06-12T00:00:00.000Z');
      expect(rooms.single['branch_id'], 'branch-a');
      expect(rooms.single['branches']['name'], 'Центр');
      expect(groups.single['price_per_lesson'], 2500);
      expect(groups.single['branches']['name'], 'Центр');
      expect(adapter.requests[1].queryParameters['branchId'], 'branch-a');
      expect(adapter.requests[2].queryParameters['branchId'], 'branch-a');
    });

    test('maps schedule matrix and room availability contracts', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/rooms/availability',
          statusCode: 200,
          body: {
            'dateFrom': '2026-06-15T00:00:00.000Z',
            'dateTo': '2026-06-16T00:00:00.000Z',
            'slotFrom': '2026-06-15T09:00:00.000Z',
            'slotTo': '2026-06-15T10:00:00.000Z',
            'items': [
              {
                'roomId': 'room-a',
                'branchId': 'branch-a',
                'branchName': 'Центр',
                'roomName': '101',
                'capacity': 4,
                'lessons': [
                  {'id': 'lesson-a', 'scheduledAt': '2026-06-15T09:00:00.000Z'},
                ],
                'isAvailable': false,
                'conflictTypes': ['room_overlap'],
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/schedule/matrix',
          statusCode: 200,
          body: {
            'from': '2026-06-15T00:00:00.000Z',
            'to': '2026-06-16T00:00:00.000Z',
            'groupBy': 'room',
            'items': [
              {
                'id': 'lesson-a',
                'studentId': 'student-a',
                'groupId': null,
                'leadId': null,
                'teacherId': 'teacher-a',
                'branchId': 'branch-a',
                'roomId': 'room-a',
                'scheduledAt': '2026-06-15T09:00:00.000Z',
                'durationMinutes': 60,
                'status': 'scheduled',
                'isTrial': true,
                'notes': null,
                'studentName': 'Анна Иванова',
                'teacherName': 'Иван Петров',
                'branchName': 'Центр',
                'roomName': '101',
                'groupName': null,
                'groupPricePerLesson': null,
                'conflictTypes': ['room_overlap'],
              },
            ],
            'groups': [
              {
                'key': 'room-a',
                'label': '101',
                'items': [
                  {
                    'id': 'lesson-a',
                    'roomId': 'room-a',
                    'roomName': '101',
                    'scheduledAt': '2026-06-15T09:00:00.000Z',
                    'durationMinutes': 60,
                    'status': 'scheduled',
                    'isTrial': true,
                    'conflictTypes': ['room_overlap'],
                  },
                ],
              },
            ],
            'conflicts': [
              {
                'type': 'room_overlap',
                'lessonId': 'lesson-a',
                'scheduledAt': '2026-06-15T09:00:00.000Z',
                'roomId': 'room-a',
                'teacherId': 'teacher-a',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final availability = await service.listRoomAvailability(
        branchId: 'branch-a',
        roomId: 'room-a',
        teacherId: 'teacher-a',
        date: '2026-06-15',
        from: '2026-06-15T09:00:00.000Z',
        to: '2026-06-15T10:00:00.000Z',
        durationMinutes: 60,
        limit: 20,
      );
      final matrix = await service.getScheduleMatrix(
        from: '2026-06-15T00:00:00.000Z',
        to: '2026-06-16T00:00:00.000Z',
        branchId: 'branch-a',
        roomId: 'room-a',
        teacherId: 'teacher-a',
        isTrial: true,
        groupBy: 'room',
        limit: 30,
      );

      expect(availability['items'].single['is_available'], false);
      expect(availability['items'].single['conflict_types'], ['room_overlap']);
      expect(matrix['items'].single['conflict_types'], ['room_overlap']);
      expect(matrix['groups'].single['label'], '101');
      expect(matrix['conflicts'].single['type'], 'room_overlap');
      expect(adapter.requests[0].queryParameters['durationMinutes'], 60);
      expect(adapter.requests[1].queryParameters['groupBy'], 'room');
      expect(adapter.requests[1].queryParameters['isTrial'], true);
    });

    test('maps teachers to client chat contacts through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/teachers',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'teacher-a',
                'status': 'active',
                'specialization': 'Фортепиано',
                'profileId': 'profile-teacher-a',
                'profileUserId': 'teacher-user-a',
                'firstName': 'Мария',
                'lastName': 'Петрова',
                'email': 'teacher@example.com',
                'phone': '+79991111111',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final teachers = await service.listTeachers(limit: 25);

      expect(teachers.single['profile_user_id'], 'teacher-user-a');
      expect(teachers.single['first_name'], 'Мария');
      expect(teachers.single['specialization'], 'Фортепиано');
      expect(adapter.requests.single.queryParameters['limit'], 25);
    });

    test(
      'maps Phase 07 staff teacher filters and activity log contracts',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/teachers',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'teacher-a',
                  'status': 'active',
                  'specialization': 'Вокал',
                  'customData': {
                    'disciplines': ['Вокал'],
                    'rating': 4.8,
                  },
                  'profileId': 'profile-teacher-a',
                  'profileUserId': 'teacher-user-a',
                  'appRole': 'teacher',
                  'isAppAccount': false,
                  'firstName': 'Мария',
                  'lastName': 'Петрова',
                  'email': 'teacher@example.com',
                  'phone': '+79991111111',
                  'branches': [
                    {'id': 'branch-a', 'name': 'Центр'},
                  ],
                  'studentsCount': 12,
                  'lessonsCount': 34,
                  'rating': 4.8,
                  'createdAt': '2026-06-15T00:00:00.000Z',
                },
              ],
            },
          ),
          _FakeResponse(
            path: '/crm/staff',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'staff-a',
                  'role': 'manager',
                  'position': 'Управляющий',
                  'status': 'working',
                  'customData': {'birthday': '1990-06-01'},
                  'profileId': 'profile-staff-a',
                  'profileUserId': 'staff-user-a',
                  'appRole': 'manager',
                  'isAppAccount': true,
                  'firstName': 'Ольга',
                  'lastName': 'Смирнова',
                  'email': 'staff@example.com',
                  'phone': '+79992222222',
                  'branches': [
                    {'id': 'branch-a', 'name': 'Центр'},
                  ],
                  'createdAt': '2026-06-15T00:00:00.000Z',
                },
              ],
            },
          ),
          _FakeResponse(
            path: '/crm/activity',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'audit-a',
                  'actorUserId': 'staff-user-a',
                  'actorName': 'Ольга Смирнова',
                  'actorEmail': 'staff@example.com',
                  'actorRole': 'manager',
                  'actorStaffRole': 'manager',
                  'actorPosition': 'Управляющий',
                  'actorBranches': [
                    {'id': 'branch-a', 'name': 'Центр'},
                  ],
                  'action': 'crm.student_updated',
                  'entityType': 'student',
                  'entityId': 'student-a',
                  'historyType': 'student',
                  'description': 'Обновлена карточка',
                  'branchId': 'branch-a',
                  'metadata': {'branchId': 'branch-a'},
                  'createdAt': '2026-06-15T00:00:00.000Z',
                },
              ],
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final teachers = await service.listTeachers(
          q: 'мария',
          status: 'active',
          branchId: 'branch-a',
          discipline: 'Вокал',
          level: 'Начальный',
          category: 'Взрослые',
          appRole: 'teacher',
          authorization: 'technical',
          ratingFrom: 4,
          ratingTo: 5,
          birthdayMonth: 6,
          limit: 20,
        );
        final staff = await service.listStaff(
          q: 'ольга',
          branchId: 'branch-a',
          role: 'manager',
          status: 'working',
          appRole: 'manager',
          authorization: 'app',
          birthdayMonth: 6,
          limit: 15,
        );
        final activity = await service.listActivityLog(
          q: 'карточка',
          actorUserId: 'staff-user-a',
          entityType: 'student',
          entityId: 'student-a',
          branchId: 'branch-a',
          role: 'manager',
          historyType: 'student',
          from: '2026-06-01T00:00:00.000Z',
          to: '2026-07-01T00:00:00.000Z',
          limit: 25,
        );

        expect(teachers.single['students_count'], 12);
        expect(teachers.single['branches'].single['name'], 'Центр');
        expect(staff.single['custom_data']['birthday'], '1990-06-01');
        expect(activity.single['description'], 'Обновлена карточка');
        expect(adapter.requests[0].queryParameters['ratingFrom'], 4);
        expect(
          adapter.requests[0].queryParameters['authorization'],
          'technical',
        );
        expect(adapter.requests[1].queryParameters['appRole'], 'manager');
        expect(adapter.requests[2].queryParameters['historyType'], 'student');
      },
    );

    test('creates groups and manages group students through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/groups',
          statusCode: 201,
          body: {
            'id': 'group-a',
            'teacherId': 'teacher-a',
            'branchId': 'branch-a',
            'roomId': 'room-a',
            'name': 'Фортепиано',
            'pricePerLesson': 3000,
            'teacherName': 'Мария Петрова',
            'branchName': 'Центр',
            'roomName': '101',
            'createdAt': '2026-06-13T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/groups/group-a/students',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'student-a',
                'leadId': null,
                'status': 'active',
                'customData': {},
                'profileId': 'profile-a',
                'profileUserId': 'client-a',
                'firstName': 'Анна',
                'lastName': 'Иванова',
                'email': 'anna@example.com',
                'phone': null,
                'createdAt': '2026-06-13T00:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/groups/group-a/students',
          statusCode: 200,
          body: {'success': true},
        ),
        _FakeResponse(
          path: '/crm/groups/group-a/students/student-a',
          statusCode: 200,
          body: {'success': true},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final group = await service.createGroup(
        name: 'Фортепиано',
        teacherId: 'teacher-a',
        branchId: 'branch-a',
        roomId: 'room-a',
        pricePerLesson: 3000,
      );
      final students = await service.listGroupStudents('group-a', limit: 10);
      await service.addGroupStudent(groupId: 'group-a', studentId: 'student-a');
      await service.removeGroupStudent(
        groupId: 'group-a',
        studentId: 'student-a',
      );

      expect(group['name'], 'Фортепиано');
      expect(group['price_per_lesson'], 3000);
      expect(students.single['first_name'], 'Анна');
      expect(adapter.requests[0].body['teacherId'], 'teacher-a');
      expect(adapter.requests[1].queryParameters['limit'], 10);
      expect(adapter.requests[2].body['studentId'], 'student-a');
    });

    test('gets updates students and creates comments through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/students/student-a',
          statusCode: 200,
          body: {
            'id': 'student-a',
            'leadId': null,
            'status': 'active',
            'customData': {'middleName': 'Сергеевна'},
            'profileId': 'profile-a',
            'profileUserId': 'client-a',
            'firstName': 'Анна',
            'lastName': 'Иванова',
            'email': 'anna@example.com',
            'phone': '+79990000000',
            'createdAt': '2026-06-12T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/students/student-a',
          statusCode: 200,
          body: {
            'id': 'student-a',
            'leadId': null,
            'status': 'active',
            'customData': {'middleName': 'Сергеевна', 'notes': 'Важно'},
            'profileId': 'profile-a',
            'profileUserId': 'client-a',
            'firstName': 'Анна',
            'lastName': 'Иванова',
            'email': 'anna@example.com',
            'phone': '+79990000000',
            'createdAt': '2026-06-12T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/comments',
          statusCode: 201,
          body: {
            'id': 'comment-a',
            'entityType': 'student',
            'entityId': 'student-a',
            'authorId': 'manager-a',
            'authorName': 'Мария Менеджер',
            'body': 'Позвонить родителю',
            'createdAt': '2026-06-12T00:00:00.000Z',
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final student = await service.getStudent('student-a');
      final updated = await service.updateStudent(
        'student-a',
        firstName: 'Анна',
        lastName: 'Иванова',
        phone: '+79990000000',
        email: 'anna@example.com',
        customDataPatch: {'middleName': 'Сергеевна', 'notes': 'Важно'},
      );
      final comment = await service.createComment(
        entityType: 'student',
        entityId: 'student-a',
        body: 'Позвонить родителю',
      );

      expect(student['first_name'], 'Анна');
      expect(updated['custom_data']['notes'], 'Важно');
      expect(comment['content'], 'Позвонить родителю');
      expect(adapter.requests[1].body['firstName'], 'Анна');
      expect(adapter.requests[1].body['customDataPatch']['notes'], 'Важно');
      expect(adapter.requests[2].body['entityType'], 'student');
      expect(adapter.requests[2].body['entityId'], 'student-a');
      expect(adapter.requests[2].body['progress'], false);
    });

    test(
      'maps student search card and duplicate candidate contracts',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/students/search',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'student-a',
                  'leadId': 'lead-a',
                  'status': 'active',
                  'customData': {'discipline': 'Вокал'},
                  'profileId': 'profile-a',
                  'profileUserId': 'technical-user-a',
                  'firstName': 'Анна',
                  'lastName': 'Иванова',
                  'email': 'anna@example.com',
                  'phone': '+79990000000',
                  'createdAt': '2026-06-12T00:00:00.000Z',
                  'branchId': 'branch-a',
                  'branchName': 'Центр',
                  'groupsCount': 2,
                  'openTasksCount': 1,
                  'lessonsCount': 8,
                  'paymentsTotal': 12000,
                  'linkedUserId': 'client-a',
                  'linkedUserEmail': 'client@example.com',
                  'isAppAccount': true,
                },
              ],
              'totalCount': 1,
            },
          ),
          _FakeResponse(
            path: '/crm/students/student-a/card',
            statusCode: 200,
            body: {
              'student': {
                'id': 'student-a',
                'leadId': 'lead-a',
                'status': 'active',
                'customData': {},
                'profileId': 'profile-a',
                'profileUserId': 'client-a',
                'firstName': 'Анна',
                'lastName': 'Иванова',
                'email': 'anna@example.com',
                'phone': '+79990000000',
                'createdAt': '2026-06-12T00:00:00.000Z',
              },
              'groups': [
                {
                  'id': 'group-a',
                  'teacherId': null,
                  'branchId': 'branch-a',
                  'roomId': null,
                  'name': 'Вокал',
                  'pricePerLesson': 3000,
                  'teacherName': null,
                  'branchName': 'Центр',
                  'roomName': null,
                  'createdAt': '2026-06-12T00:00:00.000Z',
                },
              ],
              'lessons': [],
              'payments': [],
              'tasks': [],
              'comments': [],
              'expectedPayments': [],
              'balance': {
                'studentId': 'student-a',
                'balance': -5000,
                'totalPaid': 10000,
                'totalCost': 15000,
                'updatedAt': '2026-06-12T00:00:00.000Z',
                'student': {'firstName': 'Анна', 'lastName': 'Иванова'},
              },
              'links': [
                {
                  'id': 'link-a',
                  'userId': 'client-a',
                  'email': 'client@example.com',
                  'phone': '+79990000000',
                  'linkSource': 'manual_phone',
                  'confirmedAt': '2026-06-12T00:00:00.000Z',
                  'createdAt': '2026-06-12T00:00:00.000Z',
                },
              ],
              'timeline': [
                {
                  'id': 'payment-a',
                  'type': 'payment',
                  'title': 'Платеж',
                  'body': '10000 RUB',
                  'status': null,
                  'occurredAt': '2026-06-12T00:00:00.000Z',
                },
              ],
            },
          ),
          _FakeResponse(
            path: '/crm/duplicates',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'duplicate-a',
                  'entityTypeA': 'lead',
                  'entityIdA': 'lead-a',
                  'entityTypeB': 'student',
                  'entityIdB': 'student-a',
                  'matchType': 'lead_student_phone',
                  'matchValue': '+79990000000',
                  'confidence': 0.95,
                  'source': 'computed',
                  'status': 'pending',
                  'createdAt': '2026-06-12T00:00:00.000Z',
                  'updatedAt': '2026-06-12T00:00:00.000Z',
                  'entityA': {'name': 'Анна Лид'},
                  'entityB': {'name': 'Анна Иванова'},
                },
              ],
            },
          ),
          _FakeResponse(
            path: '/crm/duplicates/duplicate-a',
            statusCode: 200,
            body: {
              'id': 'duplicate-a',
              'entityTypeA': 'lead',
              'entityIdA': 'lead-a',
              'entityTypeB': 'student',
              'entityIdB': 'student-a',
              'matchType': 'lead_student_phone',
              'matchValue': '+79990000000',
              'confidence': 0.95,
              'source': 'computed',
              'status': 'attached',
              'decisionNotes': 'Та же семья',
              'createdAt': '2026-06-12T00:00:00.000Z',
              'updatedAt': '2026-06-12T00:00:00.000Z',
              'entityA': {'name': 'Анна Лид'},
              'entityB': {'name': 'Анна Иванова'},
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final search = await service.searchStudents(
          q: 'анна',
          branchId: 'branch-a',
          linkedUser: true,
        );
        final card = await service.getStudentCard('student-a');
        final duplicates = await service.listDuplicateCandidates(
          leadId: 'lead-a',
          limit: 10,
        );
        final decision = await service.decideDuplicateCandidate(
          'duplicate-a',
          status: 'attached',
          notes: 'Та же семья',
        );

        final student =
            (search['items'] as List).single as Map<String, dynamic>;
        expect(search['total_count'], 1);
        expect(student['branch_name'], 'Центр');
        expect(student['linked_user_id'], 'client-a');
        expect((card['groups'] as List).single['name'], 'Вокал');
        expect(card['balance']['balance'], -5000);
        expect((card['links'] as List).single['link_source'], 'manual_phone');
        expect(duplicates.single['entity_a']['name'], 'Анна Лид');
        expect(decision['status'], 'attached');
        expect(adapter.requests[0].queryParameters['linkedUser'], true);
        expect(adapter.requests[2].queryParameters['leadId'], 'lead-a');
        expect(adapter.requests[3].body['notes'], 'Та же семья');
      },
    );

    test('creates students teachers and staff through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/students',
          statusCode: 201,
          body: {
            'id': 'student-a',
            'leadId': null,
            'status': 'active',
            'customData': {},
            'profileId': 'profile-a',
            'profileUserId': 'client-a',
            'firstName': 'Анна',
            'lastName': 'Иванова',
            'email': 'anna@example.com',
            'phone': '+79990000000',
            'createdAt': '2026-06-13T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/teachers',
          statusCode: 201,
          body: {
            'id': 'teacher-a',
            'status': 'active',
            'specialization': 'Вокал',
            'profileId': 'profile-b',
            'profileUserId': 'teacher-a',
            'firstName': 'Мария',
            'lastName': 'Петрова',
            'email': 'teacher@example.com',
            'phone': '+79991111111',
          },
        ),
        _FakeResponse(
          path: '/crm/teachers/teacher-a',
          statusCode: 200,
          body: {
            'id': 'teacher-a',
            'status': 'active',
            'specialization': 'Фортепиано',
            'profileId': 'profile-b',
            'profileUserId': 'teacher-a',
            'firstName': 'Мария',
            'lastName': 'Петрова',
            'email': 'teacher@example.com',
            'phone': '+79991111111',
          },
        ),
        _FakeResponse(
          path: '/crm/staff',
          statusCode: 201,
          body: {
            'id': 'profile-c',
            'userId': 'staff-a',
            'email': 'staff@example.com',
            'role': 'manager',
            'firstName': 'Ольга',
            'lastName': 'Смирнова',
            'phone': '+79992222222',
          },
        ),
        _FakeResponse(
          path: '/crm/staff/staff-a',
          statusCode: 200,
          body: {
            'id': 'staff-a',
            'role': 'manager',
            'position': 'Операционный управляющий',
            'status': 'working',
            'customData': {'birthday': '1990-06-01'},
            'profileId': 'profile-c',
            'profileUserId': 'staff-a',
            'appRole': 'manager',
            'isAppAccount': true,
            'firstName': 'Ольга',
            'lastName': 'Смирнова',
            'email': 'staff@example.com',
            'phone': '+79992222222',
            'branches': [
              {'id': 'branch-a', 'name': 'Центр'},
            ],
            'createdAt': '2026-06-13T00:00:00.000Z',
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final student = await service.createStudent(
        firstName: 'Анна',
        lastName: 'Иванова',
        email: 'anna@example.com',
        phone: '+79990000000',
      );
      final teacher = await service.createTeacher(
        firstName: 'Мария',
        lastName: 'Петрова',
        email: 'teacher@example.com',
        phone: '+79991111111',
        specialization: 'Вокал',
      );
      final updatedTeacher = await service.updateTeacher(
        'teacher-a',
        firstName: 'Мария',
        lastName: 'Петрова',
        email: 'teacher@example.com',
        phone: '+79991111111',
        specialization: 'Фортепиано',
      );
      final staff = await service.createStaff(
        firstName: 'Ольга',
        lastName: 'Смирнова',
        email: 'staff@example.com',
        phone: '+79992222222',
        role: 'manager',
      );
      final updatedStaff = await service.updateStaff(
        'staff-a',
        firstName: 'Ольга',
        lastName: 'Смирнова',
        email: 'staff@example.com',
        phone: '+79992222222',
        role: 'manager',
        position: 'Операционный управляющий',
        status: 'working',
        customDataPatch: {'birthday': '1990-06-01'},
      );

      expect(student['first_name'], 'Анна');
      expect(teacher['specialization'], 'Вокал');
      expect(updatedTeacher['specialization'], 'Фортепиано');
      expect(staff['role'], 'manager');
      expect(updatedStaff['position'], 'Операционный управляющий');
      expect(updatedStaff['custom_data']['birthday'], '1990-06-01');
      expect(adapter.requests[0].body['firstName'], 'Анна');
      expect(adapter.requests[1].body['specialization'], 'Вокал');
      expect(adapter.requests[2].body['specialization'], 'Фортепиано');
      expect(adapter.requests[3].body['role'], 'manager');
      expect(adapter.requests[4].body['position'], 'Операционный управляющий');
      expect(
        adapter.requests[4].body['customDataPatch']['birthday'],
        '1990-06-01',
      );
    });

    test('creates student from lead with conversion payload', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/students',
          statusCode: 201,
          body: {
            'id': 'student-a',
            'leadId': 'lead-a',
            'status': 'active',
            'customData': {'discipline': 'Вокал', 'sourceLeadId': 'lead-a'},
            'profileId': 'profile-a',
            'profileUserId': 'client-a',
            'firstName': 'Анна',
            'lastName': 'Иванова',
            'email': 'anna@example.com',
            'phone': '+79990000000',
            'createdAt': '2026-06-13T00:00:00.000Z',
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final student = await service.createStudent(
        firstName: 'Анна',
        lastName: 'Иванова',
        email: 'anna@example.com',
        phone: '+79990000000',
        leadId: 'lead-a',
        customDataPatch: {'discipline': 'Вокал', 'sourceLeadId': 'lead-a'},
      );

      expect(student['lead_id'], 'lead-a');
      expect(student['custom_data']['sourceLeadId'], 'lead-a');
      expect(adapter.requests.single.body['leadId'], 'lead-a');
      expect(
        adapter.requests.single.body['customDataPatch']['discipline'],
        'Вокал',
      );
    });

    test('returns student to lead through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/students/student-a/return-to-lead',
          statusCode: 201,
          body: {
            'success': true,
            'studentId': 'student-a',
            'leadId': 'lead-a',
            'createdLead': false,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final result = await service.returnStudentToLead('student-a');

      expect(result['leadId'], 'lead-a');
      expect(result['createdLead'], false);
      expect(adapter.requests.single.body, isEmpty);
    });

    test('queues student invite through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/students/student-a/invite',
          statusCode: 201,
          body: {
            'studentId': 'student-a',
            'email': 'anna@example.com',
            'status': 'queued',
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final invite = await service.inviteStudent('student-a');

      expect(invite['student_id'], 'student-a');
      expect(invite['email'], 'anna@example.com');
      expect(invite['status'], 'queued');
      expect(adapter.requests.single.body, isEmpty);
    });

    test('lists student groups and expected payments through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/students/student-a/groups',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'group-a',
                'teacherId': 'teacher-a',
                'branchId': 'branch-a',
                'roomId': 'room-a',
                'name': 'Гитара A',
                'pricePerLesson': 1500,
                'teacherName': 'Иван Петров',
                'branchName': 'Центр',
                'roomName': '101',
                'createdAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/expected-payments',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'expected-a',
                'studentId': 'student-a',
                'studentName': 'Анна Иванова',
                'amount': 5000,
                'dueDate': '2026-06-30',
                'status': 'pending',
                'description': 'Абонемент за июнь',
                'createdAt': '2026-06-12T00:00:00.000Z',
                'updatedAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final groups = await service.listStudentGroups('student-a', limit: 10);
      final expectedPayments = await service.listExpectedPayments(
        studentId: 'student-a',
        limit: 10,
      );

      expect(groups.single['teachers']['first_name'], 'Иван');
      expect(groups.single['teachers']['last_name'], 'Петров');
      expect(expectedPayments.single['due_date'], '2026-06-30');
      expect(expectedPayments.single['description'], 'Абонемент за июнь');
      expect(expectedPayments.single['students']['first_name'], 'Анна');
      expect(adapter.requests[0].queryParameters['limit'], 10);
      expect(adapter.requests[1].queryParameters['studentId'], 'student-a');
      expect(adapter.requests[1].queryParameters['limit'], 10);
    });

    test('creates updates and deletes rooms through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/rooms',
          statusCode: 201,
          body: {
            'id': 'room-b',
            'branchId': 'branch-a',
            'branchName': 'Центр',
            'name': '102',
            'capacity': 6,
            'createdAt': '2026-06-12T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/rooms/room-b',
          statusCode: 200,
          body: {
            'id': 'room-b',
            'branchId': 'branch-a',
            'branchName': 'Центр',
            'name': '103',
            'capacity': 8,
            'createdAt': '2026-06-12T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/rooms/room-b',
          statusCode: 200,
          body: {'success': true},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final created = await service.createRoom(
        name: '102',
        branchId: 'branch-a',
        capacity: 6,
      );
      final updated = await service.updateRoom(
        'room-b',
        name: '103',
        branchId: 'branch-a',
        capacity: 8,
      );
      await service.deleteRoom('room-b');

      expect(created['branch_id'], 'branch-a');
      expect(created['branches']['name'], 'Центр');
      expect(updated['name'], '103');
      expect(adapter.requests[0].body['name'], '102');
      expect(adapter.requests[0].body['branchId'], 'branch-a');
      expect(adapter.requests[0].body['capacity'], 6);
      expect(adapter.requests[1].body['name'], '103');
      expect(adapter.requests[1].body['capacity'], 8);
    });

    test('maps leads and passes trial lesson filter', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'lead-a',
                'statusId': 'status-a',
                'statusName': 'Новый',
                'firstName': 'Анна',
                'lastName': 'Иванова',
                'phone': '+79990000000',
                'email': 'anna@example.com',
                'source': 'site',
                'notes': null,
                'assignedTo': null,
                'customData': {
                  'discipline': 'Вокал',
                  'hollihopId': 'HH-LEAD-42',
                },
                'createdBy': 'manager-a',
                'createdAt': '2026-06-12T00:00:00.000Z',
                'updatedAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/lessons',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'lesson-a',
                'studentId': 'student-a',
                'groupId': null,
                'leadId': null,
                'teacherId': 'teacher-a',
                'branchId': null,
                'roomId': null,
                'scheduledAt': '2026-06-12T12:00:00.000Z',
                'durationMinutes': 60,
                'status': 'completed',
                'isTrial': true,
                'notes': null,
                'studentName': 'Анна Иванова',
                'teacherName': 'Иван Петров',
                'branchName': null,
                'roomName': null,
                'groupName': null,
                'groupPricePerLesson': null,
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final leads = await service.listLeads(limit: 10);
      final lessons = await service.listLessons(isTrial: true, limit: 10);

      expect(leads.single['status'], 'status-a');
      expect(leads.single['status_label'], 'Новый');
      expect(leads.single['custom_data']['discipline'], 'Вокал');
      expect(leads.single['hollihop_id'], 'HH-LEAD-42');
      expect(leads.single['created_at'], '2026-06-12T00:00:00.000Z');
      expect(lessons.single['is_trial'], true);
      expect(adapter.requests[0].queryParameters['limit'], 10);
      expect(adapter.requests[1].queryParameters['isTrial'], true);
    });

    test('maps lead board and lead card aggregate contracts', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads/board',
          statusCode: 200,
          body: {
            'columns': [
              {
                'id': 'status-a',
                'name': 'Новый',
                'color': '#C5A059',
                'sortOrder': 1,
                'createdAt': '2026-06-12T00:00:00.000Z',
                'totalCount': 3,
                'items': [
                  {
                    'id': 'lead-a',
                    'statusId': 'status-a',
                    'statusName': 'Новый',
                    'statusColor': '#C5A059',
                    'statusSortOrder': 1,
                    'firstName': 'Анна',
                    'lastName': 'Иванова',
                    'phone': '+79990000000',
                    'email': 'anna@example.com',
                    'source': 'site',
                    'notes': null,
                    'assignedTo': 'manager-a',
                    'assignedName': 'Мария Менеджер',
                    'branchId': 'branch-a',
                    'branchName': 'Центр',
                    'linkedStudentId': 'student-a',
                    'openTasksCount': 2,
                    'commentsCount': 4,
                    'trialLessonsCount': 1,
                    'customData': {
                      'discipline': 'Вокал',
                      'hollihopId': 'HH-LEAD-42',
                    },
                    'createdBy': 'manager-a',
                    'createdAt': '2026-06-12T00:00:00.000Z',
                    'updatedAt': '2026-06-12T00:00:00.000Z',
                  },
                ],
              },
            ],
            'totalCount': 3,
            'nextCursor': 'cursor-a',
          },
        ),
        _FakeResponse(
          path: '/crm/leads/lead-a/card',
          statusCode: 200,
          body: {
            'lead': {
              'id': 'lead-a',
              'statusId': 'status-a',
              'statusName': 'Новый',
              'firstName': 'Анна',
              'lastName': 'Иванова',
              'phone': '+79990000000',
              'email': 'anna@example.com',
              'source': 'site',
              'customData': {'discipline': 'Вокал'},
              'createdAt': '2026-06-12T00:00:00.000Z',
              'updatedAt': '2026-06-12T00:00:00.000Z',
            },
            'linkedStudents': [
              {
                'id': 'student-a',
                'leadId': 'lead-a',
                'status': 'active',
                'customData': {},
                'profileId': 'profile-a',
                'profileUserId': 'client-a',
                'firstName': 'Анна',
                'lastName': 'Иванова',
                'email': 'anna@example.com',
                'phone': '+79990000000',
                'createdAt': '2026-06-13T00:00:00.000Z',
              },
            ],
            'otherLeads': [],
            'comments': [
              {
                'id': 'comment-a',
                'entityType': 'lead',
                'entityId': 'lead-a',
                'authorId': 'manager-a',
                'authorName': 'Мария Менеджер',
                'body': 'Позвонить',
                'createdAt': '2026-06-12T10:00:00.000Z',
              },
            ],
            'tasks': [
              {
                'id': 'task-a',
                'entityType': 'lead',
                'entityId': 'lead-a',
                'assignedTo': 'manager-a',
                'assignedName': 'Мария Менеджер',
                'entityName': 'Анна Иванова',
                'title': 'Перезвонить',
                'description': null,
                'status': 'open',
                'createdBy': 'manager-a',
                'createdAt': '2026-06-12T09:00:00.000Z',
              },
            ],
            'trials': [
              {
                'id': 'lesson-a',
                'studentId': null,
                'groupId': null,
                'leadId': 'lead-a',
                'teacherId': 'teacher-a',
                'branchId': 'branch-a',
                'roomId': 'room-a',
                'scheduledAt': '2026-06-15T09:00:00.000Z',
                'durationMinutes': 60,
                'status': 'scheduled',
                'isTrial': true,
                'notes': null,
                'studentName': null,
                'teacherName': 'Иван Петров',
                'branchName': 'Центр',
                'roomName': '101',
                'groupName': null,
                'groupPricePerLesson': null,
              },
            ],
            'timeline': [
              {
                'id': 'task-a',
                'type': 'task',
                'title': 'Перезвонить',
                'body': null,
                'status': 'open',
                'occurredAt': '2026-06-12T09:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/leads/board',
          statusCode: 200,
          body: {
            'columns': [
              {
                'id': 'status-a',
                'key': 'status-a',
                'name': 'Новый',
                'color': '#C5A059',
                'sortOrder': 1,
                'createdAt': '2026-06-12T00:00:00.000Z',
                'totalCount': 3,
                'items': [
                  {
                    'id': 'lead-b',
                    'statusId': 'status-a',
                    'statusName': 'Новый',
                    'statusColor': '#C5A059',
                    'statusSortOrder': 1,
                    'firstName': 'Борис',
                    'lastName': 'Сидоров',
                    'phone': '+79991111111',
                    'email': null,
                    'source': 'site',
                    'notes': null,
                    'assignedTo': null,
                    'assignedName': null,
                    'branchId': null,
                    'branchName': null,
                    'linkedStudentId': null,
                    'openTasksCount': 0,
                    'commentsCount': 0,
                    'trialLessonsCount': 0,
                    'customData': {},
                    'createdBy': 'manager-a',
                    'createdAt': '2026-06-11T00:00:00.000Z',
                    'updatedAt': '2026-06-11T00:00:00.000Z',
                  },
                ],
              },
            ],
            'totalCount': 3,
            'nextCursor': null,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final board = await service.listLeadBoard(
        q: 'анна',
        branchId: 'branch-a',
        discipline: 'Вокал',
        quick: 'active',
        openTasks: true,
      );
      final card = await service.getLeadCard('lead-a');
      final nextPage = await service.listLeadBoard(cursor: 'cursor-a');

      final column = (board['columns'] as List).single as Map<String, dynamic>;
      final lead = (column['items'] as List).single as Map<String, dynamic>;
      expect(board['total_count'], 3);
      expect(column['label'], 'Новый');
      expect(column['total_count'], 3);
      expect(lead['assigned_name'], 'Мария Менеджер');
      expect(lead['branch_name'], 'Центр');
      expect(lead['open_tasks_count'], 2);
      expect(card['lead']['name'], 'Анна');
      expect((card['linked_students'] as List).single['first_name'], 'Анна');
      expect((card['tasks'] as List).single['title'], 'Перезвонить');
      expect((card['trials'] as List).single['teacher_name'], 'Иван Петров');
      expect((card['timeline'] as List).single['occurred_at'], isNotNull);
      expect(
        (((nextPage['columns'] as List).single as Map<String, dynamic>)['items']
                as List)
            .single['name'],
        'Борис',
      );
      expect(board['next_cursor'], 'cursor-a');
      expect(adapter.requests[0].queryParameters['q'], 'анна');
      expect(adapter.requests[0].queryParameters['openTasks'], true);
      expect(adapter.requests[2].queryParameters['cursor'], 'cursor-a');
    });

    test('manages leads and lead statuses through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads',
          statusCode: 201,
          body: {
            'id': 'lead-a',
            'statusId': 'status-a',
            'statusName': 'Новый',
            'firstName': 'Петр',
            'lastName': null,
            'phone': '+79990000000',
            'email': null,
            'source': 'site',
            'notes': null,
            'assignedTo': null,
            'customData': {'discipline': 'Гитара'},
            'createdBy': 'manager-a',
            'createdAt': '2026-06-12T00:00:00.000Z',
            'updatedAt': '2026-06-12T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/leads/lead-a',
          statusCode: 200,
          body: {
            'id': 'lead-a',
            'statusId': 'status-b',
            'statusName': 'Переговоры',
            'firstName': 'Петр',
            'lastName': 'Сидоров',
            'phone': '+79990000000',
            'email': null,
            'source': 'site',
            'notes': 'Важно',
            'assignedTo': null,
            'customData': {'level': 'beginner'},
            'createdBy': 'manager-a',
            'createdAt': '2026-06-12T00:00:00.000Z',
            'updatedAt': '2026-06-12T00:10:00.000Z',
          },
        ),
        _FakeResponse(path: '/crm/leads/lead-a', statusCode: 200, body: {}),
        _FakeResponse(
          path: '/crm/lead-statuses',
          statusCode: 201,
          body: {
            'id': 'status-c',
            'name': 'Думает',
            'color': '#8B5CF6',
            'sortOrder': 3,
            'createdAt': '2026-06-12T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/lead-statuses/status-c',
          statusCode: 200,
          body: {},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final created = await service.createLead(
        firstName: 'Петр',
        phone: '+79990000000',
        source: 'site',
        statusId: 'status-a',
        customDataPatch: {'discipline': 'Гитара'},
      );
      final updated = await service.updateLead(
        'lead-a',
        lastName: 'Сидоров',
        statusId: 'status-b',
        notes: 'Важно',
        customDataPatch: {'level': 'beginner'},
      );
      await service.deleteLead('lead-a');
      final status = await service.createLeadStatus(
        key: 'thinking',
        label: 'Думает',
        color: '#8B5CF6',
        sortOrder: 3,
      );
      await service.deleteLeadStatus('status-c');

      expect(created['name'], 'Петр');
      expect(created['status'], 'status-a');
      expect(updated['last_name'], 'Сидоров');
      expect(updated['custom_data']['level'], 'beginner');
      expect(status['key'], 'status-c');
      expect(status['label'], 'Думает');
      expect(
        adapter.requests[0].body['customDataPatch']['discipline'],
        'Гитара',
      );
      expect(adapter.requests[1].body['statusId'], 'status-b');
      expect(adapter.requests[3].body['label'], 'Думает');
    });

    test('creates lessons with branch and room ids', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/lessons',
          statusCode: 201,
          body: {
            'id': 'lesson-a',
            'studentId': 'student-a',
            'groupId': null,
            'leadId': null,
            'teacherId': 'teacher-a',
            'branchId': 'branch-a',
            'roomId': 'room-a',
            'scheduledAt': '2026-06-12T12:00:00.000Z',
            'durationMinutes': 60,
            'status': 'scheduled',
            'isTrial': false,
            'notes': null,
            'studentName': 'Анна Иванова',
            'teacherName': 'Иван Петров',
            'branchName': 'Центр',
            'roomName': '101',
            'groupName': null,
            'groupPricePerLesson': null,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final lesson = await service.createLesson(
        studentId: 'student-a',
        teacherId: 'teacher-a',
        branchId: 'branch-a',
        roomId: 'room-a',
        scheduledAt: '2026-06-12T12:00:00.000Z',
        durationMinutes: 60,
      );

      expect(adapter.requests.single.body['branchId'], 'branch-a');
      expect(adapter.requests.single.body['roomId'], 'room-a');
      expect(lesson['branch_id'], 'branch-a');
      expect(lesson['rooms']['name'], '101');
      expect(lesson['branches']['name'], 'Центр');
    });

    test('creates trial lessons for leads', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/lessons',
          statusCode: 201,
          body: {
            'id': 'lesson-lead-a',
            'studentId': null,
            'groupId': null,
            'leadId': 'lead-a',
            'teacherId': 'teacher-a',
            'branchId': null,
            'roomId': 'room-a',
            'scheduledAt': '2026-06-13T10:00:00.000Z',
            'durationMinutes': 60,
            'status': 'scheduled',
            'isTrial': true,
            'notes': 'Пробное занятие',
            'studentName': null,
            'teacherName': 'Иван Петров',
            'branchName': null,
            'roomName': '101',
            'groupName': null,
            'groupPricePerLesson': null,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final lesson = await service.createLesson(
        leadId: 'lead-a',
        teacherId: 'teacher-a',
        roomId: 'room-a',
        scheduledAt: '2026-06-13T10:00:00.000Z',
        isTrial: true,
        notes: 'Пробное занятие',
      );

      expect(adapter.requests.single.body['leadId'], 'lead-a');
      expect(adapter.requests.single.body['isTrial'], true);
      expect(lesson['lead_id'], 'lead-a');
      expect(lesson['is_trial'], true);
    });

    test('gets and saves lesson attendance through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/lessons/lesson-a/attendance',
          statusCode: 200,
          body: {
            'lessonId': 'lesson-a',
            'students': [
              {
                'studentId': 'student-a',
                'studentName': 'Анна Иванова',
                'status': 'present',
                'passReason': '',
              },
              {
                'studentId': 'student-b',
                'studentName': 'Олег Петров',
                'status': 'absent',
                'passReason': 'Болеет',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/lessons/lesson-a/attendance',
          statusCode: 200,
          body: {
            'lessonId': 'lesson-a',
            'students': [
              {
                'studentId': 'student-b',
                'studentName': 'Олег Петров',
                'status': 'absent',
                'passReason': 'Болеет',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final attendance = await service.getLessonAttendance('lesson-a');
      final saved = await service.saveLessonAttendance('lesson-a', [
        {
          'student_id': 'student-b',
          'is_present': false,
          'pass_reason': 'Болеет',
        },
      ]);

      expect(attendance['students'].first['name'], 'Анна Иванова');
      expect(attendance['participations'][1]['is_present'], false);
      expect(saved['participations'].single['pass_reason'], 'Болеет');
      expect(
        adapter.requests[1].body['items'].single['studentId'],
        'student-b',
      );
      expect(adapter.requests[1].body['items'].single['status'], 'absent');
      expect(adapter.requests[1].body['items'].single['passReason'], 'Болеет');
    });

    test('maps subscriptions to legacy keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/subscriptions',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'sub-a',
                'studentId': 'student-a',
                'lessonsTotal': 8,
                'lessonsUsed': 3,
                'startsAt': '2026-06-01',
                'expiresAt': '2026-07-01',
                'status': 'active',
                'createdAt': '2026-06-01T00:00:00.000Z',
                'updatedAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final subscriptions = await service.listSubscriptions(
        studentId: 'student-a',
        limit: 1,
      );

      expect(adapter.requests.single.queryParameters['studentId'], 'student-a');
      expect(adapter.requests.single.queryParameters['limit'], 1);
      expect(subscriptions.single['student_id'], 'student-a');
      expect(subscriptions.single['lessons_total'], 8);
      expect(subscriptions.single['valid_until'], '2026-07-01');
    });

    test('maps payments and creates payment payload', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/payments',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'payment-a',
                'studentId': 'student-a',
                'studentName': 'Анна Иванова',
                'amount': 5000,
                'currency': 'RUB',
                'paymentDate': '2026-06-12T12:00:00.000Z',
                'method': 'subscription',
                'externalId': null,
                'notes': 'Оплата абонемента',
                'createdBy': 'manager-a',
                'createdAt': '2026-06-12T12:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/payments',
          statusCode: 201,
          body: {
            'id': 'payment-b',
            'studentId': 'student-a',
            'studentName': 'Анна Иванова',
            'amount': 2500,
            'currency': 'RUB',
            'paymentDate': '2026-06-12T13:00:00.000Z',
            'method': 'other',
            'externalId': null,
            'notes': null,
            'createdBy': 'manager-a',
            'createdAt': '2026-06-12T13:00:00.000Z',
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final payments = await service.listPayments(
        from: '2026-06-01T00:00:00.000Z',
        limit: 10,
      );
      final created = await service.createPayment(
        studentId: 'student-a',
        amount: 2500,
        paymentDate: '2026-06-12T13:00:00.000Z',
        method: 'other',
      );

      expect(payments.single['students']['first_name'], 'Анна');
      expect(payments.single['type'], 'subscription');
      expect(payments.single['notes'], 'Оплата абонемента');
      expect(payments.single['description'], 'Оплата абонемента');
      expect(created['amount'], 2500);
      expect(
        adapter.requests[0].queryParameters['from'],
        '2026-06-01T00:00:00.000Z',
      );
      expect(adapter.requests[1].body['studentId'], 'student-a');
      expect(adapter.requests[1].body['method'], 'other');
    });

    test('maps tasks and creates task payload', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/tasks',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'task-a',
                'entityType': 'student',
                'entityId': 'student-a',
                'assignedTo': 'manager-a',
                'assignedName': 'Мария Менеджер',
                'entityName': 'Анна Иванова',
                'title': 'Позвонить',
                'description': null,
                'status': 'open',
                'dueAt': '2026-06-13T00:00:00.000Z',
                'createdBy': 'admin-a',
                'createdAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/tasks',
          statusCode: 201,
          body: {
            'id': 'task-b',
            'entityType': 'lead',
            'entityId': 'lead-a',
            'assignedTo': null,
            'assignedName': null,
            'entityName': 'Петр Лид',
            'title': 'Назначить пробный урок',
            'description': 'Позвонить сегодня',
            'status': 'open',
            'dueAt': null,
            'createdBy': 'admin-a',
            'createdAt': '2026-06-12T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/crm/tasks/task-a',
          statusCode: 200,
          body: {
            'id': 'task-a',
            'entityType': 'student',
            'entityId': 'student-a',
            'assignedTo': 'manager-b',
            'assignedName': 'Новый Менеджер',
            'entityName': 'Анна Иванова',
            'title': 'Позвонить',
            'description': null,
            'status': 'in_progress',
            'dueAt': '2026-06-13T00:00:00.000Z',
            'createdBy': 'admin-a',
            'createdAt': '2026-06-12T00:00:00.000Z',
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final tasks = await service.listTasks(status: 'open', limit: 15);
      final created = await service.createTask(
        entityType: 'lead',
        entityId: 'lead-a',
        title: 'Назначить пробный урок',
        description: 'Позвонить сегодня',
      );
      final updated = await service.updateTask(
        'task-a',
        assignedTo: 'manager-b',
        status: 'in_progress',
      );

      expect(tasks.single['due_date'], '2026-06-13T00:00:00.000Z');
      expect(tasks.single['entity_name'], 'Анна Иванова');
      expect(tasks.single['students']['first_name'], 'Анна');
      expect(created['leads']['name'], 'Петр Лид');
      expect(updated['assigned_to'], 'manager-b');
      expect(updated['assigned_name'], 'Новый Менеджер');
      expect(adapter.requests[0].queryParameters['status'], 'open');
      expect(adapter.requests[0].queryParameters['limit'], 15);
      expect(adapter.requests[1].body['entityType'], 'lead');
      expect(adapter.requests[1].body['entityId'], 'lead-a');
      expect(adapter.requests[1].body['status'], 'open');
      expect(adapter.requests[2].body['assignedTo'], 'manager-b');
      expect(adapter.requests[2].body['status'], 'in_progress');
    });

    test('maps task board filters and unified timeline', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/tasks',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'task-a',
                'entityType': 'lead',
                'entityId': 'lead-a',
                'assignedTo': 'manager-a',
                'assignedName': 'Мария Менеджер',
                'entityName': 'Анна Иванова',
                'title': 'Позвонить',
                'description': 'Приоритет высокий, WhatsApp',
                'status': 'open',
                'dueAt': '2026-06-13T00:00:00.000Z',
                'createdBy': 'admin-a',
                'creatorName': 'Ольга Админ',
                'branchId': 'branch-a',
                'branchName': 'Центр',
                'createdAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/timeline',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'payment-a',
                'type': 'payment',
                'title': 'Платеж',
                'body': 'Абонемент',
                'status': 'cash',
                'amount': 12000,
                'actorUserId': 'manager-a',
                'actorName': 'Мария Менеджер',
                'occurredAt': '2026-06-14T09:00:00.000Z',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final tasks = await service.listTasks(
        q: 'анна',
        entityType: 'lead',
        entityId: 'lead-a',
        assignedTo: 'manager-a',
        createdBy: 'admin-a',
        branchId: 'branch-a',
        status: 'open',
        priority: 'высокий',
        taskType: 'звонок',
        communicationMethod: 'WhatsApp',
        from: '2026-06-01T00:00:00.000Z',
        to: '2026-07-01T00:00:00.000Z',
        limit: 25,
      );
      final timeline = await service.listTimeline(
        entityType: 'student',
        entityId: 'student-a',
        from: '2026-06-01T00:00:00.000Z',
        to: '2026-07-01T00:00:00.000Z',
        includeAudit: true,
        limit: 40,
      );

      expect(tasks.single['creator_name'], 'Ольга Админ');
      expect(tasks.single['branch_name'], 'Центр');
      expect(timeline.single['amount'], 12000);
      expect(timeline.single['actor_name'], 'Мария Менеджер');
      expect(
        adapter.requests[0].queryParameters['communicationMethod'],
        'WhatsApp',
      );
      expect(adapter.requests[0].queryParameters['priority'], 'высокий');
      expect(adapter.requests[1].queryParameters['includeAudit'], true);
      expect(adapter.requests[1].queryParameters['limit'], 40);
    });

    test('maps student balances to debtor legacy shape', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/student-balances',
          statusCode: 200,
          body: {
            'items': [
              {
                'studentId': 'student-a',
                'balance': -3000,
                'totalPaid': 2000,
                'totalCost': 5000,
                'updatedAt': '2026-06-12T12:00:00.000Z',
                'student': {
                  'firstName': 'Анна',
                  'lastName': 'Иванова',
                  'phone': '+79990000000',
                },
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final balances = await service.listStudentBalances(
        debtOnly: true,
        limit: 20,
      );

      expect(balances.single['student_id'], 'student-a');
      expect(balances.single['balance'], -3000);
      expect(balances.single['total_paid'], 2000);
      expect(balances.single['students']['profiles']['first_name'], 'Анна');
      expect(adapter.requests.single.queryParameters['debtOnly'], true);
      expect(adapter.requests.single.queryParameters['limit'], 20);
    });

    test('maps progress comments to legacy keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/comments',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'comment-a',
                'entityType': 'student',
                'entityId': 'student-a',
                'authorId': 'teacher-a',
                'authorName': 'Иван Петров',
                'body': '[PROGRESS] Хорошая динамика',
                'createdAt': '2026-06-12T00:00:00.000Z',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final comments = await service.listProgressNotes(studentId: 'student-a');

      expect(adapter.requests.single.queryParameters['entityType'], 'student');
      expect(adapter.requests.single.queryParameters['entityId'], 'student-a');
      expect(adapter.requests.single.queryParameters['progressOnly'], true);
      expect(comments.single['content'], '[PROGRESS] Хорошая динамика');
      expect(comments.single['profiles']['first_name'], 'Иван');
      expect(comments.single['profiles']['last_name'], 'Петров');
    });

    // ── Analytics endpoints ───────────────────────────────────────────────

    test('getAnalyticsFunnel requests /analytics/funnel and maps stages',
        () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/analytics/funnel',
          statusCode: 200,
          body: {
            'from': '2026-01-01',
            'to': '2026-04-01',
            'stages': [
              {
                'statusId': 's1',
                'name': 'Новый',
                'sortOrder': 0,
                'leadsEntered': 100,
                'ratioToPrevStage': null,
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final result = await service.getAnalyticsFunnel(
        from: '2026-01-01',
        to: '2026-04-01',
      );

      expect(adapter.requests.single.queryParameters['from'], '2026-01-01');
      expect(adapter.requests.single.queryParameters['to'], '2026-04-01');
      expect((result['stages'] as List).first['name'], 'Новый');
      expect((result['stages'] as List).first['leadsEntered'], 100);
    });

    test('getAnalyticsDebts requests /analytics/debts and maps buckets',
        () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/analytics/debts',
          statusCode: 200,
          body: {
            'buckets': [
              {'bucket': '0-7', 'students': 5, 'amount': 50000},
            ],
            'bucketStudentSum': 5,
            'distinctStudents': 5,
            'totalAmount': 50000,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final r = await service.getAnalyticsDebts();

      expect(adapter.requests.single.queryParameters, isEmpty);
      expect((r['buckets'] as List).first['bucket'], '0-7');
      expect(r['totalAmount'], 50000);
    });

    test(
        'getAnalyticsBranches requests /analytics/branches with date params',
        () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/analytics/branches',
          statusCode: 200,
          body: {
            'from': '2026-01-01',
            'to': '2026-04-01',
            'branches': [
              {'branchId': 'b1', 'branchName': 'Центр', 'newLeads': 20},
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final r = await service.getAnalyticsBranches(
        from: '2026-01-01',
        to: '2026-04-01',
      );

      expect(adapter.requests.single.queryParameters['from'], '2026-01-01');
      expect((r['branches'] as List).first['branchName'], 'Центр');
    });

    test(
        'getAnalyticsWeeklyReport requests /analytics/weekly-report',
        () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/analytics/weekly-report',
          statusCode: 200,
          body: {
            'weekStart': '2026-06-10',
            'weekEnd': '2026-06-16',
            'newLeads': 12,
            'tasks': 8,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final r = await service.getAnalyticsWeeklyReport(branchId: 'b1');

      expect(
        adapter.requests.single.queryParameters['branchId'],
        'b1',
      );
      expect(r['newLeads'], 12);
    });

    test('getAnalyticsLossReasons requests /analytics/loss-reasons', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/analytics/loss-reasons',
          statusCode: 200,
          body: {
            'reasons': [
              {'reason': 'Дорого', 'count': 10},
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final r = await service.getAnalyticsLossReasons(from: '2026-01-01');

      expect(adapter.requests.single.queryParameters['from'], '2026-01-01');
      expect((r['reasons'] as List).first['reason'], 'Дорого');
    });

    test('getAnalyticsForecast requests /analytics/forecast', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/analytics/forecast',
          statusCode: 200,
          body: {
            'forecastAmount': 120000,
            'confirmedAmount': 80000,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final r = await service.getAnalyticsForecast(branchId: 'b1');

      expect(adapter.requests.single.queryParameters['branchId'], 'b1');
      expect(r['forecastAmount'], 120000);
    });

    test('getAnalyticsChurn requests /analytics/churn-risk', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/analytics/churn-risk',
          statusCode: 200,
          body: {
            'atRisk': 7,
            'students': [
              {'studentId': 's1', 'daysSinceLastLesson': 30},
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final r = await service.getAnalyticsChurn(inactiveDays: 21);

      expect(adapter.requests.single.queryParameters['inactiveDays'], 21);
      expect(r['atRisk'], 7);
    });

    test('getAnalyticsChatSla requests /analytics/chats/sla', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/analytics/chats/sla',
          statusCode: 200,
          body: {
            'avgResponseMs': 45000,
            'withinSlaPercent': 92.5,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final r = await service.getAnalyticsChatSla(
        from: '2026-06-01',
        to: '2026-06-30',
      );

      expect(adapter.requests.single.queryParameters['from'], '2026-06-01');
      expect(r['avgResponseMs'], 45000);
    });

    test('getAppLeadsCount reads /crm/leads/app-count and returns the count',
        () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads/app-count',
          statusCode: 200,
          body: {'count': 7},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final count = await service.getAppLeadsCount();

      expect(count, 7);
      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('getAppLeadsCount coerces a string count to int', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads/app-count',
          statusCode: 200,
          body: {'count': '12'},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      expect(await service.getAppLeadsCount(), 12);
    });

    test('listBranchDisciplines maps items to snake keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/branches/branch-a/disciplines',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'bd-1',
                'disciplineId': 'disc-1',
                'name': 'Вокал',
                'sortOrder': 0,
              },
              {
                'id': 'bd-2',
                'disciplineId': 'disc-2',
                'name': 'Гитара',
                'sortOrder': 1,
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final items = await service.listBranchDisciplines('branch-a');

      expect(items, hasLength(2));
      expect(items.first['id'], 'bd-1');
      expect(items.first['discipline_id'], 'disc-1');
      expect(items.first['name'], 'Вокал');
      expect(items.first['sort_order'], 0);
      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('listDisciplines maps items to {id, name}', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/disciplines',
          statusCode: 200,
          body: {
            'items': [
              {'id': 'disc-1', 'name': 'Вокал'},
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final items = await service.listDisciplines();

      expect(items.single['id'], 'disc-1');
      expect(items.single['name'], 'Вокал');
      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test(
      'getLeadStatusHistory requests /crm/leads/{id}/status-history and maps items',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/leads/lead-a/status-history',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'h1',
                  'oldStatus': 'Новый',
                  'newStatus': 'В работе',
                  'oldOwnerId': null,
                  'newOwnerId': 'user-b',
                  'changedBy': 'user-a',
                  'changedAt': '2026-06-10T12:00:00.000Z',
                  'reasonId': null,
                  'comment': 'Перевёл в работу',
                },
              ],
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final items = await service.getLeadStatusHistory('lead-a');

        expect(adapter.requests.single, isNotNull);
        expect(items.single['old_status'], 'Новый');
        expect(items.single['new_status'], 'В работе');
        expect(items.single['changed_at'], '2026-06-10T12:00:00.000Z');
        expect(items.single['comment'], 'Перевёл в работу');
      },
    );

    test(
      'listLeadApplications requests /crm/leads/{id}/applications and maps items',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/leads/lead-a/applications',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'app-1',
                  'appliedAt': '2026-06-20T10:00:00.000Z',
                  'channel': 'Заявка с сайта',
                  'office': 'Сокол',
                  'discipline': 'Вокал',
                  'status': 'Новая',
                  'utm': {'Source': 'yandex', 'Medium': 'cpc'},
                },
              ],
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final items = await service.listLeadApplications('lead-a');

        expect(adapter.requests.single, isNotNull);
        expect(items.single['applied_at'], '2026-06-20T10:00:00.000Z');
        expect(items.single['channel'], 'Заявка с сайта');
        expect(items.single['discipline'], 'Вокал');
        expect(items.single['utm'], {'Source': 'yandex', 'Medium': 'cpc'});
      },
    );

    test(
      'getFamilyForEntity requests /crm/families/by-entity/{type}/{id} and maps family + members',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/families/by-entity/lead/lead-a',
            statusCode: 200,
            body: {
              'family': {
                'id': 'fam-1',
                'name': 'Ивановы',
                'branchId': 'branch-a',
                'primaryPayerMemberId': 'm2',
              },
              'members': [
                {
                  'id': 'm1',
                  'entityType': 'lead',
                  'entityId': 'lead-a',
                  'role': 'child',
                  'isPrimaryContact': false,
                  'name': 'Аня Иванова',
                },
                {
                  'id': 'm2',
                  'entityType': 'profile',
                  'entityId': 'prof-1',
                  'role': 'parent',
                  'isPrimaryContact': true,
                  'name': 'Мария Иванова',
                },
              ],
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final result = await service.getFamilyForEntity(
          entityType: 'lead',
          entityId: 'lead-a',
        );

        expect((result['family'] as Map)['name'], 'Ивановы');
        expect((result['family'] as Map)['primary_payer_member_id'], 'm2');
        final members = result['members'] as List;
        expect(members.length, 2);
        expect(members.last['is_primary_contact'], true);
        expect(members.last['name'], 'Мария Иванова');
      },
    );

    test('getFamilyForEntity returns null family when entity has no family', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/families/by-entity/student/student-x',
          statusCode: 200,
          body: {'family': null, 'members': <dynamic>[]},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final result = await service.getFamilyForEntity(
        entityType: 'student',
        entityId: 'student-x',
      );

      expect(result['family'], isNull);
      expect((result['members'] as List), isEmpty);
    });
  });
}

MagicApiClient _client(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.phantom-net.ru',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return MagicApiClient(
    baseUrl: 'https://api.phantom-net.ru',
    tokenStore: MemoryMagicTokenStore(),
    dio: dio,
  );
}

class _FakeResponse {
  final String path;
  final int statusCode;
  final Object? body;

  const _FakeResponse({
    required this.path,
    required this.statusCode,
    required this.body,
  });
}

class _CapturedRequest {
  final Map<String, dynamic> queryParameters;
  final Map<String, dynamic> body;

  const _CapturedRequest({required this.queryParameters, required this.body});
}

class _FakeAdapter implements HttpClientAdapter {
  final List<_FakeResponse> _responses;
  final List<_CapturedRequest> requests = [];

  _FakeAdapter(this._responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_responses.isEmpty) {
      return ResponseBody.fromString(
        jsonEncode({'message': 'Unexpected request: ${options.path}'}),
        500,
      );
    }

    final response = _responses.removeAt(0);
    expect(options.uri.path, response.path);
    final requestBody = options.data is Map<String, dynamic>
        ? options.data as Map<String, dynamic>
        : <String, dynamic>{};
    requests.add(
      _CapturedRequest(
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
        body: requestBody,
      ),
    );
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
