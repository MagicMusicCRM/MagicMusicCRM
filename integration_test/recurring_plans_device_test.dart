import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';

import '../test/features/crm/client_card/card_fake_api.dart';
import 'evidence_screenshot.dart';

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
  'endedByName': 'Мария Управляющая',
  'endReason': 'Клиент завершил обучение',
  'rows': <Map<String, dynamic>>[],
};

Map<String, dynamic> _timelineItem({
  required String id,
  required String scheduledAt,
  String lifecycleState = 'scheduled',
  String originKind = 'generated',
  String? planId = 'plan-active',
  String? seriesId = 'series-active',
  String? predecessorId,
  String? successorId,
  bool covered = false,
}) => {
  'id': id,
  'version': 1,
  'scheduledAt': scheduledAt,
  'durationMinutes': 60,
  'lifecycleState': lifecycleState,
  'student': {'id': 'student-1', 'name': 'Анна Смирнова'},
  'group': null,
  'teacher': {'id': 'teacher-1', 'name': 'Мария Иванова'},
  'room': {'id': 'room-1', 'name': 'Класс 1'},
  'branch': {'id': 'branch-1', 'name': 'Сокол'},
  'origin': {'kind': originKind, 'planId': planId, 'seriesId': seriesId},
  'settlement': {
    'coveredBySubscription': covered,
    'settlementTypeKey': covered ? 'subscription' : null,
  },
  'reschedule': {
    'predecessorId': predecessorId,
    'successorId': successorId,
    'actionableLessonId': successorId ?? id,
  },
};

Map<String, dynamic> _timelinePage(
  List<Map<String, dynamic>> items, {
  bool hasPrevious = false,
  bool hasNext = false,
  String? previousCursor,
  String? nextCursor,
}) => {
  'items': items,
  'hasPrevious': hasPrevious,
  'hasNext': hasNext,
  'previousCursor': previousCursor,
  'nextCursor': nextCursor,
};

class _PagingPlanApi extends FakeCardApiClient {
  _PagingPlanApi()
    : super(role: 'manager', schedulePlans: const [_activePlan, _endedPlan]);

  static final _first = <String, dynamic>{
    'items': [
      _timelineItem(
        id: 'lesson-device-manual',
        scheduledAt: '2026-08-05T13:00:00.000Z',
        originKind: 'manual',
        planId: null,
        seriesId: null,
      ),
      _timelineItem(
        id: 'lesson-device-plan-a',
        scheduledAt: '2026-08-06T13:00:00.000Z',
        planId: 'plan-a',
        seriesId: 'series-a',
      ),
      _timelineItem(
        id: 'lesson-device-plan-b',
        scheduledAt: '2026-08-07T13:00:00.000Z',
        planId: 'plan-b',
        seriesId: 'series-b',
        covered: true,
      ),
      _timelineItem(
        id: 'lesson-device-cancelled',
        scheduledAt: '2026-08-08T13:00:00.000Z',
        lifecycleState: 'cancelled',
        successorId: 'lesson-device-successor',
      ),
    ],
    'hasPrevious': false,
    'hasNext': true,
    'previousCursor': null,
    'nextCursor': 'device-next',
  };

