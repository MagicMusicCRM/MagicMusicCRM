import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_teacher_timeline.dart';
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
  {
    'id': 'lesson-lead',
    'leadId': 'lead-1',
    'leadName': 'Лид Тестовый',
    'teacherId': 'teacher-1',
    'teacherName': 'Мария Педагог',
    'branchId': 'branch-a',
    'branchName': 'Сокол',
    'roomId': 'room-a',
    'roomName': 'Класс 1',
    'scheduledAt': '2026-08-04T11:00:00.000Z',
    'durationMinutes': 60,
    'status': 'scheduled',
    'lifecycleState': 'scheduled',
    'isTrial': true,
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
  EntityLink? initialLink,
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
            initialLink: initialLink,
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

  testWidgets('subscription coverage stays separate in every calendar mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      branches: _branches,
      rooms: _rooms,
      scheduleMatrix: [
        {
          ..._lessons.first,
          'reservationState': 'reserved',
          'conflictTypes': <String>[],
          'isTrial': false,
        },
        _lessons[1],
      ],
    );
    await tester.pumpWidget(
      _calendarApp(api, initial: _dayState(), clientContext: false),
    );
    await tester.pumpAndSettle();

    void expectCoverage() {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('schedule-lesson-lesson-selected')),
          matching: find.byType(LessonSubscriptionBadge),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('schedule-lesson-lesson-other')),
          matching: find.byType(LessonSubscriptionBadge),
        ),
        findsNothing,
      );
    }

    expect(_lessonBorder(tester, 'lesson-selected'), AppColor.actionBlue);
    expect(_lessonBorder(tester, 'lesson-other'), AppColor.success);
    expectCoverage();

    await tester.tap(find.text('По преподавателям'));
    await tester.pumpAndSettle();
    expect(
      _timelineLessonBorder(tester, 'lesson-selected'),
      AppColor.actionBlue,
    );
    expect(_timelineLessonBorder(tester, 'lesson-other'), AppColor.success);
    expectCoverage();

    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(_lessonBorder(tester, 'lesson-selected'), AppColor.actionBlue);
    expect(_lessonBorder(tester, 'lesson-other'), AppColor.success);
    expectCoverage();

    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();
    final monthLesson = find.byKey(
      const ValueKey('schedule-month-lesson-lesson-selected'),
    );
    final monthBox =
        tester.widget<Container>(monthLesson).decoration as BoxDecoration;
    expect((monthBox.border! as Border).left.color, AppColor.actionBlue);
    expect(
      find.descendant(
        of: monthLesson,
        matching: find.byType(LessonSubscriptionBadge),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
      final hideOthers = tester.widget<FilterChip>(
        find.byKey(const ValueKey('client-calendar-hide-others')),
      );
      expect(hideOthers.selected, isTrue);
      expect(find.text('Другие клиенты'), findsNothing);
      expect(find.byType(ScheduleDayCanvas), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-selected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-other')),
        findsNothing,
      );
      expect(find.byIcon(Icons.person_pin_circle_outlined), findsWidgets);
      expect(find.byIcon(Icons.people_outline_rounded), findsNothing);
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

      await tester.tap(
        find.byKey(const ValueKey('client-calendar-hide-others')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-other')),
        findsOneWidget,
      );
      expect(
        _lessonMarker('lesson-selected', Icons.person_pin_circle_outlined),
        findsOneWidget,
      );
      expect(
        _lessonMarker('lesson-other', Icons.people_outline_rounded),
        findsOneWidget,
      );
      expect(_lessonBorder(tester, 'lesson-selected'), AppColor.danger);
      expect(_lessonBorder(tester, 'lesson-other'), AppColor.success);

      await tester.tap(find.text('По преподавателям'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleTeacherTimeline), findsOneWidget);
      expect(
        _lessonMarker('lesson-selected', Icons.person_pin_circle_outlined),
        findsOneWidget,
      );
      expect(
        _lessonMarker('lesson-other', Icons.people_outline_rounded),
        findsOneWidget,
      );
      expect(_timelineLessonBorder(tester, 'lesson-selected'), AppColor.danger);
      expect(_timelineLessonBorder(tester, 'lesson-other'), AppColor.success);

      await tester.tap(find.text('Неделя'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-week-view')), findsOneWidget);
      expect(
        _lessonMarker('lesson-selected', Icons.person_pin_circle_outlined),
        findsOneWidget,
      );
      expect(
        _lessonMarker('lesson-other', Icons.people_outline_rounded),
        findsOneWidget,
      );
      expect(_lessonBorder(tester, 'lesson-selected'), AppColor.danger);
      expect(_lessonBorder(tester, 'lesson-other'), AppColor.success);

      await tester.tap(find.text('Месяц'));
      await tester.pumpAndSettle();
      expect(find.text('Август 2026'), findsWidgets);
      expect(find.text('августа 2026'), findsNothing);
      expect(_monthDayBorder(tester, '2026-08-04'), AppColor.success);
      expect(_monthDayBorder(tester, '2026-08-05'), isNot(AppColor.success));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canonical Schedule lead filter hides others locally and can reveal them',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);
      final api = FakeCardApiClient(
        branches: _branches,
        rooms: _rooms,
        scheduleMatrix: _lessons,
      );
      final route = EntityLink.typed(
        entityType: EntityLinkType.report,
        entityId: '__section__',
        variant: 'lesson_list',
        optionalFocus: EntityLinkFocus(
          focus: 'date',
          filter: const {
            'clientType': 'lead',
            'clientId': 'lead-1',
            'clientName': 'Лид Тестовый',
          },
        ),
      );

      await tester.pumpWidget(
        _calendarApp(
          api,
          initial: _dayState(),
          clientContext: false,
          initialLink: route,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-lead')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-other')),
        findsNothing,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('client-calendar-hide-others')),
            )
            .selected,
        isTrue,
      );
      expect(
        api.getCalls
            .where((call) => call.path == '/crm/schedule/matrix')
            .every(
              (call) =>
                  !call.query.containsKey('leadId') &&
                  !call.query.containsKey('studentId'),
            ),
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey('client-calendar-hide-others')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('schedule-lesson-lesson-other')),
        findsOneWidget,
      );
      expect(_lessonBorder(tester, 'lesson-lead'), AppColor.actionBlue);
      expect(_lessonBorder(tester, 'lesson-other'), AppColor.success);
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
    expect(_lessonBorder(tester, 'lesson-selected'), AppColor.danger);
    expect(_lessonBorder(tester, 'lesson-other'), AppColor.success);

    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-week-view')), findsOneWidget);
    expect(_lessonBorder(tester, 'lesson-selected'), AppColor.danger);
    expect(_lessonBorder(tester, 'lesson-other'), AppColor.success);

    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();
    expect(_monthDayBorder(tester, '2026-08-04'), AppColor.success);
    expect(_monthDayBorder(tester, '2026-08-05'), isNot(AppColor.success));

    await tester.tap(find.byTooltip('Поиск: анна смирнова'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Очистить'));
    await tester.pump();
    expect(find.text('Поиск: анна смирнова'), findsNothing);

    await tester.tap(find.byTooltip('Найти занятие'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'НетСовпадений');
    await tester.tap(find.widgetWithText(FilledButton, 'Найти'));
    await tester.pumpAndSettle();
    expect(find.text('Совпадений: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'schedule search resolves lead student teacher room and lesson date '
    'without losing input focus or scroll',
    (tester) async {
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
        _calendarApp(
          api,
          initial: ContextViewState(
            filters: _dayState().filters,
            date: _dayState().date,
            scrollOffset: 180,
          ),
          clientContext: false,
          onChanged: states.add,
        ),
      );
      await tester.pumpAndSettle();
      final preservedScroll = states.last.scrollOffset;
      expect(preservedScroll, greaterThan(0));

      String? activeQuery;
      Future<void> search(String value) async {
        await tester.tap(
          find.byTooltip(
            activeQuery == null ? 'Найти занятие' : 'Поиск: $activeQuery',
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byType(EditableText).last;
        for (var index = 1; index <= value.length; index++) {
          await tester.enterText(field, value.substring(0, index));
          await tester.pump();
          final editable = tester.widget<EditableText>(field);
          expect(editable.focusNode.hasFocus, isTrue);
          expect(editable.controller.text, value.substring(0, index));
        }
        await tester.tap(find.widgetWithText(FilledButton, 'Найти'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        activeQuery = value.toLowerCase();
        expect(states.last.scrollOffset, closeTo(preservedScroll, 0.1));
      }

      await search('ы');
      expect(
        api.getCalls.any(
          (call) =>
              call.path == '/crm/schedule/matrix' &&
              call.query['leadId'] == 'lead-1',
        ),
        isTrue,
      );

      await search('Ан');
      expect(
        api.getCalls.any(
          (call) =>
              call.path == '/crm/schedule/matrix' &&
              call.query['studentId'] == 'student-1',
        ),
        isTrue,
      );

      await search('я');
      expect(
        api.getCalls.any(
          (call) =>
              call.path == '/crm/schedule/matrix' &&
              call.query['teacherId'] == 'teacher-1',
        ),
        isTrue,
      );

      await search('1');
      expect(
        api.getCalls.any(
          (call) =>
              call.path == '/crm/schedule/matrix' &&
              call.query['roomId'] == 'room-a',
        ),
        isTrue,
      );

      await search('05.08.2026');
      await tester.pumpAndSettle();
      activeQuery = null;
      expect(states.last.date, DateTime(2026, 8, 5));
      expect(states.last.scrollOffset, closeTo(preservedScroll, 0.1));
      expect(find.textContaining('Поиск:'), findsNothing);
      expect(find.byType(ScheduleDayCanvas), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

    await tester.tap(find.byKey(const ValueKey('schedule-filter-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-filter-branch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Центр').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-filter-apply')));
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
      titleResolver: const EntityPresentationResolver().pageTitle,
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

    expect(controller.state.tabs, hasLength(2));
    final sourceTab = controller.state.tabs.first;
    final targetTab = controller.state.activeTab;
    expect(sourceTab.routeStack, hasLength(1));
    expect(targetTab.currentRoute.link.entityType, EntityLinkType.lesson);
    final source = sourceTab.currentRoute.viewState;
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

Finder _lessonMarker(String id, IconData icon) => find.descendant(
  of: find.byKey(ValueKey('schedule-lesson-$id')),
  matching: find.byIcon(icon),
);

Color _timelineLessonBorder(WidgetTester tester, String id) {
  final card = find.ancestor(
    of: find.byKey(ValueKey('schedule-lesson-$id')),
    matching: find.byType(AnimatedContainer),
  );
  final animated = tester.widget<AnimatedContainer>(card.first);
  return ((animated.decoration as BoxDecoration).border! as Border).top.color;
}

Color _monthDayBorder(WidgetTester tester, String day) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('schedule-month-day-$day')),
  );
  return ((container.decoration as BoxDecoration).border! as Border).top.color;
}
