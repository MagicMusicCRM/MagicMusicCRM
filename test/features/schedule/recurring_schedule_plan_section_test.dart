import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/group_schedule_participants_editor.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';

import '../crm/client_card/card_fake_api.dart';

const _activePlan = {
  'id': 'plan-active',
  'kind': 'individual',
  'title': 'Индивидуальный вокал',
  'studentId': 'student-1',
  'subscriptionId': 'subscription-1',
  'activeFrom': '2026-08-01',
  'activeUntil': null,
  'status': 'active',
  'version': 1,
  'rows': [
    {
      'id': 'series-active',
      'teacherId': 'teacher-1',
      'teacherName': 'Мария Иванова',
      'roomId': 'room-1',
      'roomName': 'Класс 1',
      'branchId': 'branch-1',
      'branchName': 'Сокол',
      'weekday': 4,
      'beginTime': '16:00',
      'durationMinutes': 60,
      'validFrom': '2026-08-01',
      'validUntil': null,
      'financialDecision': {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'none',
      },
      'active': true,
    },
  ],
};

const _groupMembers = [
  GroupScheduleMemberOption(
    studentId: 'student-1',
    label: 'Анна Смирнова',
    subscriptions: [
      {
        'id': 'subscription-1',
        'package_name': 'Вокал 12',
        'lessons_total': 12,
        'lessons_used': 2,
      },
    ],
  ),
  GroupScheduleMemberOption(
    studentId: 'student-2',
    label: 'Борис Петров',
    subscriptions: [
      {
        'id': 'subscription-2',
        'package_name': 'Ансамбль 8',
        'lessons_total': 8,
        'lessons_used': 1,
      },
    ],
  ),
];

const _groupPlan = {
  'id': 'plan-group',
  'kind': 'group',
  'title': 'Вокальная группа',
  'groupId': 'group-1',
  'activeFrom': '2026-08-02',
  'activeUntil': '2026-12-31',
  'status': 'active',
  'version': 1,
  'participants': [
    {
      'id': 'participant-1',
      'studentId': 'student-1',
      'subscriptionId': 'subscription-1',
      'effectiveFrom': '2026-08-02',
      'effectiveUntil': '2026-12-31',
      'version': 1,
    },
    {
      'id': 'participant-2',
      'studentId': 'student-2',
      'subscriptionId': 'subscription-2',
      'effectiveFrom': '2026-08-02',
      'effectiveUntil': '2026-12-31',
      'version': 1,
    },
  ],
  'rows': [
    {
      'id': 'series-group',
      'teacherId': 'teacher-1',
      'teacherName': 'Мария Иванова',
      'roomId': 'room-1',
      'roomName': 'Класс 1',
      'branchId': 'branch-1',
      'branchName': 'Сокол',
      'weekday': 6,
      'beginTime': '12:00',
      'durationMinutes': 90,
      'validFrom': '2026-08-02',
      'validUntil': '2026-12-31',
      'financialDecision': {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'none',
      },
      'active': true,
    },
  ],
};

const _endedPlan = {
  'id': 'plan-ended',
  'kind': 'individual',
  'title': 'Завершённое фортепиано',
  'studentId': 'student-1',
  'subscriptionId': 'subscription-1',
  'activeFrom': '2026-01-01',
  'activeUntil': '2026-07-31',
  'status': 'ended',
  'version': 2,
  'endedAt': '2026-07-31T15:00:00.000Z',
  'endedBy': 'manager-1',
  'endedByName': 'Мария Управляющая',
  'endReason': 'Клиент завершил обучение',
  'rows': [
    {
      'id': 'series-ended',
      'teacherId': 'teacher-1',
      'teacherName': 'Мария Иванова',
      'roomId': 'room-1',
      'roomName': 'Класс 1',
      'branchId': 'branch-1',
      'branchName': 'Сокол',
      'weekday': 2,
      'beginTime': '11:00',
      'durationMinutes': 60,
      'validFrom': '2026-01-01',
      'validUntil': '2026-07-31',
      'financialDecision': {
        'settlementTypeKey': 'free_lesson',
        'teacherCompensationRuleKey': 'none',
      },
      'active': true,
    },
  ],
};