  static final _next = <String, dynamic>{
    'items': [
      _timelineItem(
        id: 'lesson-device-successor',
        scheduledAt: '2026-08-14T13:00:00.000Z',
        predecessorId: 'lesson-device-cancelled',
      ),
    ],
    'hasPrevious': true,
    'hasNext': false,
    'previousCursor': 'device-previous',
    'nextCursor': null,
  };

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
      return Map<String, dynamic>.from(
            query['cursor'] == 'device-next' ? _next : _first,
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recurring plan lifecycle keeps card state on device', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final api = FakeCardApiClient(
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
      schedulePlans: const [_activePlan, _endedPlan],
      mutateSchedulePlanOnEnd: true,
      studentLessonTimelinePage: _timelinePage([
        _timelineItem(
          id: 'lesson-active',
          scheduledAt: '2026-08-07T13:00:00.000Z',
          covered: true,
        ),
      ]),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AppTheme.production,
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: RecurringSchedulePlanSection(
                    studentId: 'student-1',
                    fallbackLessons: const [],
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Индивидуальный вокал'), findsOneWidget);
    expect(find.byKey(const Key('student-lesson-timeline')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('Абонемент') ?? false),
      ),
      findsOneWidget,
    );
    expect(find.text('Завершённое фортепиано'), findsOneWidget);
    await captureEvidence(tester, 'recurring-plan-active-timeline');
    await _expandPlan(tester, 'plan-active');
    expect(find.text('Завершённое фортепиано'), findsOneWidget);

    final edit = find.byKey(
      const ValueKey('schedule-plan-row-edit-series-active'),
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Изменить строку'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Индивидуальный вокал'), findsOneWidget);
    expect(find.text('Мария Иванова'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('schedule-plan-add')));
    await tester.tap(find.byKey(const Key('schedule-plan-add')));
    await tester.pumpAndSettle();
    await _chooseReferences(tester);
    await captureEvidence(tester, 'recurring-plan-editor-required-fields');
    await _saveEditor(tester);
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
    await _saveEditor(tester);
    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();
    expect(
      api.idempotentRequests.where(
        (request) => request.path == '/crm/schedule-plans',
      ),
      hasLength(1),
    );

    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await _saveEditor(tester);
    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();
    expect(
      api.postRequests.where(
        (request) =>
            request.path ==
            '/crm/schedule-plans/plan-active/constraints/preview',
      ),
      hasLength(1),
    );
    expect(
      api.idempotentRequests.where(
        (request) => request.path == '/crm/schedule-plans/plan-active',
      ),
      hasLength(1),
    );

