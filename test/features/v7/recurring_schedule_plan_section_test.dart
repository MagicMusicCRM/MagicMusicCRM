import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
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

const _groupPlan = {
  'id': 'plan-group',
  'kind': 'group',
  'title': 'Вокальная группа',
  'groupId': 'group-1',
  'activeFrom': '2026-08-02',
  'activeUntil': '2026-12-31',
  'status': 'active',
  'version': 1,
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

Map<String, dynamic> _tray(String planId, String lessonId) => {
  'planId': planId,
  'items': [
    {
      'id': lessonId,
      'scheduledAt': '2026-08-07T13:00:00.000Z',
      'localDate': '2026-08-07',
      'localTime': '16:00',
      'state': 'scheduled',
      'settlementMarkers': [
        {
          'key': 'paid_absence',
          'label': 'Оплачиваемый пропуск',
          'colorToken': 'blue',
        },
      ],
      'relationMarker': 'none',
      'predecessorId': null,
      'successorId': null,
      'teacher': {'id': 'teacher-1', 'name': 'Мария Иванова'},
      'room': {'id': 'room-1', 'name': 'Класс 1'},
    },
  ],
  'hasPrevious': false,
  'hasNext': false,
  'previousCursor': null,
  'nextCursor': null,
};

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final width in const [360.0, 840.0, 1200.0]) {
    testWidgets('plans render active/group/ended at ${width.toInt()}', (
      tester,
    ) async {
      final api = _api();
      await _pump(tester, api, width: width, textScale: 1.25);

      expect(find.text('Постоянные расписания'), findsOneWidget);
      expect(find.text('Индивидуальный вокал'), findsOneWidget);
      expect(find.text('Вокальная группа'), findsOneWidget);
      expect(find.text('Мария Иванова'), findsWidgets);
      expect(find.text('Класс 1'), findsWidgets);
      expect(
        find.byKey(const ValueKey('schedule-plan-tray-plan-active')),
        findsOneWidget,
      );
      expect(find.text('Завершённые (1)'), findsOneWidget);
      expect(find.text('Завершённое фортепиано'), findsNothing);

      await tester.ensureVisible(find.text('Завершённые (1)'));
      await tester.tap(find.text('Завершённые (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Завершённое фортепиано'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no plan keeps actual lessons visible', (tester) async {
    final api = FakeCardApiClient(role: 'manager');
    await _pump(
      tester,
      api,
      fallbackLessons: const [
        {
          'id': 'legacy-lesson',
          'scheduledAt': '2026-08-08T12:00:00.000Z',
          'lifecycleState': 'scheduled',
          'teacherName': 'Ирина Орлова',
        },
      ],
    );

    expect(find.text('Постоянных расписаний пока нет'), findsOneWidget);
    expect(find.byKey(const Key('client-lesson-date-tray')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('client-lesson-legacy-lesson')),
      findsOneWidget,
    );
  });

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
    await tester.tap(find.text('Мария Иванова').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пётр Сидоров').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Класс 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Класс 2').last);
    await tester.pumpAndSettle();
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
    expect(
      api.postRequests.where(
        (request) => request.path == '/crm/schedule-plans/constraints/preview',
      ),
      hasLength(1),
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
    final update = api.idempotentRequests.singleWhere(
      (request) => request.path == '/crm/schedule-plans/plan-active',
    );
    expect(update.data['expectedVersion'], 1);
    expect((update.data['rows'] as List).single['seriesId'], 'series-active');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('end requires reason, preview and confirmed idempotent commit', (
    tester,
  ) async {
    final api = _api(plans: const [_activePlan]);
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
    await tester.pump(const Duration(seconds: 4));
  });
}

FakeCardApiClient _api({List<Map<String, dynamic>>? plans}) =>
    FakeCardApiClient(
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
      schedulePlanTrays: {
        'plan-active': _tray('plan-active', 'lesson-active'),
        'plan-group': _tray('plan-group', 'lesson-group'),
        'plan-ended': _tray('plan-ended', 'lesson-ended'),
      },
    );

Future<void> _pump(
  WidgetTester tester,
  FakeCardApiClient api, {
  double width = 840,
  double textScale = 1,
  List<Map<String, dynamic>> fallbackLessons = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1000),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: RecurringSchedulePlanSection(
                studentId: 'student-1',
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
}

Future<void> _chooseReferences(WidgetTester tester) async {
  await tester.tap(find.text('Выберите педагога'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Мария Иванова').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Выберите аудиторию'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Класс 1').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('schedule-plan-settlement-type')),
  );
  await tester.tap(find.byKey(const ValueKey('schedule-plan-settlement-type')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Бесплатное занятие').last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('schedule-plan-compensation-rule')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Не оплачивать').last);
  await tester.pumpAndSettle();
}