Map<String, dynamic> _timelinePage({
  String lessonId = 'lesson-active',
  String state = 'scheduled',
  bool covered = true,
  String? predecessorId,
  String? successorId,
  bool hasPrevious = false,
  bool hasNext = false,
  String? previousCursor,
  String? nextCursor,
}) => {
  'items': [
    {
      'id': lessonId,
      'version': 1,
      'scheduledAt': '2026-08-07T13:00:00.000Z',
      'durationMinutes': 60,
      'lifecycleState': state,
      'student': {'id': 'student-1', 'name': 'Анна Смирнова'},
      'group': null,
      'teacher': {'id': 'teacher-1', 'name': 'Мария Иванова'},
      'room': {'id': 'room-1', 'name': 'Класс 1'},
      'branch': {'id': 'branch-1', 'name': 'Сокол'},
      'origin': {
        'kind': lessonId.contains('manual') ? 'manual' : 'generated',
        'planId': lessonId.contains('manual') ? null : 'plan-active',
        'seriesId': lessonId.contains('manual') ? null : 'series-active',
      },
      'settlement': {
        'coveredBySubscription': covered,
        'settlementTypeKey': covered ? 'subscription' : null,
      },
      'reschedule': {
        'predecessorId': predecessorId,
        'successorId': successorId,
        'actionableLessonId': successorId ?? lessonId,
      },
    },
  ],
  'hasPrevious': hasPrevious,
  'hasNext': hasNext,
  'previousCursor': previousCursor,
  'nextCursor': nextCursor,
};

class _PagingCardApiClient extends FakeCardApiClient {
  _PagingCardApiClient({this.remainingNextFailures = 0})
    : super(role: 'manager', schedulePlans: const [_activePlan, _endedPlan]);

  int remainingNextFailures;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/students/student-1/lesson-timeline') {
      final query = {...?queryParameters};
      getRequests.add(path);
      getCalls.add((path: path, query: query));
      final cursor = query['cursor']?.toString();
      if (cursor == 'cursor-next') {
        if (remainingNextFailures > 0) {
          remainingNextFailures--;
          throw const MagicApiException(message: 'Временная ошибка сети');
        }
        return _timelinePage(
              lessonId: 'lesson-page-2',
              predecessorId: 'lesson-page-1',
              hasPrevious: true,
              previousCursor: 'cursor-previous',
            )
            as T;
      }
      return _timelinePage(
            lessonId: 'lesson-page-1',
            state: 'rescheduled',
            successorId: 'lesson-page-2',
            covered: false,
            hasNext: true,
            nextCursor: 'cursor-next',
          )
          as T;
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

class _ExactLessonCardApiClient extends FakeCardApiClient {
  _ExactLessonCardApiClient()
    : super(
        role: 'manager',
        student: const {
          'id': 'student-1',
          'firstName': 'Анна',
          'lastName': 'Смирнова',
        },
        branches: const [
          {'id': 'branch-1', 'name': 'Сокол'},
        ],
        teachers: const [
          {
            'id': 'teacher-1',
            'firstName': 'Мария',
            'lastName': 'Иванова',
            'status': 'active',
            'assignedBranches': [
              {'id': 'branch-1', 'name': 'Сокол'},
            ],
          },
        ],
        rooms: const [
          {'id': 'room-1', 'branchId': 'branch-1', 'name': 'Класс 1'},
        ],
        scheduleMatrix: const [_exactLesson],
        schedulePlans: const [_activePlan],
        studentLessonTimelinePage: _timelinePage(lessonId: 'lesson-exact-12'),
      );

  static const _exactLesson = <String, dynamic>{
    'id': 'lesson-exact-12',
    'version': 7,
    'studentId': 'student-1',
    'groupId': null,
    'leadId': null,
    'teacherId': 'teacher-1',
    'branchId': 'branch-1',
    'roomId': 'room-1',
    'scheduledAt': '2026-08-13T13:00:00.000Z',
    'durationMinutes': 60,
    'status': 'scheduled',
    'lifecycleState': 'scheduled',
    'isTrial': false,
    'studentName': 'Анна Смирнова',
    'teacherName': 'Мария Иванова',
    'branchName': 'Сокол',
    'roomName': 'Класс 1',
    'completionType': 'standard.success',
    'clientChargeType': 'none',
    'snapshotTrial': false,
  };

