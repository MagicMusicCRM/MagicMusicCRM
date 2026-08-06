import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

import '../crm/client_card/card_fake_api.dart';

const _branches = [
  {'id': 'branch-a', 'name': 'Сокол', 'utcOffsetMinutes': 180},
  {'id': 'branch-b', 'name': 'Центр', 'utcOffsetMinutes': 180},
];

const _rooms = [
  {'id': 'room-a', 'name': 'Класс 1', 'branchId': 'branch-a'},
  {'id': 'room-b', 'name': 'Класс 2', 'branchId': 'branch-b'},
];

const _lessons = [
  {
    'id': 'lesson-selected',
    'studentId': 'student-1',
    'studentName': 'Анна Смирнова',
    'teacherId': 'teacher-1',
    'teacherName': 'Мария Педагог',
    'branchId': 'branch-a',
    'branchName': 'Сокол',
    'roomId': 'room-a',
    'roomName': 'Класс 1',
    'scheduledAt': '2026-08-04T07:00:00.000Z',
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
    'teacherId': 'teacher-1',
    'teacherName': 'Мария Педагог',
    'branchId': 'branch-a',
    'branchName': 'Сокол',
    'roomId': 'room-a',
    'roomName': 'Класс 1',
    'scheduledAt': '2026-08-04T09:00:00.000Z',
    'durationMinutes': 60,
    'status': 'completed',
    'lifecycleState': 'successfully_completed',
    'isTrial': false,
    'conflictTypes': <String>[],
  },
  {
    'id': 'lesson-next-day',
    'studentId': 'student-2',
    'studentName': 'Иван Петров',
    'teacherId': 'teacher-1',
    'teacherName': 'Мария Педагог',
    'branchId': 'branch-a',
    'branchName': 'Сокол',
    'roomId': 'room-a',
    'roomName': 'Класс 1',
    'scheduledAt': '2026-08-05T07:00:00.000Z',
    'durationMinutes': 60,
    'status': 'scheduled',
    'lifecycleState': 'scheduled',
    'isTrial': false,
    'conflictTypes': <String>[],
  },
];

ContextViewState _dayState() => ContextViewState(
  filters: const {
    'section': 'lessons',
    'clientCalendarMode': 'day',
    'clientCalendarBranchId': 'branch-a',
    'dayMode': 'byRoom',
  },
  date: DateTime(2026, 8, 4),
);

