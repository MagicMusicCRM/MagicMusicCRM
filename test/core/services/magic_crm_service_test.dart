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
    test(
      'reads managed credentials through dedicated access endpoints',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/teachers/teacher-a/access',
            statusCode: 200,
            body: {
              'email': 'teacher@example.com',
              'password': 'teacher-password-123',
              'passwordRecoverable': true,
            },
          ),
          _FakeResponse(
            path: '/crm/staff/staff-a/access',
            statusCode: 200,
            body: {
              'email': 'staff@example.com',
              'password': 'staff-password-123',
              'passwordRecoverable': true,
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final teacher = await service.getTeacherAccess('teacher-a');
        final staff = await service.getStaffAccess('staff-a');

        expect(teacher['password'], 'teacher-password-123');
        expect(staff['email'], 'staff@example.com');
        expect(adapter.requests.map((request) => request.method), [
          'GET',
          'GET',
        ]);
      },
    );

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
            'sources': {'tasks': '/crm/shared-tasks?state=open'},
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
      expect(dashboard['sources']['tasks'], '/crm/shared-tasks?state=open');
      expect(adapter.requests.single.queryParameters['branchId'], 'branch-a');
    });

    test('uses canonical task filters and calendar', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/shared-tasks',
          statusCode: 200,
          body: {
            'items': <Map<String, dynamic>>[],
            'counters': {'open': 0, 'overdue': 0},
          },
        ),
        _FakeResponse(
          path: '/crm/shared-tasks/calendar',
          statusCode: 200,
          body: {
            'items': [
              {'day': '2026-08-12', 'count': 2},
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      await service.listSharedTasks(
        q: 'отчёт',
        priority: 'high',
        scope: 'branch',
      );
      final calendar = await service.sharedTaskCalendar(
        from: '2026-08-01T00:00:00.000Z',
        to: '2026-09-01T00:00:00.000Z',
        priority: 'high',
      );

      expect(adapter.requests.first.queryParameters['q'], 'отчёт');
      expect(adapter.requests.first.queryParameters['priority'], 'high');
      expect(adapter.requests.first.queryParameters['scope'], 'branch');
      expect(calendar, {'2026-08-12': 2});
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

    test(
      'branch lifecycle uses preview, versioned commit and archive listing',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/branches',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'branch-a',
                  'name': 'Сокол',
                  'lifecycleState': 'archived',
                  'version': 4,
                  'archivedAt': '2026-08-11T12:00:00.000Z',
                  'archiveReason': 'Переезд',
                },
              ],
            },
          ),
          _FakeResponse(
            path: '/crm/branches/branch-a/close-preview',
            statusCode: 200,
            body: {
              'branch': {'id': 'branch-a', 'version': 3},
              'canClose': true,
              'blockers': <Object>[],
            },
          ),
          _FakeResponse(
            path: '/crm/branches/branch-a/close',
            statusCode: 200,
            body: {
              'branch': {
                'id': 'branch-a',
                'lifecycleState': 'archived',
                'version': 4,
              },
            },
          ),
          _FakeResponse(
            path: '/crm/branches/branch-a/history',
            statusCode: 200,
            body: {
              'items': [
                {
                  'operation': 'archive',
                  'toState': 'archived',
                  'reasonText': 'Переезд',
                },
              ],
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final branches = await service.listBranches(includeArchived: true);
        final preview = await service.previewBranchClose('branch-a');
        await service.closeBranch(
          'branch-a',
          expectedVersion: 3,
          reasonText: ' Переезд ',
          effectiveDate: '2026-08-11',
        );
        final history = await service.listBranchLifecycleHistory('branch-a');

        expect(branches.single, containsPair('lifecycle_state', 'archived'));
        expect(branches.single['version'], 4);
        expect(preview['canClose'], isTrue);
        expect(history.single['reasonText'], 'Переезд');
        expect(
          adapter.requests.first.queryParameters['includeArchived'],
          isTrue,
        );
        expect(adapter.requests[2].body, {
          'expectedVersion': 3,
          'confirm': true,
          'reasonText': 'Переезд',
          'effectiveDate': '2026-08-11',
        });
        expect(adapter.requests[2].headers['Idempotency-Key'], isNotEmpty);
        expect(adapter.requests[2].headers['X-Request-Id'], isNotEmpty);
      },
    );

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
                'version': 7,
                'studentId': 'student-a',
                'groupId': null,
                'leadId': null,
                'teacherId': 'teacher-a',
                'branchId': 'branch-a',
                'roomId': 'room-a',
                'scheduledAt': '2026-06-15T09:00:00.000Z',
                'durationMinutes': 60,
                'status': 'scheduled',
                'lifecycleState': 'settlement_pending',
                'settlementFailureCode': 'ConflictException',
                'isTrial': true,
                'notes': null,
                'studentName': 'Анна Иванова',
                'teacherName': 'Иван Петров',
                'branchName': 'Центр',
                'roomName': '101',
                'groupName': null,
                'groupPricePerLesson': null,
                'groupParticipants': const [
                  {'clientId': 'student-a', 'clientName': 'Анна Иванова'},
                ],
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
      expect(matrix['items'].single['version'], 7);
      expect(matrix['items'].single['group_participants'], [
        {'clientId': 'student-a', 'clientName': 'Анна Иванова'},
      ]);
      expect(
        matrix['items'].single['settlement_failure_code'],
        'ConflictException',
      );
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

    // KVA-238: зарплатный модуль педагогов.
    test(
      'teacher payroll, payouts, rates, stats and group rate override',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/teachers/teacher-a/payroll',
            statusCode: 200,
            body: {
              'teacherId': 'teacher-a',
              'hoursTotal': 12,
              'accruedTotal': 8400,
              'bonusTotal': 500,
              'deductionTotal': 200,
              'paidTotal': 5000,
              'debt': 3700,
              'currentRate': 700,
              'rateHistory': [
                {'rate': 700, 'effectiveFrom': '2026-01-01'},
              ],
              'payouts': [
                {
                  'id': 'payout-a',
                  'kind': 'payout',
                  'amount': 5000,
                  'comment': 'За июнь',
                  'paidAt': '2026-07-01T10:00:00.000Z',
                  'authorName': 'Ольга Смирнова',
                },
              ],
            },
          ),
          _FakeResponse(
            path: '/crm/teachers/teacher-a/payouts',
            statusCode: 201,
            body: {
              'id': 'payout-b',
              'teacherId': 'teacher-a',
              'kind': 'bonus',
              'amount': 1000,
              'comment': 'Премия',
              'paidAt': '2026-07-10T10:00:00.000Z',
            },
          ),
          _FakeResponse(
            path: '/crm/teachers/teacher-a/rates',
            statusCode: 201,
            body: {
              'id': 'rate-a',
              'teacherId': 'teacher-a',
              'rate': 900,
              'effectiveFrom': '2026-08-01',
            },
          ),
          _FakeResponse(
            path: '/crm/reports/teacher-stats',
            statusCode: 200,
            body: {
              'from': '2026-07-01T00:00:00.000Z',
              'to': '2026-08-01T00:00:00.000Z',
              'items': [
                {
                  'teacherId': 'teacher-a',
                  'teacherName': 'Мария Петрова',
                  'hoursTotal': 3,
                  'accruedTotal': 2100,
                  'paidTotal': 500,
                  'units': [
                    {
                      'unitType': 'group',
                      'groupId': 'group-a',
                      'studentId': null,
                      'unitName': 'Вокал (группа)',
                      'rate': 700,
                      'days': [
                        {'date': '2026-07-01', 'hours': 1},
                      ],
                      'hoursTotal': 2,
                      'accruedTotal': 1400,
                    },
                  ],
                },
              ],
              'totals': {
                'hoursTotal': 3,
                'accruedTotal': 2100,
                'paidTotal': 500,
              },
            },
          ),
          _FakeResponse(
            path: '/crm/groups/group-a',
            statusCode: 200,
            body: {
              'id': 'group-a',
              'teacherId': 'teacher-a',
              'branchId': 'branch-a',
              'roomId': 'room-a',
              'name': 'Вокал (группа)',
              'pricePerLesson': 3000,
              'teacherRate': 0,
              'teacherName': 'Мария Петрова',
              'branchName': 'Центр',
              'roomName': '101',
              'createdAt': '2026-06-13T00:00:00.000Z',
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final payroll = await service.getTeacherPayroll('teacher-a');
        final payout = await service.createTeacherPayout(
          teacherId: 'teacher-a',
          kind: 'bonus',
          amount: 1000,
          expectedVersion: 2,
          reasonText: 'Премия за июль',
          comment: 'Премия',
        );
        final rate = await service.setTeacherHourRate(
          teacherId: 'teacher-a',
          rate: 900,
          expectedVersion: 3,
          reasonText: 'Новая ставка с августа',
          effectiveFrom: '2026-08-01',
        );
        final stats = await service.getTeacherStatsReport(
          from: '2026-07-01T00:00:00.000Z',
          to: '2026-08-01T00:00:00.000Z',
          branchId: 'branch-a',
          teacherId: 'teacher-a',
          unitType: 'group',
        );
        // «Входит в оклад» = 0 (drill-down отчёта переводит группу в 0).
        final group = await service.updateGroup(
          'group-a',
          teacherRate: 0,
          setTeacherRate: true,
        );

        expect(payroll['debt'], 3700);
        expect(payroll['currentRate'], 700);
        expect((payroll['payouts'] as List).single['kind'], 'payout');

        expect(payout['kind'], 'bonus');
        expect(adapter.requests[1].body['kind'], 'bonus');
        expect(adapter.requests[1].body['amount'], 1000);
        expect(adapter.requests[1].body['comment'], 'Премия');
        expect(adapter.requests[1].body['expectedVersion'], 2);
        expect(adapter.requests[1].body['reasonText'], 'Премия за июль');

        expect(rate['rate'], 900);
        expect(adapter.requests[2].body['rate'], 900);
        expect(adapter.requests[2].body['expectedVersion'], 3);
        expect(adapter.requests[2].body['effectiveFrom'], '2026-08-01');

        expect((stats['items'] as List).single['teacherName'], 'Мария Петрова');
        expect(adapter.requests[3].queryParameters['branchId'], 'branch-a');
        expect(adapter.requests[3].queryParameters['teacherId'], 'teacher-a');
        expect(adapter.requests[3].queryParameters['unitType'], 'group');

        expect(group['teacher_rate'], 0);
        expect(adapter.requests[4].body.containsKey('teacherRate'), isTrue);
        expect(adapter.requests[4].body['teacherRate'], 0);
      },
    );

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
        expectedVersion: 1,
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
            'role': 'admin',
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
        _FakeResponse(
          path: '/crm/teachers/legacy-teacher/access',
          statusCode: 201,
          body: {
            'id': 'legacy-teacher',
            'email': 'legacy.teacher@example.com',
            'appRole': 'teacher',
            'isAppAccount': true,
          },
        ),
        _FakeResponse(
          path: '/crm/staff/legacy-staff/access',
          statusCode: 201,
          body: {
            'id': 'legacy-staff',
            'email': 'legacy.staff@example.com',
            'role': 'admin',
            'appRole': 'admin',
            'isAppAccount': true,
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
        password: 'password-123',
        phone: '+79991111111',
        branchIds: const ['branch-a'],
        disciplineIds: const ['discipline-a'],
        customDataPatch: const {
          'levels': ['Начальный'],
          'categories': ['Дети'],
        },
        salary: 15000,
        rate: 750,
        rateEffectiveFrom: '2026-08-01',
      );
      final updatedTeacher = await service.updateTeacher(
        'teacher-a',
        firstName: 'Мария',
        lastName: 'Петрова',
        email: 'teacher@example.com',
        phone: '+79991111111',
        branchIds: const ['branch-a'],
        disciplineIds: const ['discipline-b'],
        customDataPatch: const {
          'levels': ['Средний'],
        },
        salary: 20000,
        rate: 900,
        rateEffectiveFrom: '2026-08-10',
        payrollExpectedVersion: 3,
        payrollReasonText: 'Плановое изменение условий',
      );
      final staff = await service.createStaff(
        firstName: 'Ольга',
        lastName: 'Смирнова',
        email: 'staff@example.com',
        password: 'password-123',
        phone: '+79992222222',
        branchIds: const ['branch-a'],
      );
      final updatedStaff = await service.updateStaff(
        'staff-a',
        firstName: 'Ольга',
        lastName: 'Смирнова',
        email: 'staff@example.com',
        phone: '+79992222222',
        position: 'Операционный управляющий',
        status: 'working',
        customDataPatch: {'birthday': '1990-06-01'},
      );
      final provisionedTeacher = await service.provisionTeacherAccess(
        teacherId: 'legacy-teacher',
        email: 'legacy.teacher@example.com',
        password: 'password-123',
      );
      final provisionedStaff = await service.provisionStaffAccess(
        staffId: 'legacy-staff',
        email: 'legacy.staff@example.com',
        password: 'password-123',
      );

      expect(student['first_name'], 'Анна');
      expect(teacher['specialization'], 'Вокал');
      expect(updatedTeacher['specialization'], 'Фортепиано');
      expect(staff['role'], 'admin');
      expect(updatedStaff['position'], 'Операционный управляющий');
      expect(updatedStaff['custom_data']['birthday'], '1990-06-01');
      expect(provisionedTeacher['is_app_account'], true);
      expect(provisionedStaff['app_role'], 'admin');
      expect(adapter.requests[0].body['firstName'], 'Анна');
      expect(adapter.requests[1].body['branchIds'], ['branch-a']);
      expect(adapter.requests[1].body['disciplineIds'], ['discipline-a']);
      expect(adapter.requests[1].body['password'], 'password-123');
      expect(adapter.requests[1].body['customDataPatch']['levels'], [
        'Начальный',
      ]);
      expect(adapter.requests[1].body['salary'], 15000);
      expect(adapter.requests[1].body['rate'], 750);
      expect(adapter.requests[1].body['rateEffectiveFrom'], '2026-08-01');
      expect(adapter.requests[2].body['branchIds'], ['branch-a']);
      expect(adapter.requests[2].body['disciplineIds'], ['discipline-b']);
      expect(adapter.requests[2].body['customDataPatch']['levels'], [
        'Средний',
      ]);
      expect(adapter.requests[2].body['salary'], 20000);
      expect(adapter.requests[2].body['rate'], 900);
      expect(adapter.requests[2].body['rateEffectiveFrom'], '2026-08-10');
      expect(adapter.requests[2].body['payrollExpectedVersion'], 3);
      expect(
        adapter.requests[2].body['payrollReasonText'],
        'Плановое изменение условий',
      );
      expect(adapter.requests[1].body['accessRole'], 'teacher');
      expect(adapter.requests[3].body['accessRole'], 'admin');
      expect(adapter.requests[3].body['branchIds'], ['branch-a']);
      expect(adapter.requests[3].body['password'], 'password-123');
      expect(adapter.requests[4].body['position'], 'Операционный управляющий');
      expect(
        adapter.requests[4].body['customDataPatch']['birthday'],
        '1990-06-01',
      );
      expect(adapter.requests[5].body, {
        'email': 'legacy.teacher@example.com',
        'password': 'password-123',
      });
      expect(adapter.requests[6].body, {
        'email': 'legacy.staff@example.com',
        'password': 'password-123',
      });
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

    test('lists student groups through v3 API', () async {
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
      ]);
      final service = MagicCrmService(_client(adapter));

      final groups = await service.listStudentGroups('student-a', limit: 10);
      expect(groups.single['teachers']['first_name'], 'Иван');
      expect(groups.single['teachers']['last_name'], 'Петров');
      expect(adapter.requests.single.queryParameters['limit'], 10);
    });

    test('creates, updates and archives rooms through lifecycle API', () async {
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
          path: '/crm/rooms/room-b/archive-preview',
          statusCode: 200,
          body: {
            'room': {'id': 'room-b', 'version': 1},
            'canArchive': true,
            'blockers': <dynamic>[],
          },
        ),
        _FakeResponse(
          path: '/crm/rooms/room-b/archive',
          statusCode: 200,
          body: {
            'room': {
              'id': 'room-b',
              'lifecycleState': 'archived',
              'version': 2,
            },
          },
        ),
        _FakeResponse(
          path: '/crm/rooms/room-b/history',
          statusCode: 200,
          body: {
            'items': [
              {'operation': 'archive', 'reasonText': 'Ремонт класса'},
            ],
          },
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
      final preview = await service.previewRoomArchive('room-b');
      await service.archiveRoom(
        'room-b',
        expectedVersion: 1,
        reasonText: ' Ремонт класса ',
        effectiveDate: '2026-08-11',
      );
      final history = await service.listRoomLifecycleHistory('room-b');

      expect(created['branch_id'], 'branch-a');
      expect(created['branches']['name'], 'Центр');
      expect(updated['name'], '103');
      expect(adapter.requests[0].body['name'], '102');
      expect(adapter.requests[0].body['branchId'], 'branch-a');
      expect(adapter.requests[0].body['capacity'], 6);
      expect(adapter.requests[1].body['name'], '103');
      expect(adapter.requests[1].body['capacity'], 8);
      expect(preview['canArchive'], isTrue);
      expect(history.single['reasonText'], 'Ремонт класса');
      expect(adapter.requests[3].body, {
        'expectedVersion': 1,
        'confirm': true,
        'reasonText': 'Ремонт класса',
        'effectiveDate': '2026-08-11',
      });
      expect(adapter.requests[3].headers['Idempotency-Key'], isNotEmpty);
      expect(adapter.requests[3].headers['X-Request-Id'], isNotEmpty);
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
                'version': 7,
                'studentId': 'student-a',
                'groupId': null,
                'leadId': null,
                'teacherId': 'teacher-a',
                'branchId': null,
                'roomId': null,
                'scheduledAt': '2026-06-12T12:00:00.000Z',
                'durationMinutes': 60,
                'status': 'completed',
                'lifecycleState': 'successfully_completed',
                'reservationState': 'reserved',
                'settlementFailureCode': 'ConflictException',
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
      expect(lessons.single['lifecycle_state'], 'successfully_completed');
      expect(lessons.single['reservation_state'], 'reserved');
      expect(lessons.single['settlement_failure_code'], 'ConflictException');
      expect(lessons.single['version'], 7);
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
                'nextCursor': 'cursor-a',
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
                    'linkedUserId': 'client-a',
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
            'nextCursor': null,
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
        hideConverted: true,
      );
      final card = await service.getLeadCard('lead-a');
      final nextPage = await service.listLeadBoard(
        statusId: 'status-a',
        cursor: 'cursor-a',
      );

      final column = (board['columns'] as List).single as Map<String, dynamic>;
      final lead = (column['items'] as List).single as Map<String, dynamic>;
      expect(board['total_count'], 3);
      expect(column['label'], 'Новый');
      expect(column['total_count'], 3);
      expect(lead['assigned_name'], 'Мария Менеджер');
      expect(lead['branch_name'], 'Центр');
      expect(lead['linked_user_id'], 'client-a');
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
      expect(board['next_cursor'], isNull);
      expect(column['next_cursor'], 'cursor-a');
      expect(adapter.requests[0].queryParameters['q'], 'анна');
      expect(adapter.requests[0].queryParameters['openTasks'], true);
      // ⚠️ Фильтр hideConverted живёт на бэке с июня, но фронт его НИ РАЗУ не
      // передавал — мёртвый код. Тест на то и стоит, чтобы он не умер снова:
      // без параметра в запросе тумблер на доске ничего не делает.
      expect(adapter.requests[0].queryParameters['hideConverted'], true);
      expect(adapter.requests[2].queryParameters['cursor'], 'cursor-a');
      expect(adapter.requests[2].queryParameters['statusId'], 'status-a');
    });

    test('requests and maps the unassigned lead-board column page', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads/board',
          statusCode: 200,
          body: {
            'columns': [
              {
                'id': 'unassigned',
                'name': 'Без статуса',
                'color': null,
                'sortOrder': 9999,
                'createdAt': null,
                'totalCount': 2,
                'nextCursor': null,
                'items': <dynamic>[],
              },
            ],
            'totalCount': 2,
            'nextCursor': null,
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final page = await service.listLeadBoard(
        unassigned: true,
        cursor:
            '2026-07-18T10:11:12.123456Z|11111111-1111-4111-8111-111111111111',
      );

      final column = (page['columns'] as List).single as Map<String, dynamic>;
      expect(column['id'], 'unassigned');
      expect(column['next_cursor'], isNull);
      expect(adapter.requests.single.queryParameters['unassigned'], true);
      expect(
        adapter.requests.single.queryParameters.containsKey('statusId'),
        false,
      );
    });

    test('passes the complete lead-board filter and sort contract', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads/board',
          statusCode: 200,
          body: {'columns': <dynamic>[], 'totalCount': 0, 'nextCursor': null},
        ),
        _FakeResponse(
          path: '/crm/lead-sources',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'source-a',
                'canonicalName': 'site',
                'displayName': 'Сайт',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/admin/staff',
          statusCode: 200,
          body: [
            {
              'id': 'manager-a',
              'displayName': 'Мария Менеджер',
              'role': 'manager',
            },
          ],
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      await service.listLeadBoard(
        q: 'Анна',
        statusId: 'status-a',
        branchId: 'branch-a',
        assignedTo: 'manager-a',
        source: 'Сайт',
        discipline: 'Вокал',
        level: 'Начальный',
        category: 'Взрослый',
        requestType: 'Пробное занятие',
        goal: 'Поставить голос',
        gender: 'Женский',
        preferredSchedule: 'вечер',
        from: '2026-06-01T00:00:00.000Z',
        to: '2026-07-01T00:00:00.000Z',
        sort: 'oldest',
        quick: 'active',
        openTasks: true,
        hideConverted: true,
      );
      final sources = await service.listLeadSources();
      final staff = await service.listResponsibleStaff();

      expect(adapter.requests.first.queryParameters, {
        'limit': 25,
        'quick': 'active',
        'sort': 'oldest',
        'q': 'Анна',
        'statusId': 'status-a',
        'branchId': 'branch-a',
        'assignedTo': 'manager-a',
        'source': 'Сайт',
        'discipline': 'Вокал',
        'level': 'Начальный',
        'category': 'Взрослый',
        'requestType': 'Пробное занятие',
        'goal': 'Поставить голос',
        'gender': 'Женский',
        'preferredSchedule': 'вечер',
        'from': '2026-06-01T00:00:00.000Z',
        'to': '2026-07-01T00:00:00.000Z',
        'openTasks': true,
        'hideConverted': true,
      });
      expect(sources.single, {'id': 'source-a', 'name': 'Сайт'});
      expect(staff.single, {
        'id': 'manager-a',
        'name': 'Мария Менеджер',
        'role': 'manager',
      });
      expect(
        adapter.requests.last.queryParameters['roles'],
        'admin,manager,director',
      );
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
        expectedVersion: 1,
        lastName: 'Сидоров',
        statusId: 'status-b',
        notes: 'Важно',
        customDataPatch: {'level': 'beginner'},
      );
      expect(created['name'], 'Петр');
      expect(created['status'], 'status-a');
      expect(updated['last_name'], 'Сидоров');
      expect(updated['custom_data']['level'], 'beginner');
      expect(
        adapter.requests[0].body['customDataPatch']['discipline'],
        'Гитара',
      );
      expect(adapter.requests[1].body['statusId'], 'status-b');
    });

    test(
      'sends explicit responsible clear flags only when requested',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/leads/lead-a',
            statusCode: 200,
            body: {'id': 'lead-a', 'customData': <String, dynamic>{}},
          ),
          _FakeResponse(
            path: '/crm/students/student-a',
            statusCode: 200,
            body: {'id': 'student-a', 'customData': <String, dynamic>{}},
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        await service.updateLead(
          'lead-a',
          expectedVersion: 1,
          clearAssignedTo: true,
        );
        await service.updateStudent(
          'student-a',
          expectedVersion: 1,
          clearResponsible: true,
        );

        expect(adapter.requests[0].body, {
          'expectedVersion': 1,
          'clearAssignedTo': true,
        });
        expect(adapter.requests[1].body, {
          'expectedVersion': 1,
          'clearResponsible': true,
        });
      },
    );

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

    test('maps schedule month summary counts and room ids', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/schedule/month-summary',
          statusCode: 200,
          body: {
            'items': [
              {
                'day': '2026-08-06',
                'count': '3',
                'roomIds': ['room-a', 'room-b'],
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final summary = await service.getScheduleMonthSummary(
        from: '2026-08-01T00:00:00Z',
        to: '2026-09-01T00:00:00Z',
        branchId: 'branch-a',
      );

      expect(summary.single, {
        'day': '2026-08-06',
        'count': 3,
        'room_ids': ['room-a', 'room-b'],
      });
      expect(adapter.requests.single.queryParameters, {
        'from': '2026-08-01T00:00:00Z',
        'to': '2026-09-01T00:00:00Z',
        'branchId': 'branch-a',
      });
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

    test('maps subscriptions to legacy keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/students/student-a/commerce',
          statusCode: 200,
          body: {
            'projection': 'admin_scoped',
            'student': {
              'studentId': 'student-a',
              'accounts': <dynamic>[],
              'subscriptions': [
                {
                  'id': 'sub-a',
                  'status': 'active',
                  'startsAt': '2026-06-01',
                  'expiresAt': '2026-07-01',
                  'units': {
                    'total': '8',
                    'used': '3',
                    'reserved': '0',
                    'paid': '8',
                    'available': '5',
                    'remaining': '5',
                  },
                  'financial': {
                    'actualPaidMinor': '640000',
                    'obligationMinor': '640000',
                    'debtMinor': '0',
                    'overpaymentMinor': '0',
                    'nextPaymentAt': null,
                  },
                  'terms': {
                    'displayName': 'Вокал — 8 часов',
                    'validityDays': 30,
                    'basePriceMinor': '800000',
                    'finalPriceMinor': '640000',
                    'currencyCode': 'RUB',
                    'discount': {
                      'type': 'percent',
                      'percentBasisPoints': 2000,
                      'reason': 'retention.offer',
                    },
                  },
                  'installments': <dynamic>[],
                },
              ],
              'movements': <dynamic>[],
              'lessonBalance': {
                'activeSubscriptionCount': 1,
                'total': '8',
                'used': '3',
                'reserved': '0',
                'paid': '8',
                'available': '5',
                'debts': <dynamic>[],
                'nextPaymentAt': null,
                'expiresAt': '2026-07-01',
              },
            },
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final subscriptions = await service.listSubscriptions(
        studentId: 'student-a',
        limit: 1,
      );

      expect(adapter.requests.single.queryParameters, isEmpty);
      expect(subscriptions.single['student_id'], 'student-a');
      expect(subscriptions.single['lessons_total'], 8);
      expect(subscriptions.single['lessons_used'], 3);
      expect(subscriptions.single['lessons_remaining'], 5);
      expect(subscriptions.single['package_name'], 'Вокал — 8 часов');
      expect(subscriptions.single['package_price'], 6400);
      expect(subscriptions.single['valid_until'], '2026-07-01T00:00:00.000');
    });

    test('maps payments', () async {
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
      ]);
      final service = MagicCrmService(_client(adapter));

      final payments = await service.listPayments(
        from: '2026-06-01T00:00:00.000Z',
        limit: 10,
      );
      expect(payments.single.studentFirstName, 'Анна');
      expect(payments.single.type, 'subscription');
      expect(payments.single.notes, 'Оплата абонемента');
      expect(payments.single.description, 'Оплата абонемента');
      expect(
        adapter.requests[0].queryParameters['from'],
        '2026-06-01T00:00:00.000Z',
      );
    });

    test('maps unified timeline', () async {
      final adapter = _FakeAdapter([
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

      final timeline = await service.listTimeline(
        entityType: 'student',
        entityId: 'student-a',
        from: '2026-06-01T00:00:00.000Z',
        to: '2026-07-01T00:00:00.000Z',
        includeAudit: true,
        limit: 40,
      );

      expect(timeline.single['amount'], 12000);
      expect(timeline.single['actor_name'], 'Мария Менеджер');
      expect(adapter.requests[0].queryParameters['includeAudit'], true);
      expect(adapter.requests[0].queryParameters['limit'], 40);
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

    test(
      'getAnalyticsFunnel requests /analytics/funnel and maps stages',
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
      },
    );

    test(
      'getAnalyticsDebts requests /analytics/debts and maps buckets',
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
      },
    );

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
      },
    );

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
          body: {'forecastAmount': 120000, 'confirmedAmount': 80000},
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
          body: {'avgResponseMs': 45000, 'withinSlaPercent': 92.5},
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

    test(
      'getAppLeadsCount reads /crm/leads/app-count and returns the count',
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
      },
    );

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
                'lifecycleState': 'active',
                'version': 2,
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
      expect(items.first['lifecycle_state'], 'active');
      expect(items.first['version'], 2);
      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test(
      'listBranchDisciplines can include archived links explicitly',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/branches/branch-a/disciplines',
            statusCode: 200,
            body: {'items': <Map<String, dynamic>>[]},
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        await service.listBranchDisciplines('branch-a', includeArchived: true);

        expect(adapter.requests.single.queryParameters, {
          'includeArchived': true,
        });
      },
    );

    test('listDisciplines maps items to {id, name}', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/disciplines',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'disc-1',
                'name': 'Вокал',
                'lifecycleState': 'archived',
                'version': 4,
                'archiveReason': 'Больше не ведём',
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final items = await service.listDisciplines(includeArchived: true);

      expect(items.single['id'], 'disc-1');
      expect(items.single['name'], 'Вокал');
      expect(items.single['lifecycle_state'], 'archived');
      expect(items.single['version'], 4);
      expect(items.single['archive_reason'], 'Больше не ведём');
      expect(adapter.requests.single.queryParameters, {
        'includeArchived': true,
      });
    });

    test('assignBranchDiscipline posts selected dictionary value', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/branches/branch-a/disciplines',
          statusCode: 201,
          body: {'id': 'bd-1', 'disciplineId': 'disc-1', 'sortOrder': 0},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      await service.assignBranchDiscipline(
        branchId: 'branch-a',
        disciplineId: 'disc-1',
      );

      expect(adapter.requests.single.body, {'disciplineId': 'disc-1'});
    });

    test(
      'reference lifecycle uses preview, history and versioned mutation paths',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/disciplines/disc-1/lifecycle-preview',
            statusCode: 201,
            body: {
              'entity': {'id': 'disc-1', 'version': 3},
              'blockers': <Map<String, dynamic>>[],
            },
          ),
          _FakeResponse(
            path: '/crm/disciplines/disc-1/history',
            statusCode: 200,
            body: {
              'items': [
                {'operation': 'rename', 'version': 2},
              ],
            },
          ),
          _FakeResponse(
            path: '/crm/loss-reasons/reason-1',
            statusCode: 200,
            body: {
              'preview': {
                'entity': {'id': 'reason-1', 'version': 2},
              },
            },
          ),
          _FakeResponse(
            path: '/crm/branch-disciplines/link-1/unassign',
            statusCode: 201,
            body: {
              'preview': {
                'entity': {'id': 'link-1', 'version': 2},
              },
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final preview = await service.previewReferenceCatalogLifecycle(
          entityType: 'discipline',
          id: 'disc-1',
        );
        final history = await service.listReferenceCatalogHistory(
          entityType: 'discipline',
          id: 'disc-1',
        );
        await service.renameReferenceCatalogItem(
          entityType: 'loss_reason',
          id: 'reason-1',
          name: 'Высокая цена',
          expectedVersion: 1,
          reasonText: 'Уточнили формулировку',
        );
        await service.archiveReferenceCatalogItem(
          entityType: 'branch_discipline',
          id: 'link-1',
          expectedVersion: 1,
          reasonText: 'Больше не ведём в филиале',
        );

        expect(preview['entity']['version'], 3);
        expect(history.single['operation'], 'rename');
        expect(adapter.requests[2].method, 'PATCH');
        expect(adapter.requests[2].body, {
          'name': 'Высокая цена',
          'expectedVersion': 1,
          'confirm': true,
          'reasonText': 'Уточнили формулировку',
        });
        expect(adapter.requests[3].method, 'POST');
        expect(adapter.requests[3].body['confirm'], true);
        expect(adapter.requests[2].headers['Idempotency-Key'], isNotEmpty);
        expect(adapter.requests[3].headers['X-Request-Id'], isNotEmpty);
      },
    );

    test('loss reason catalog supports archive listing and creation', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/loss-reasons',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'reason-1',
                'name': 'Нет времени',
                'lifecycleState': 'archived',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/loss-reasons',
          statusCode: 201,
          body: {'id': 'reason-2', 'name': 'Подумает позже', 'kind': 'paused'},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final items = await service.listLossReasons(includeArchived: true);
      await service.createLossReason(name: 'Подумает позже', kind: 'paused');

      expect(items.single['lifecycleState'], 'archived');
      expect(adapter.requests.first.queryParameters, {'includeArchived': true});
      expect(adapter.requests.last.body, {
        'name': 'Подумает позже',
        'kind': 'paused',
      });
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

    test(
      'getFamilyForEntity returns null family when entity has no family',
      () async {
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
      },
    );

    test(
      'issueLeadSubscription converts only through the package endpoint',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/crm/leads/lead-a/subscriptions/issue',
            statusCode: 201,
            body: {
              'converted': true,
              'student': {'id': 'student-a'},
            },
          ),
        ]);
        final service = MagicCrmService(_client(adapter));

        final result = await service.issueLeadSubscription(
          'lead-a',
          'package-a',
        );

        expect(result['converted'], true);
        expect(adapter.requests.single.body, {'packageId': 'package-a'});
      },
    );

    test('lead homework list and create preserve lead ownership', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/homeworks',
          statusCode: 200,
          body: {'items': <dynamic>[]},
        ),
        _FakeResponse(
          path: '/crm/homeworks',
          statusCode: 201,
          body: {'id': 'homework-a'},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      await service.listHomeworks(leadId: 'lead-a', limit: 5);
      await service.createHomework(
        leadId: 'lead-a',
        lessonId: 'trial-a',
        title: 'Гамма до мажор',
      );

      expect(adapter.requests.first.queryParameters, {
        'leadId': 'lead-a',
        'limit': 5,
      });
      expect(adapter.requests.last.body, {
        'title': 'Гамма до мажор',
        'leadId': 'lead-a',
        'lessonId': 'trial-a',
      });
    });

    test(
      'group schedule plan preview, create and update keep participant contract',
      () async {
        final adapter = _FakeAdapter([
          const _FakeResponse(
            path: '/crm/schedule-plans/constraints/preview',
            statusCode: 200,
            body: {'valid': true, 'conflicts': <dynamic>[]},
          ),
          const _FakeResponse(
            path: '/crm/schedule-plans',
            statusCode: 201,
            body: {'id': 'plan-group', 'version': 1},
          ),
          const _FakeResponse(
            path: '/crm/schedule-plans/plan-group/constraints/preview',
            statusCode: 200,
            body: {'valid': true, 'rows': <dynamic>[]},
          ),
          const _FakeResponse(
            path: '/crm/schedule-plans/plan-group',
            statusCode: 200,
            body: {'id': 'plan-group', 'version': 2},
          ),
        ]);
        final service = MagicCrmService(_client(adapter));
        const participants = [
          {'studentId': 'student-a', 'subscriptionId': 'subscription-a'},
          {'studentId': 'student-b', 'subscriptionId': 'subscription-b'},
        ];
        const rows = [
          {
            'teacherId': 'teacher-a',
            'roomId': 'room-a',
            'branchId': 'branch-a',
            'weekday': DateTime.monday,
            'beginTime': '16:00',
            'durationMinutes': 60,
            'financialDecision': {
              'settlementTypeKey': 'free_lesson',
              'teacherCompensationRuleKey': 'none',
            },
          },
        ];
        const identity = MagicMutationIdentity(
          idempotencyKey: 'group-plan-command',
          requestId: 'group-plan-request',
        );

        await service.previewSchedulePlanConstraints(
          title: ' Ансамбль ',
          kind: 'group',
          groupId: 'group-a',
          participants: participants,
          activeFrom: '2026-08-17',
          activeUntil: null,
          rows: rows,
        );
        await service.createSchedulePlan(
          identity: identity,
          title: ' Ансамбль ',
          kind: 'group',
          groupId: 'group-a',
          participants: participants,
          activeFrom: '2026-08-17',
          activeUntil: null,
          rows: rows,
        );
        await service.previewSchedulePlanUpdateConstraints(
          'plan-group',
          expectedVersion: 1,
          effectiveFrom: '2026-09-01',
          title: ' Ансамбль ',
          participants: participants.take(1).toList(),
          activeUntil: null,
          rows: rows,
        );
        await service.updateSchedulePlan(
          'plan-group',
          identity: identity,
          expectedVersion: 1,
          effectiveFrom: '2026-09-01',
          title: 'Ансамбль',
          participants: participants.take(1).toList(),
          activeUntil: null,
          rows: rows,
        );

        for (final request in adapter.requests.take(2)) {
          expect(request.body['kind'], 'group');
          expect(request.body['groupId'], 'group-a');
          expect(request.body['participants'], participants);
          expect(request.body, isNot(contains('studentId')));
          expect(request.body, isNot(contains('subscriptionId')));
          expect(request.body['title'], 'Ансамбль');
        }
        expect(adapter.requests[1].method, 'POST');
        expect(
          adapter.requests[1].headers['Idempotency-Key'],
          'group-plan-command',
        );
        expect(adapter.requests[2].method, 'POST');
        expect(adapter.requests[2].body['expectedVersion'], 1);
        expect(adapter.requests[2].body['title'], 'Ансамбль');
        expect(adapter.requests[2].body['participants'], [participants.first]);
        expect(adapter.requests[3].method, 'PATCH');
        expect(adapter.requests[3].body, adapter.requests[2].body);
        expect(adapter.requests[3].body, isNot(contains('subscriptionId')));
      },
    );
    test('owns the lesson settlement history route', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/lessons/lesson-a/settlement-history',
          statusCode: 200,
          body: {
            'items': [
              {'transitionId': 'transition-a'},
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final response = await service.getLessonSettlementHistory('lesson-a');

      expect(response['items'], [
        {'transitionId': 'transition-a'},
      ]);
      expect(adapter.requests.single.method, 'GET');
      expect(
        adapter.requests.single.path,
        '/crm/lessons/lesson-a/settlement-history',
      );
    });

    test('owns lesson analysis, catalog, preview and create routes', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/lessons/constraints/preview',
          statusCode: 200,
          body: {'valid': true, 'violations': [], 'suggestions': []},
        ),
        _FakeResponse(
          path: '/crm/configuration/lesson-decisions',
          statusCode: 200,
          body: {'settlementTypes': [], 'teacherCompensationRules': []},
        ),
        _FakeResponse(
          path: '/crm/lessons/lesson-a/reschedule/preview',
          statusCode: 200,
          body: {'canConfirm': true, 'previewToken': 'token-a'},
        ),
        _FakeResponse(
          path: '/crm/lessons',
          statusCode: 201,
          body: {'id': 'lesson-created'},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      await service.analyzeLessonSchedule(
        clientType: 'student',
        clientId: 'student-a',
        teacherId: 'teacher-a',
        branchId: 'branch-a',
        roomId: 'room-a',
        scheduledAt: '2026-08-26T10:00:00.000Z',
        durationMinutes: 60,
      );
      await service.getLessonDecisionCatalog(branchId: 'branch-a');
      await service.previewLessonDecision(
        lessonId: 'lesson-a',
        operationKey: 'reschedule',
        data: {'expectedVersion': 2},
      );
      await service.createLessonRaw({
        'clientRef': {'type': 'student', 'id': 'student-a'},
      });

      expect(adapter.requests.map((request) => request.path), [
        '/crm/lessons/constraints/preview',
        '/crm/configuration/lesson-decisions',
        '/crm/lessons/lesson-a/reschedule/preview',
        '/crm/lessons',
      ]);
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
  final String path;
  final String method;
  final Map<String, dynamic> queryParameters;
  final Map<String, dynamic> body;
  final Map<String, dynamic> headers;

  const _CapturedRequest({
    required this.path,
    required this.method,
    required this.queryParameters,
    required this.body,
    required this.headers,
  });
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
        path: options.uri.path,
        method: options.method,
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
        body: requestBody,
        headers: Map<String, dynamic>.from(options.headers),
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
