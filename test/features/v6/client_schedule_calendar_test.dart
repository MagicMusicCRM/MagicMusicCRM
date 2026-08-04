import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_schedule_calendar.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../crm/client_card/card_fake_api.dart';

const _branches = [
  {'id': 'branch-a', 'name': 'Сокол', 'utcOffsetMinutes': 180},
  {'id': 'branch-b', 'name': 'Центр', 'utcOffsetMinutes': 180},
];

const _lessons = [
  {
    'id': 'lesson-selected',
    'studentId': 'student-1',
    'studentName': 'Анна Смирнова',
    'branchId': 'branch-a',
    'scheduledAt': '2026-08-04T12:00:00.000Z',
    'durationMinutes': 60,
    'status': 'scheduled',
    'lifecycleState': 'scheduled',
    'isTrial': true,
    'conflictTypes': ['room_overlap'],
  },
  {
    'id': 'lesson-other',
    'studentId': 'student-2',
    'studentName': 'Иван Петров',
    'branchId': 'branch-a',
    'scheduledAt': '2026-08-04T13:00:00.000Z',
    'durationMinutes': 45,
    'status': 'completed',
    'lifecycleState': 'successfully_completed',
    'isTrial': false,
    'conflictTypes': <String>[],
  },
];

Widget _calendarApp(
  FakeCardApiClient api, {
  ContextViewState? initial,
  ValueChanged<ContextViewState>? onChanged,
  TargetPlatform? platform,
  bool active = true,
}) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(api),
      crmRealtimeProvider.overrideWith(
        (ref) => const Stream<CrmChangedEvent>.empty(),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClientScheduleCalendar(
            clientType: 'student',
            clientId: 'student-1',
            clientName: 'Анна Смирнова',
            branches: _branches,
            defaultBranchId: 'branch-a',
            canRead: true,
            active: active,
            initialViewState: initial,
            onViewStateChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('viewport is finite for Month, Week and Day', () {
    final date = DateTime(2026, 8, 4);
    final month = clientCalendarViewport(CalendarView.month, date);
    final week = clientCalendarViewport(CalendarView.week, date);
    final day = clientCalendarViewport(CalendarView.day, date);

    expect(
      month.endExclusive.difference(month.start).inDays,
      inInclusiveRange(35, 42),
    );
    expect(week.endExclusive.difference(week.start).inDays, 7);
    expect(day.endExclusive.difference(day.start).inDays, 1);
  });

  test('relation is typed and does not infer from display names', () {
    expect(
      lessonBelongsToClient(
        const {'student_id': 'student-1', 'lead_id': 'lead-1'},
        clientType: 'student',
        clientId: 'student-1',
      ),
      isTrue,
    );
    expect(
      lessonBelongsToClient(
        const {'student_name': 'Анна Смирнова'},
        clientType: 'student',
        clientId: 'student-1',
      ),
      isFalse,
    );
    expect(
      lessonBelongsToClient(
        const {'student_id': 'student-1', 'lead_id': 'lead-1'},
        clientType: 'lead',
        clientId: 'lead-1',
      ),
      isTrue,
    );
  });

  testWidgets('hidden client section does not prefetch the viewport', (
    tester,
  ) async {
    final api = FakeCardApiClient(scheduleMatrix: _lessons);
    await tester.pumpWidget(_calendarApp(api, active: false));
    await tester.pumpAndSettle();
    expect(
      api.getCalls.where((call) => call.path == '/crm/schedule/matrix'),
      isEmpty,
    );

    await tester.pumpWidget(_calendarApp(api));
    await tester.pumpAndSettle();
    expect(
      api.getCalls.where((call) => call.path == '/crm/schedule/matrix'),
      isNotEmpty,
    );
  });

  for (final platform in const [
    TargetPlatform.windows,
    TargetPlatform.android,
  ]) {
    testWidgets('$platform restores scope and renders relation legend', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        platform == TargetPlatform.android ? 412 : 1200,
        900,
      );
      addTearDown(tester.view.reset);
      final api = FakeCardApiClient(scheduleMatrix: _lessons);
      await tester.pumpWidget(
        _calendarApp(
          api,
          initial: ContextViewState(
            filters: const {
              'section': 'lessons',
              'clientCalendarMode': 'day',
              'clientCalendarBranchId': 'branch-a',
            },
            date: DateTime(2026, 8, 4),
          ),
          platform: platform,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Календарь занятий'), findsOneWidget);
      expect(find.text('Клиент карточки'), findsOneWidget);
      expect(find.text('Другие клиенты'), findsOneWidget);
      expect(find.text('Пробное'), findsOneWidget);
      expect(find.text('Конфликт'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('client-calendar-grid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('client-calendar-lesson-lesson-selected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('client-calendar-lesson-lesson-other')),
        findsOneWidget,
      );

      final matrixCalls = api.getCalls
          .where((call) => call.path == '/crm/schedule/matrix')
          .toList();
      expect(matrixCalls, hasLength(2));
      final matrix = matrixCalls.lastWhere(
        (call) => !call.query.containsKey('studentId'),
      );
      final selectedMatrix = matrixCalls.lastWhere(
        (call) => call.query['studentId'] == 'student-1',
      );
      expect(matrix.query['branchId'], 'branch-a');
      expect(matrix.query['limit'], 500);
      expect(matrix.query.containsKey('studentId'), isFalse);
      expect(matrix.query.containsKey('leadId'), isFalse);
      expect(selectedMatrix.query['branchId'], 'branch-a');
      final from = DateTime.parse(matrix.query['from'] as String);
      final to = DateTime.parse(matrix.query['to'] as String);
      expect(to.difference(from).inDays, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mode and branch changes publish restorable view state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(scheduleMatrix: _lessons);
    final states = <ContextViewState>[];
    await tester.pumpWidget(
      _calendarApp(
        api,
        initial: ContextViewState(
          filters: const {
            'section': 'lessons',
            'clientCalendarMode': 'day',
            'clientCalendarBranchId': 'branch-a',
          },
          date: DateTime(2026, 8, 4),
        ),
        onChanged: states.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(states.last.filters['clientCalendarMode'], 'week');
    final weekCall = api.getCalls.lastWhere(
      (call) => call.path == '/crm/schedule/matrix',
    );
    expect(
      DateTime.parse(
        weekCall.query['to'] as String,
      ).difference(DateTime.parse(weekCall.query['from'] as String)).inDays,
      7,
    );

    await tester.tap(find.byKey(const ValueKey('client-calendar-branch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Центр').last);
    await tester.pumpAndSettle();
    expect(states.last.filters['clientCalendarBranchId'], 'branch-b');
    final branchCall = api.getCalls.lastWhere(
      (call) => call.path == '/crm/schedule/matrix',
    );
    expect(branchCall.query['branchId'], 'branch-b');
  });

  testWidgets('lesson link stores calendar source state for workspace Back', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(scheduleMatrix: _lessons);
    final controller = WorkspaceController(
      accountId: 'account-1',
      initialLink: EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'student-1',
        variant: 'student',
      ),
      sharedScope: const WorkspaceSharedScope(
        session: Object(),
        cache: Object(),
        realtime: Object(),
      ),
    );
    addTearDown(controller.dispose);
    const snapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'admin',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic', 'schedule.lesson.write'},
      scopes: {'schedule': 'branch'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceNavigationScope(
              controller: controller,
              isDesktop: true,
              child: SingleChildScrollView(
                child: ClientScheduleCalendar(
                  clientType: 'student',
                  clientId: 'student-1',
                  clientName: 'Анна Смирнова',
                  branches: _branches,
                  defaultBranchId: 'branch-a',
                  canRead: true,
                  initialViewState: ContextViewState(
                    filters: const {
                      'section': 'lessons',
                      'clientCalendarMode': 'day',
                      'clientCalendarBranchId': 'branch-a',
                    },
                    date: DateTime(2026, 8, 4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedLesson = find.byKey(
      const ValueKey('client-calendar-lesson-lesson-selected'),
    );
    await tester.ensureVisible(selectedLesson);
    await tester.pumpAndSettle();
    await tester.tap(selectedLesson);
    await tester.pumpAndSettle();

    final tab = controller.state.activeTab;
    expect(tab.routeStack, hasLength(2));
    expect(tab.currentRoute.link.entityType, EntityLinkType.lesson);
    final source = tab.routeStack.first.viewState;
    expect(source.filters['section'], 'lessons');
    expect(source.filters['clientCalendarMode'], 'day');
    expect(source.filters['clientCalendarBranchId'], 'branch-a');
    expect(source.date, DateTime(2026, 8, 4));
  });

  testWidgets('Android lesson drilldown pushes schedule and keeps card Back', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(scheduleMatrix: _lessons);
    var openedQuery = <String, String>{};
    final router = GoRouter(
      initialLocation: '/students/student-1',
      routes: [
        GoRoute(
          path: '/students/:id',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: ClientScheduleCalendar(
                clientType: 'student',
                clientId: 'student-1',
                clientName: 'Анна Смирнова',
                branches: _branches,
                defaultBranchId: 'branch-a',
                canRead: true,
                initialViewState: ContextViewState(
                  filters: const {
                    'section': 'lessons',
                    'clientCalendarMode': 'day',
                    'clientCalendarBranchId': 'branch-a',
                  },
                  date: DateTime(2026, 8, 4),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/admin',
          builder: (_, state) {
            openedQuery = state.uri.queryParameters;
            return const Scaffold(body: Text('Расписание host'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    const snapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'admin',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic', 'schedule.lesson.write'},
      scopes: {'schedule': 'branch'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: MaterialApp.router(
          theme: ThemeData(platform: TargetPlatform.android),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedLesson = find.byKey(
      const ValueKey('client-calendar-lesson-lesson-selected'),
    );
    await tester.ensureVisible(selectedLesson);
    await tester.pumpAndSettle();
    await tester.tap(selectedLesson);
    await tester.pumpAndSettle();

    expect(find.text('Расписание host'), findsOneWidget);
    expect(openedQuery['entityType'], 'lesson');
    expect(openedQuery['entityId'], 'lesson-selected');
    expect(openedQuery['focus'], 'lesson');
    expect(openedQuery['f.clientId'], 'student-1');
    expect(openedQuery['f.branchId'], 'branch-a');
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('client-calendar-grid')), findsOneWidget);
  });
}