  Map<String, dynamic>? exactLessonQuery;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/lessons') {
      exactLessonQuery = {...?queryParameters};
      final lessonId = queryParameters?['lessonId']?.toString();
      return <String, dynamic>{
            'items': lessonId == _exactLesson['id']
                ? <dynamic>[_exactLesson]
                : <dynamic>[],
          }
          as T;
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('canonical timeline keeps subscription coverage visible', (
    tester,
  ) async {
    final api = _api(timelinePage: _timelinePage(covered: true));
    await _pump(tester, api);

    expect(find.text('Лента занятий'), findsOneWidget);
    expect(find.byKey(const Key('student-lesson-timeline')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('Абонемент') ?? false),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-plan-tray-plan-active')),
      findsNothing,
    );
  });

  for (final width in const [390.0, 768.0, 1440.0]) {
    testWidgets('plans and one timeline render at ${width.toInt()}', (
      tester,
    ) async {
      final api = _api();
      await _pump(tester, api, width: width, textScale: 1.25);

      expect(find.text('Постоянные расписания'), findsOneWidget);
      expect(find.text('Индивидуальный вокал'), findsOneWidget);
      expect(find.text('Вокальная группа'), findsOneWidget);
      expect(find.text('Лента занятий'), findsOneWidget);
      expect(find.byKey(const Key('student-lesson-timeline')), findsOneWidget);
      expect(find.text('Завершено'), findsOneWidget);
      expect(find.text('Завершённое фортепиано'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('global timeline pages and retries the failed cursor', (
    tester,
  ) async {
    final api = _PagingCardApiClient(remainingNextFailures: 1);
    await _pump(tester, api, width: 840);

    expect(
      find.byKey(const ValueKey('student-timeline-lesson-page-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('student-lesson-timeline-next')));
    await tester.pumpAndSettle();
    expect(find.text('Временная ошибка сети'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('student-timeline-lesson-page-1')),
      findsOneWidget,
    );
    expect(api.getCalls.last.query, {
      'cursor': 'cursor-next',
      'direction': 'next',
      'limit': 24,
    });

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('student-timeline-lesson-page-2')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('student-lesson-timeline-previous')));
    await tester.pumpAndSettle();
    expect(api.getCalls.last.query, {
      'cursor': 'cursor-previous',
      'direction': 'previous',
      'limit': 24,
    });
  });

  testWidgets('timeline opens the exact lesson ID', (tester) async {
    final api = _ExactLessonCardApiClient();
    await _pump(tester, api, width: 840);

    final item = find.byKey(const ValueKey('student-timeline-lesson-exact-12'));
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(api.exactLessonQuery?['lessonId'], 'lesson-exact-12');
    expect(api.exactLessonQuery?['limit'], 1);
  });

  testWidgets('no plan still shows the canonical manual lesson', (
    tester,
  ) async {
    final api = _api(
      plans: const [],
      timelinePage: _timelinePage(lessonId: 'lesson-manual', covered: false),
    );
    await _pump(tester, api);

    expect(find.text('Постоянных расписаний пока нет'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('Разовое занятие') ?? false),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('student-timeline-lesson-manual')),
      findsOneWidget,
    );
  });

  testWidgets(
    'group mode keeps group lessons and never calls student timeline',
    (tester) async {
      final api = _api(plans: const [_groupPlan]);
      await _pump(
        tester,
        api,
        groupId: 'group-1',
        subjectName: 'Вокальная группа',
        fallbackLessons: const [
          {
            'id': 'group-lesson-1',
            'scheduledAt': '2026-09-12T09:00:00.000Z',
            'teacherName': 'Мария Иванова',
          },
        ],
        groupMembers: _groupMembers,
      );

      expect(find.byKey(const Key('group-lesson-list')), findsOneWidget);
      expect(find.byKey(const Key('student-lesson-timeline')), findsNothing);
      expect(
        api.getCalls.where(
          (call) =>
              call.path.contains('/crm/students/') &&
              call.path.endsWith('/lesson-timeline'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets('row removal previews impact and removes UI only after commit', (
    tester,
  ) async {
    final api = _api(plans: const [_activePlan]);
    await _pump(tester, api, width: 840);

    final remove = find.byKey(const ValueKey('remove-plan-row-series-active'));
    expect(remove, findsOneWidget);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('schedule-plan-row-removal-reason')),
      'Смена преподавателя',
    );
    await tester.tap(find.byKey(const Key('schedule-plan-row-removal-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Будет отменено будущих занятий: 3'), findsOneWidget);
    expect(find.text('История проведённых занятий сохранится'), findsOneWidget);
    expect(remove, findsOneWidget);

    await tester.tap(
      find.byKey(const Key('schedule-plan-row-removal-confirm')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('schedule-plan-row-removal-submit')));
    await tester.pumpAndSettle();

    expect(remove, findsNothing);
    final commit = api.idempotentRequests.singleWhere(
      (request) =>
          request.path ==
          '/crm/schedule-plans/plan-active/rows/series-active/remove',
    );
    expect(commit.data['previewToken'], 'schedule-plan-row-preview-token');
    expect(commit.data['confirm'], true);
    expect(commit.identity.idempotencyKey, isNotEmpty);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'individual plan reads back shared and different teacher room rows',
    (tester) async {
      final api = _api(plans: const [], mutateSchedulePlanOnCreate: true);
      await _pump(tester, api);

      await tester.tap(find.byKey(const Key('schedule-plan-add')));
      await tester.pumpAndSettle();
      final firstDay = DateTime.now().weekday;
      final secondDay = firstDay == 7 ? 1 : firstDay + 1;
      final thirdDay = secondDay == 7 ? 1 : secondDay + 1;
      await tester.tap(
        find.byKey(ValueKey('preferred-schedule-weekday-$secondDay')),
      );
      await _chooseReferences(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('preferred-schedule-save')),
      );
      await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('schedule-plan-add-row-group')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('preferred-schedule-weekday-$firstDay')),
      );
      await tester.tap(
        find.byKey(ValueKey('preferred-schedule-weekday-$secondDay')),
      );
      await tester.tap(
        find.byKey(ValueKey('preferred-schedule-weekday-$thirdDay')),
      );
      await _chooseSearchable(
        tester,
        const ValueKey('preferred-schedule-teacher'),
        'Пётр Сидоров',
      );
      await _chooseSearchable(
        tester,
        const ValueKey('preferred-schedule-room'),
        'Класс 2',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('preferred-schedule-save')),
      );
      await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('schedule-plan-preview-and-create')),
      );
      await tester.pumpAndSettle();

      final preview = api.postRequests.singleWhere(
        (request) => request.path == '/crm/schedule-plans/constraints/preview',
      );
      final create = api.idempotentRequests.singleWhere(
        (request) => request.path == '/crm/schedule-plans',
      );
      for (final data in [preview.data, create.data]) {
        final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
        expect(rows, hasLength(3));
        for (final row in rows) {
          expect(row['financialDecision'], {
            'settlementTypeKey': 'free_lesson',
            'clientDecisions': [
              {
                'clientId': 'student-1',
                'chargeType': 'subscription',
                'subscriptionId': 'subscription-1',
              },
            ],
          });
        }
        expect(
          rows
              .where((row) => row['teacherId'] == 'teacher-1')
              .map((row) => row['weekday'])
              .toSet(),
          {firstDay, secondDay},
        );
        expect(
          rows
              .where((row) => row['teacherId'] == 'teacher-1')
              .every((row) => row['roomId'] == 'room-1'),
          isTrue,
        );
        expect(
          rows.singleWhere((row) => row['teacherId'] == 'teacher-2'),
          containsPair('roomId', 'room-2'),
        );
        expect(
          rows.singleWhere((row) => row['teacherId'] == 'teacher-2'),
          containsPair('weekday', thirdDay),
        );
      }
      expect(
        api.getCalls
            .where((request) => request.path == '/crm/schedule-plans')
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(
        find.byKey(const ValueKey('schedule-plan-created-plan-1')),
        findsOneWidget,
      );
      await _expandPlan(tester, 'created-plan-1');
      for (var index = 1; index <= 3; index++) {
        expect(
          find.byKey(ValueKey('schedule-plan-row-edit-created-series-$index')),
          findsOneWidget,
        );
      }
      expect(find.text('Мария Иванова'), findsWidgets);
      expect(find.text('Класс 1'), findsWidgets);
      expect(find.text('Пётр Сидоров'), findsOneWidget);
      expect(find.text('Класс 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('create and edit use one plan aggregate', (tester) async {
    final api = _api(plans: const [_activePlan]);
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('schedule-plan-add')));
    await tester.pumpAndSettle();
    await _chooseReferences(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('preferred-schedule-save')),
    );
    await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-plan-row-group-0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('schedule-plan-add-row-group')));
    await tester.pumpAndSettle();
    final currentDay = DateTime.now().weekday;
    final otherDay = currentDay == 7 ? 1 : currentDay + 1;
    await tester.tap(
      find.byKey(ValueKey('preferred-schedule-weekday-$currentDay')),
    );
    await tester.tap(
      find.byKey(ValueKey('preferred-schedule-weekday-$otherDay')),
    );
    await _chooseSearchable(
      tester,
      const ValueKey('preferred-schedule-teacher'),
      'Пётр Сидоров',
    );
    await _chooseSearchable(
      tester,
      const ValueKey('preferred-schedule-room'),
      'Класс 2',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('preferred-schedule-save')),
    );
    await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-plan-row-group-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();
    final createPreview = api.postRequests.singleWhere(
      (request) => request.path == '/crm/schedule-plans/constraints/preview',
    );
    final create = api.idempotentRequests.singleWhere(
      (request) => request.path == '/crm/schedule-plans',
    );
    expect(create.data, containsPair('kind', 'individual'));
    expect(create.data, containsPair('subscriptionId', 'subscription-1'));
    expect(create.data['activeUntil'], isNull);
    expect(create.data['rows'], hasLength(2));
    expect(
      (create.data['rows'] as List).map((row) => row['teacherId']),
      containsAll(['teacher-1', 'teacher-2']),
    );
    for (final data in [createPreview.data, create.data]) {
      for (final row in (data['rows'] as List).cast<Map<String, dynamic>>()) {
        expect(row['financialDecision'], {
          'settlementTypeKey': 'free_lesson',
          'clientDecisions': [
            {
              'clientId': 'student-1',
              'chargeType': 'subscription',
              'subscriptionId': 'subscription-1',
            },
          ],
        });
      }
    }

    await tester.ensureVisible(
      find.byKey(const ValueKey('schedule-plan-row-edit-series-active')),
    );
    await tester.tap(
      find.byKey(const ValueKey('schedule-plan-row-edit-series-active')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('preferred-schedule-save')),
    );
    await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-plan-row-group-0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();
    final updatePreview = api.postRequests.singleWhere(
      (request) =>
          request.path == '/crm/schedule-plans/plan-active/constraints/preview',
    );
    final update = api.idempotentRequests.singleWhere(
      (request) => request.path == '/crm/schedule-plans/plan-active',
    );
    expect(update.data['expectedVersion'], 1);
    expect((update.data['rows'] as List).single['seriesId'], 'series-active');
    for (final data in [updatePreview.data, update.data]) {
      expect((data['rows'] as List).single['financialDecision'], {
        'settlementTypeKey': 'free_lesson',
        'clientDecisions': <Map<String, dynamic>>[],
      });
    }
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'group plan creates one aggregate with per-student subscriptions',
    (tester) async {
      final api = _api(plans: const []);
      await _pump(
        tester,
        api,
        groupId: 'group-1',
        subjectName: 'Вокальная группа',
        groupMembers: _groupMembers,
      );

      await tester.tap(find.byKey(const Key('schedule-plan-add')));
      await tester.pumpAndSettle();
      expect(find.text('Анна Смирнова'), findsOneWidget);
      expect(find.text('Борис Петров'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('group-plan-participants-submit')),
      );
      await tester.pumpAndSettle();
      await _chooseReferences(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('preferred-schedule-save')),
      );
      await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('schedule-plan-preview-and-create')),
      );
      await tester.pumpAndSettle();

      final preview = api.postRequests.singleWhere(
        (request) => request.path == '/crm/schedule-plans/constraints/preview',
      );
      final create = api.idempotentRequests.singleWhere(
        (request) => request.path == '/crm/schedule-plans',
      );
      for (final data in [preview.data, create.data]) {
        expect(data['kind'], 'group');
        expect(data['groupId'], 'group-1');
        expect(data, isNot(contains('studentId')));
        expect(data, isNot(contains('subscriptionId')));
        expect(data['participants'], [
          {'studentId': 'student-1', 'subscriptionId': 'subscription-1'},
          {'studentId': 'student-2', 'subscriptionId': 'subscription-2'},
        ]);
      }
      expect(create.data['title'], 'Вокальная группа');
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('group participant changes keep a dated versioned update', (
    tester,
  ) async {
    final api = _api(plans: const [_groupPlan]);
    await _pump(
      tester,
      api,
      groupId: 'group-1',
      subjectName: 'Вокальная группа',
      groupMembers: _groupMembers,
    );

    final participantsButton = find.byKey(
      const ValueKey('schedule-plan-participants-plan-group'),
    );
    await tester.ensureVisible(participantsButton);
    await tester.tap(participantsButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('group-plan-member-student-2')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('group-plan-participants-submit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();

    final update = api.idempotentRequests.singleWhere(
      (request) => request.path == '/crm/schedule-plans/plan-group',
    );
    expect(update.data['expectedVersion'], 1);
    expect(update.data['effectiveFrom'], isNotEmpty);
    expect(update.data['participants'], [
      {'studentId': 'student-1', 'subscriptionId': 'subscription-1'},
    ]);
    expect((update.data['rows'] as List).single['seriesId'], 'series-group');
    final preview = api.postRequests.singleWhere(
      (request) =>
          request.path == '/crm/schedule-plans/plan-group/constraints/preview',
    );
    expect(preview.data['participants'], update.data['participants']);
    expect(preview.data['rows'], update.data['rows']);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'group conflict matrix names participant and reopens the retained draft',
    (tester) async {
      final api = _api(
        plans: const [],
        constraintPreviews: const [
          {
            'valid': false,
            'rows': [
              {
                'index': 0,
                'valid': false,
                'occurrencesChecked': 1,
                'failures': [
                  {
                    'studentId': 'student-2',
                    'occurrence': {'localDate': '2026-08-15'},
                    'violations': [
                      {
                        'code': 'INVALID_INTERVAL',
                        'resource': {'type': 'interval', 'id': 'candidate'},
                        'conflictingLessonIds': <String>[],
                      },
                      {
                        'code': 'OUTSIDE_BRANCH_HOURS',
                        'resource': {'type': 'branch', 'id': 'branch-1'},
                        'conflictingLessonIds': <String>[],
                      },
                      {
                        'code': 'TEACHER_UNAVAILABLE',
                        'resource': {'type': 'teacher', 'id': 'teacher-1'},
                        'conflictingLessonIds': <String>[],
                      },
                      {
                        'code': 'TEACHER_BRANCH_MISMATCH',
                        'resource': {'type': 'teacher', 'id': 'teacher-1'},
                        'conflictingLessonIds': <String>[],
                      },
                      {
                        'code': 'ROOM_BRANCH_MISMATCH',
                        'resource': {'type': 'room', 'id': 'room-1'},
                        'conflictingLessonIds': <String>[],
                      },
                      {
                        'code': 'CLIENT_OVERLAP',
                        'resource': {'type': 'client', 'id': 'student-2'},
                        'conflictingLessonIds': ['lesson-conflict'],
                        'conflictingRowIndexes': [1],
                      },
                      {
                        'code': 'TEACHER_OVERLAP',
                        'resource': {'type': 'teacher', 'id': 'teacher-1'},
                        'conflictingLessonIds': ['lesson-conflict'],
                      },
                      {
                        'code': 'ROOM_OVERLAP',
                        'resource': {'type': 'room', 'id': 'room-1'},
                        'conflictingLessonIds': ['lesson-conflict'],
                      },
                    ],
                  },
                ],
                'suggestions': [
                  {
                    'kind': 'SAME_TIME_ROOM',
                    'rank': 1,
                    'score': 1000,
                    'changes': {'roomId': 'room-2', 'roomName': 'Класс 2'},
                  },
                ],
              },
            ],
          },
        ],
      );
      await _pump(
        tester,
        api,
        groupId: 'group-1',
        subjectName: 'Вокальная группа',
        groupMembers: _groupMembers,
      );

      await tester.tap(find.byKey(const Key('schedule-plan-add')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('group-plan-participants-submit')),
      );
      await tester.pumpAndSettle();
      await _chooseReferences(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('preferred-schedule-save')),
      );
      await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('schedule-plan-preview-and-create')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Найдены ограничения расписания'), findsOneWidget);
      for (final label in const [
        'некорректный интервал',
        'вне часов работы филиала',
        'педагог недоступен',
        'педагог не назначен в этот филиал',
        'аудитория относится к другому филиалу',
        'педагог уже занят',
        'у клиента уже есть занятие',
        'аудитория уже занята',
      ]) {
        expect(find.textContaining(label), findsOneWidget);
      }
      expect(find.text('Участник: Борис Петров'), findsOneWidget);
      expect(
        find.textContaining('Свободная аудитория в то же время'),
        findsOneWidget,
      );
      expect(find.textContaining('Пересечение со строками: 2'), findsOneWidget);
      expect(find.textContaining('Открыть занятие 1'), findsWidgets);
      expect(
        api.idempotentRequests.where(
          (request) => request.path == '/crm/schedule-plans',
        ),
        isEmpty,
      );

      final fix = find.byKey(
        const ValueKey(
          'schedule-plan-fix-row-0-аудитория относится к другому филиалу-all',
        ),
      );
      await tester.ensureVisible(fix);
      await tester.tap(fix);
      await tester.pumpAndSettle();
      expect(find.text('Изменить набор дней'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('Мария Иванова'), findsWidgets);
      expect(find.text('Класс 1'), findsWidgets);
    },
  );

  testWidgets(
    'existing Plan keeps a conflicting edit until preview becomes valid',
    (tester) async {
      final api = _api(
        plans: const [_activePlan],
        constraintPreviews: const [
          {
            'valid': false,
            'rows': [
              {
                'index': 0,
                'valid': false,
                'occurrencesChecked': 1,
                'failures': [
                  {
                    'studentId': 'student-1',
                    'occurrence': {'localDate': '2026-08-20'},
                    'violations': [
                      {
                        'code': 'TEACHER_OVERLAP',
                        'resource': {'type': 'teacher', 'id': 'teacher-1'},
                        'conflictingLessonIds': ['lesson-busy'],
                      },
                    ],
                  },
                ],
              },
            ],
          },
          {
            'valid': true,
            'rows': [
              {
                'index': 0,
                'valid': true,
                'occurrencesChecked': 1,
                'failures': <dynamic>[],
              },
            ],
          },
        ],
      );
      await _pump(tester, api);

      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule-plan-row-edit-series-active')),
      );
      await tester.tap(
        find.byKey(const ValueKey('schedule-plan-row-edit-series-active')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('preferred-schedule-save')),
      );
      await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('schedule-plan-preview-and-create')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('педагог уже занят'), findsOneWidget);
      expect(
        api.idempotentRequests.where(
          (request) => request.path == '/crm/schedule-plans/plan-active',
        ),
        isEmpty,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('schedule-plan-fix-row-0-педагог уже занят-all'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Изменить набор дней'), findsOneWidget);
      expect(find.text('16:00').hitTestable(), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('preferred-schedule-save')),
      );
      await tester.tap(find.byKey(const ValueKey('preferred-schedule-save')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('schedule-plan-preview-and-create')),
      );
      await tester.pumpAndSettle();

      expect(
        api.postRequests.where(
          (request) =>
              request.path ==
              '/crm/schedule-plans/plan-active/constraints/preview',
        ),
        hasLength(2),
      );
      final update = api.idempotentRequests.singleWhere(
        (request) => request.path == '/crm/schedule-plans/plan-active',
      );
      expect((update.data['rows'] as List).single['seriesId'], 'series-active');
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('end requires reason, preview and confirmed idempotent commit', (
    tester,
  ) async {
    final api = _api(plans: const [_activePlan], mutateSchedulePlanOnEnd: true);
    await _pump(tester, api);

    await tester.tap(
      find.byKey(const ValueKey('schedule-plan-end-plan-active')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('schedule-plan-end-reason')),
      'Клиент завершил занятия',
    );
    await tester.tap(find.byKey(const Key('schedule-plan-end-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-plan-end-impact')), findsOneWidget);
    expect(find.textContaining('Будут отменены: 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('schedule-plan-end-submit')));
    await tester.pumpAndSettle();

    final end = api.idempotentRequests.singleWhere(
      (request) => request.path == '/crm/schedule-plans/plan-active/end',
    );
    expect(end.data['reasonText'], 'Клиент завершил занятия');
    expect(end.data['previewToken'], 'schedule-plan-preview-token');
    expect(end.data['confirm'], true);
    expect(
      find.byKey(const ValueKey('schedule-plan-end-plan-active')),
      findsNothing,
    );
    expect(find.text('Завершено'), findsOneWidget);
    expect(find.text('Индивидуальный вокал'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-plan-end-history-plan-active')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Причина: Клиент завершил занятия'),
      findsOneWidget,
    );
    expect(
      api.getCalls
          .where((request) => request.path == '/crm/schedule-plans')
          .length,
      greaterThanOrEqualTo(2),
    );
    await tester.pump(const Duration(seconds: 4));
  });
}

FakeCardApiClient _api({
  List<Map<String, dynamic>>? plans,
  Map<String, dynamic>? timelinePage,
  List<Map<String, dynamic>> constraintPreviews = const [],
  bool mutateSchedulePlanOnCreate = false,
  bool mutateSchedulePlanOnEnd = false,
}) => FakeCardApiClient(
  role: 'manager',
  branches: const [
    {'id': 'branch-1', 'name': 'Сокол'},
  ],
  teachers: const [
    {
      'id': 'teacher-1',
      'firstName': 'Мария',
      'lastName': 'Иванова',
      'status': 'active',
      'assignedBranches': [
        {'id': 'branch-1', 'name': 'Сокол'},
      ],
    },
    {
      'id': 'teacher-2',
      'firstName': 'Пётр',
      'lastName': 'Сидоров',
      'status': 'active',
      'assignedBranches': [
        {'id': 'branch-1', 'name': 'Сокол'},
      ],
    },
  ],
  rooms: const [
    {'id': 'room-1', 'branchId': 'branch-1', 'name': 'Класс 1'},
    {'id': 'room-2', 'branchId': 'branch-1', 'name': 'Класс 2'},
  ],
  schedulePlans: plans ?? const [_activePlan, _groupPlan, _endedPlan],
  mutateSchedulePlanOnCreate: mutateSchedulePlanOnCreate,
  mutateSchedulePlanOnEnd: mutateSchedulePlanOnEnd,
  schedulePlanConstraintPreviews: constraintPreviews,
  studentLessonTimelinePage: timelinePage ?? _timelinePage(),
);

Future<void> _pump(
  WidgetTester tester,
  FakeCardApiClient api, {
  double width = 840,
  double textScale = 1,
  List<Map<String, dynamic>> fallbackLessons = const [],
  String? groupId,
  String? subjectName,
  List<GroupScheduleMemberOption> groupMembers = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: ThemeData(
          platform: width >= 840
              ? TargetPlatform.windows
              : TargetPlatform.android,
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1000),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: RecurringSchedulePlanSection(
                studentId: groupId == null ? 'student-1' : null,
                groupId: groupId,
                subjectName: subjectName,
                groupMembers: groupMembers,
                fallbackLessons: fallbackLessons,
                branches: api.branches,
                defaultBranchId: 'branch-1',
                subscriptions: const [
                  {'id': 'subscription-1', 'label': '12 занятий'},
                ],
                canWrite: true,
                onChanged: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (groupId == null &&
      find
          .byKey(const PageStorageKey('schedule-plan-expansion-plan-active'))
          .evaluate()
          .isNotEmpty) {
    await _expandPlan(tester, 'plan-active');
  }
}

Future<void> _expandPlan(WidgetTester tester, String id) async {
  final tile = find.byKey(PageStorageKey('schedule-plan-expansion-$id'));
  await tester.ensureVisible(tile);
  await tester.tap(
    find.descendant(of: tile, matching: find.byType(ListTile)).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _chooseReferences(WidgetTester tester) async {
  await _chooseSearchable(
    tester,
    const ValueKey('preferred-schedule-teacher'),
    'Мария Иванова',
  );
  await _chooseSearchable(
    tester,
    const ValueKey('preferred-schedule-room'),
    'Класс 1',
  );
  await tester.ensureVisible(
    find.byKey(const ValueKey('schedule-plan-settlement-type')),
  );
  await tester.tap(find.byKey(const ValueKey('schedule-plan-settlement-type')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Бесплатное занятие').last);
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('schedule-plan-compensation-rule')),
    findsNothing,
  );
}

Future<void> _chooseSearchable(
  WidgetTester tester,
  Key field,
  String option,
) async {
  await tester.ensureVisible(find.byKey(field));
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, option).hitTestable());
  await tester.pumpAndSettle();
}