    final end = find.byKey(const ValueKey('schedule-plan-end-plan-active'));
    await tester.ensureVisible(end);
    await tester.tap(end);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('schedule-plan-end-reason')),
      'Клиент завершил занятия',
    );
    final submit = find.byKey(const Key('schedule-plan-end-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-plan-end-impact')), findsOneWidget);
    await captureEvidence(tester, 'recurring-plan-end-impact');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      api.idempotentRequests.where(
        (request) => request.path == '/crm/schedule-plans/plan-active/end',
      ),
      hasLength(1),
    );
    expect(
      find.byKey(const ValueKey('schedule-plan-end-plan-active')),
      findsNothing,
    );
    expect(find.text('Завершено'), findsNWidgets(2));
    if (find
        .byKey(const ValueKey('schedule-plan-end-history-plan-active'))
        .evaluate()
        .isEmpty) {
      await tester.ensureVisible(find.text('Индивидуальный вокал'));
      await tester.tap(find.text('Индивидуальный вокал'));
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(const ValueKey('schedule-plan-end-history-plan-active')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Причина: Клиент завершил занятия'),
      findsOneWidget,
    );
    await captureEvidence(tester, 'recurring-plan-ended-history');
    expect(tester.takeException(), isNull);
    debugPrint('V7_RECURRING_PLANS_DEVICE_PASS');
  });

  testWidgets('canonical timeline pages and final row removal on device', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final api = _PagingPlanApi();
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AppTheme.production,
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: RecurringSchedulePlanSection(
                    studentId: 'student-1',
                    fallbackLessons: const [],
                    branches: const [],
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Завершённое фортепиано'), findsOneWidget);
    expect(find.byKey(const Key('student-lesson-timeline')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-plan-tray-plan-active')),
      findsNothing,
    );
    for (final id in [
      'lesson-device-manual',
      'lesson-device-plan-a',
      'lesson-device-plan-b',
      'lesson-device-cancelled',
    ]) {
      expect(find.byKey(ValueKey('student-timeline-$id')), findsOneWidget);
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('Разовое занятие') ?? false),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('student-timeline-lesson-device-successor')),
      findsNothing,
    );
    await captureEvidence(tester, 'student-lesson-timeline-page-1');

    await tester.tap(find.byKey(const Key('student-lesson-timeline-next')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('student-timeline-lesson-device-successor')),
      findsOneWidget,
    );
    expect(api.getCalls.last.query, {
      'cursor': 'device-next',
      'direction': 'next',
      'limit': 24,
    });
    await captureEvidence(tester, 'student-lesson-timeline-page-2');

    await tester.tap(find.byKey(const Key('student-lesson-timeline-previous')));
    await tester.pumpAndSettle();
    expect(api.getCalls.last.query, {
      'cursor': 'device-previous',
      'direction': 'previous',
      'limit': 24,
    });

    await _expandPlan(tester, 'plan-active');
    final remove = find.byKey(const ValueKey('remove-plan-row-series-active'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('schedule-plan-row-removal-reason')),
      'Клиент меняет расписание',
    );
    await tester.tap(find.byKey(const Key('schedule-plan-row-removal-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Будет отменено будущих занятий: 3'), findsOneWidget);
    expect(find.text('История проведённых занятий сохранится'), findsOneWidget);
    expect(
      find.text(
        'Это последняя действующая строка. Расписание будет завершено.',
      ),
      findsOneWidget,
    );
    await captureEvidence(tester, 'schedule-plan-final-row-impact');
    await tester.tap(
      find.byKey(const Key('schedule-plan-row-removal-confirm')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('schedule-plan-row-removal-submit')));
    await tester.pumpAndSettle();
    expect(remove, findsNothing);
    expect(tester.takeException(), isNull);
    debugPrint('V7_STUDENT_LESSON_TIMELINE_DEVICE_PASS');
  });

  testWidgets('individual plan reads back mixed rows on device', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final api = FakeCardApiClient(
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
      mutateSchedulePlanOnCreate: true,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AppTheme.production,
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: RecurringSchedulePlanSection(
                    studentId: 'student-1',
                    fallbackLessons: const [],
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('schedule-plan-add')));
    await tester.pumpAndSettle();
    final firstDay = DateTime.now().weekday;
    final secondDay = firstDay == 7 ? 1 : firstDay + 1;
    final thirdDay = secondDay == 7 ? 1 : secondDay + 1;
    await tester.tap(
      find.byKey(ValueKey('preferred-schedule-weekday-$secondDay')),
    );
    await _chooseReferences(tester);
    await _saveEditor(tester);

    await tester.tap(find.byKey(const Key('schedule-plan-add-row-group')));
    await tester.pumpAndSettle();
    for (final weekday in [firstDay, secondDay, thirdDay]) {
      await tester.tap(
        find.byKey(ValueKey('preferred-schedule-weekday-$weekday')),
      );
    }
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
    await _saveEditor(tester);
    expect(
      find.byKey(const ValueKey('schedule-plan-row-group-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-plan-row-group-1')),
      findsOneWidget,
    );
    await captureEvidence(tester, 'individual-plan-mixed-row-review');

    await tester.tap(find.byKey(const Key('schedule-plan-preview-and-create')));
    await tester.pumpAndSettle();
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
    expect(find.text('Мария Иванова'), findsNWidgets(2));
    expect(find.text('Класс 1'), findsNWidgets(2));
    expect(find.text('Пётр Сидоров'), findsOneWidget);
    expect(find.text('Класс 2'), findsOneWidget);
    expect(
      api.getCalls
          .where((request) => request.path == '/crm/schedule-plans')
          .length,
      greaterThanOrEqualTo(2),
    );
    await captureEvidence(tester, 'individual-plan-mixed-row-readback');
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
    debugPrint('V7_INDIVIDUAL_PLAN_MIXED_ROWS_DEVICE_PASS');
  });
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
  final menuItem = find.ancestor(
    of: find.text(option).last,
    matching: find.byType(MenuItemButton),
  );
  expect(menuItem, findsOneWidget);
  tester.widget<MenuItemButton>(menuItem).onPressed?.call();
  await tester.pumpAndSettle();
}

Future<void> _saveEditor(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('preferred-schedule-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}