Widget _calendarApp(
  FakeCardApiClient api, {
  ContextViewState? initial,
  ValueChanged<ContextViewState>? onChanged,
  bool active = true,
  bool clientContext = true,
}) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(api),
      crmRealtimeProvider.overrideWith(
        (ref) => const Stream<CrmChangedEvent>.empty(),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: SizedBox(
          height: 760,
          child: ScheduleWidget(
            title: 'Календарь занятий',
            clientType: clientContext ? 'student' : null,
            clientId: clientContext ? 'student-1' : null,
            clientName: clientContext ? 'Анна Смирнова' : null,
            initialBranchId: 'branch-a',
            canWrite: false,
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

  testWidgets('inactive client section does not prefetch schedule', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      branches: _branches,
      rooms: _rooms,
      scheduleMatrix: _lessons,
    );
    await tester.pumpWidget(_calendarApp(api, active: false));
    await tester.pumpAndSettle();

    expect(
      api.getCalls.where((call) => call.path == '/crm/schedule/matrix'),
      isEmpty,
    );
  });

  testWidgets(
    'client context reuses the canonical Day model and relation marks',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);
      final api = FakeCardApiClient(
        branches: _branches,
        rooms: _rooms,
        scheduleMatrix: _lessons,
      );
      await tester.pumpWidget(_calendarApp(api, initial: _dayState()));
      await tester.pumpAndSettle();

      expect(find.text('Календарь занятий'), findsOneWidget);
      expect(find.text('Анна Смирнова'), findsWidgets);
      expect(find.text('Другие клиенты'), findsOneWidget);
      expect(find.byType(ScheduleDayCanvas), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-selected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-other')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.person_pin_circle_outlined), findsWidgets);
      expect(find.byIcon(Icons.people_outline_rounded), findsWidgets);
      expect(find.text('Создать занятие'), findsNothing);

      final matrixCalls = api.getCalls
          .where((call) => call.path == '/crm/schedule/matrix')
          .toList();
      expect(matrixCalls, isNotEmpty);
      for (final call in matrixCalls) {
        expect(call.query['branchId'], 'branch-a');
        expect(call.query.containsKey('studentId'), isFalse);
        expect(call.query.containsKey('leadId'), isFalse);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('schedule search keeps the view and marks Day Week Month', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      branches: _branches,
      rooms: _rooms,
      scheduleMatrix: _lessons,
    );
    await tester.pumpWidget(
      _calendarApp(api, initial: _dayState(), clientContext: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Найти занятие'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Анна Смирнова');
    await tester.tap(find.widgetWithText(FilledButton, 'Найти'));
    await tester.pump();

    expect(find.text('Поиск: анна смирнова'), findsOneWidget);
    expect(
      api.getCalls.any((call) => call.path == '/crm/clients/search'),
      isTrue,
    );
    expect(
      api.getCalls.any(
        (call) =>
            call.path == '/crm/schedule/matrix' &&
            call.query['studentId'] == 'student-1',
      ),
      isTrue,
    );
    expect(_lessonBorder(tester, 'lesson-selected'), AppColor.gold);
    await tester.pump(const Duration(seconds: 4));
    expect(_lessonBorder(tester, 'lesson-selected'), AppColor.success);
    expect(_lessonBorder(tester, 'lesson-other'), AppColor.text2);

    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-week-view')), findsOneWidget);
    expect(_lessonBorder(tester, 'lesson-selected'), AppColor.success);
    expect(_lessonBorder(tester, 'lesson-other'), AppColor.text2);

    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();
    expect(_monthDayBorder(tester, '2026-08-04'), AppColor.success);
    expect(_monthDayBorder(tester, '2026-08-05'), isNot(AppColor.success));

    await tester.tap(find.byTooltip('Поиск: анна смирнова'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Очистить'));
    await tester.pump();
    expect(find.text('Поиск: анна смирнова'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode and branch publish one restorable schedule state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final states = <ContextViewState>[];
    final api = FakeCardApiClient(
      branches: _branches,
      rooms: _rooms,
      scheduleMatrix: _lessons,
    );
    await tester.pumpWidget(
      _calendarApp(api, initial: _dayState(), onChanged: states.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(states.last.filters['view'], 'week');
    expect(states.last.filters['clientCalendarMode'], 'week');

    await tester.tap(
      find.byKey(const ValueKey('schedule-branch-selector-branch-a')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Центр').last);
    await tester.pumpAndSettle();
    expect(states.last.filters['branchId'], 'branch-b');
    expect(states.last.filters['clientCalendarBranchId'], 'branch-b');
  });

  testWidgets('linked lesson keeps client schedule state for workspace Back', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      branches: _branches,
      rooms: _rooms,
      scheduleMatrix: _lessons,
    );
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
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: WorkspaceNavigationScope(
              controller: controller,
              isDesktop: true,
              child: SizedBox(
                height: 760,
                child: ScheduleWidget(
                  title: 'Календарь занятий',
                  clientType: 'student',
                  clientId: 'student-1',
                  clientName: 'Анна Смирнова',
                  initialBranchId: 'branch-a',
                  canWrite: false,
                  initialViewState: _dayState(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('schedule-lesson-lesson-selected')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson-reference-Занятие')));
    await tester.pumpAndSettle();

    final tab = controller.state.activeTab;
    expect(tab.routeStack, hasLength(2));
    expect(tab.currentRoute.link.entityType, EntityLinkType.lesson);
    final source = tab.routeStack.first.viewState;
    expect(source.filters['section'], 'lessons');
    expect(source.filters['view'], 'day');
    expect(source.filters['clientCalendarBranchId'], 'branch-a');
    expect(source.date, DateTime(2026, 8, 4));
  });
}

Color _lessonBorder(WidgetTester tester, String id) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('schedule-lesson-$id')),
  );
  return ((container.decoration as BoxDecoration).border! as Border).top.color;
}

Color _monthDayBorder(WidgetTester tester, String day) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('schedule-month-day-$day')),
  );
  return ((container.decoration as BoxDecoration).border! as Border).top.color;
}
