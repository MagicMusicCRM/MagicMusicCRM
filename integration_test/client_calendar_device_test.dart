import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_teacher_timeline.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';

import '../test/features/crm/client_card/card_fake_api.dart';
import 'evidence_screenshot.dart';

const _coveredLesson = {
  'id': 'lesson-device-covered',
  'studentId': 'student-1',
  'studentName': 'Анна Смирнова',
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
  'reservationState': 'reserved',
  'isTrial': false,
  'conflictTypes': <String>[],
};

const _coveredTimelinePage = {
  'items': [
    {
      'id': 'lesson-device-covered',
      'version': 1,
      'scheduledAt': '2026-08-04T11:00:00.000Z',
      'durationMinutes': 60,
      'lifecycleState': 'scheduled',
      'student': {'id': 'student-1', 'name': 'Анна Смирнова'},
      'group': null,
      'teacher': {'id': 'teacher-1', 'name': 'Мария Педагог'},
      'room': {'id': 'room-a', 'name': 'Класс 1'},
      'branch': {'id': 'branch-a', 'name': 'Сокол'},
      'origin': {
        'kind': 'generated',
        'planId': 'plan-covered',
        'seriesId': 'series-covered',
      },
      'settlement': {
        'coveredBySubscription': true,
        'settlementTypeKey': 'subscription',
      },
      'reschedule': {
        'predecessorId': null,
        'successorId': null,
        'actionableLessonId': 'lesson-device-covered',
      },
    },
  ],
  'previousCursor': null,
  'nextCursor': null,
  'hasPrevious': false,
  'hasNext': false,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('client calendar drills into schedule and Back restores it', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeCardApiClient(
      student: const {
        'id': 'student-2',
        'firstName': 'Иван',
        'lastName': 'Петров',
      },
      branches: const [
        {'id': 'branch-a', 'name': 'Сокол', 'utcOffsetMinutes': 180},
      ],
      teachers: const [
        {
          'id': 'teacher-1',
          'firstName': 'Мария',
          'lastName': 'Педагог',
          'status': 'active',
          'assignedBranches': [
            {'id': 'branch-a', 'name': 'Сокол'},
          ],
        },
      ],
      rooms: const [
        {'id': 'room-a', 'name': 'Класс 1', 'branchId': 'branch-a'},
      ],
      scheduleMatrix: const [
        {
          'id': 'lesson-device',
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
          'id': 'lesson-device-booked',
          'studentId': 'student-1',
          'studentName': 'Анна Смирнова',
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
          'isTrial': false,
          'conflictTypes': <String>[],
        },
        {
          'id': 'lesson-late',
          'version': 1,
          'studentId': 'student-2',
          'studentName': 'Иван Петров',
          'teacherId': 'teacher-1',
          'teacherName': 'Мария Педагог',
          'branchId': 'branch-a',
          'branchName': 'Сокол',
          'roomId': 'room-a',
          'roomName': 'Класс 1',
          'scheduledAt': '2026-08-04T17:00:00.000Z',
          'durationMinutes': 60,
          'status': 'scheduled',
          'lifecycleState': 'scheduled',
          'isTrial': false,
          'conflictTypes': <String>[],
        },
      ],
    );
    final router = GoRouter(
      initialLocation: '/students/student-1',
      routes: [
        GoRoute(
          path: '/students/:id',
          builder: (_, _) => Scaffold(
            body: SizedBox(
              height: 760,
              child: ScheduleWidget(
                title: 'Календарь занятий',
                clientType: 'student',
                clientId: 'student-1',
                clientName: 'Анна Смирнова',
                initialBranchId: 'branch-a',
                canWrite: true,
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
          builder: (_, _) => const Scaffold(body: Text('Расписание host')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(api),
            capabilitySnapshotProvider.overrideWith(
              (ref) async => const CapabilitySnapshot(
                accountId: 'account-1',
                role: 'admin',
                accessVersion: 1,
                capabilities: {
                  'crm.client.read.basic',
                  'schedule.lesson.read.assigned',
                  'schedule.lesson.write',
                },
                scopes: {'schedule': 'branch'},
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.dark,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Анна Смирнова'), findsWidgets);
    final hideOthers = tester.widget<FilterChip>(
      find.byKey(const ValueKey('client-calendar-hide-others')),
    );
    expect(hideOthers.selected, isTrue);
    expect(find.text('Другие клиенты'), findsNothing);
    expect(
      find.byKey(const ValueKey('schedule-lesson-lesson-other')),
      findsNothing,
    );
    await captureEvidence(tester, 'client-calendar-hide-others-default');
    await tester.tap(find.byKey(const ValueKey('client-calendar-hide-others')));
    await tester.pumpAndSettle();
    expect(find.text('Другие клиенты'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-lesson-lesson-other')),
      findsOneWidget,
    );
    expect(
      _lessonMarker('lesson-device', Icons.person_pin_circle_outlined),
      findsOneWidget,
    );
    expect(
      _lessonMarker('lesson-other', Icons.people_outline_rounded),
      findsOneWidget,
    );
    await captureEvidence(tester, 'client-calendar-show-others-highlight');

    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-week-view')), findsOneWidget);
    expect(
      _lessonMarker('lesson-device', Icons.person_pin_circle_outlined),
      findsOneWidget,
    );
    expect(
      _lessonMarker('lesson-other', Icons.people_outline_rounded),
      findsOneWidget,
    );
    await captureEvidence(tester, 'client-calendar-week-target-markers');

    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();
    expect(find.text('Август 2026'), findsWidgets);
    expect(find.text('августа 2026'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Календарь занятий').first).dy,
      greaterThanOrEqualTo(0),
    );
    expect(
      find.byKey(const ValueKey('schedule-month-day-2026-08-04')),
      findsOneWidget,
    );
    await captureEvidence(tester, 'client-calendar-month-target-day');

    await tester.tap(find.text('День'));
    await tester.pumpAndSettle();

    final lateLesson = find.byKey(
      const ValueKey('schedule-lesson-lesson-late'),
    );
    await tester.ensureVisible(lateLesson);
    await tester.pumpAndSettle();
    final dayCanvas = find.byType(ScheduleDayCanvas);
    final scrollBeforeEditor = _maxVerticalScrollOffset(tester, dayCanvas);
    expect(scrollBeforeEditor, greaterThan(0));
    await tester.tap(lateLesson);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Перенести или изменить'));
    await tester.pumpAndSettle();
    expect(find.text('Перенести или изменить занятие'), findsOneWidget);
    await captureEvidence(tester, 'client-calendar-canonical-editor');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleDayCanvas), findsOneWidget);
    expect(find.text('вт, 4 августа 2026'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('client-calendar-hide-others')),
          )
          .selected,
      isFalse,
    );
    expect(
      _maxVerticalScrollOffset(tester, find.byType(ScheduleDayCanvas)),
      closeTo(scrollBeforeEditor, 1),
    );
    await captureEvidence(tester, 'client-calendar-back-context-restored');

    await tester.tap(find.text('По преподавателям'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleTeacherTimeline), findsOneWidget);
    expect(
      _lessonMarker('lesson-device', Icons.person_pin_circle_outlined),
      findsOneWidget,
    );
    expect(
      _lessonMarker('lesson-other', Icons.people_outline_rounded),
      findsOneWidget,
    );
    await captureEvidence(tester, 'client-calendar-teacher-target-markers');

    final lesson = find.byKey(const ValueKey('schedule-lesson-lesson-device'));
    await tester.ensureVisible(lesson);
    await tester.pumpAndSettle();
    await tester.tap(lesson);
    await tester.pumpAndSettle();
    final reference = find.byKey(const ValueKey('lesson-reference-Занятие'));
    if (reference.evaluate().isEmpty) {
      await tester.tap(lesson);
      await tester.pumpAndSettle();
    }
    await tester.tap(reference);
    await tester.pumpAndSettle();
    expect(find.text('Расписание host'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleTeacherTimeline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'covered lesson matches calendar drill-down and client timeline',
    (tester) async {
      await initializeDateFormatting('ru');
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeCardApiClient(
        branches: const [
          {'id': 'branch-a', 'name': 'Сокол', 'utcOffsetMinutes': 180},
        ],
        teachers: const [
          {
            'id': 'teacher-1',
            'firstName': 'Мария',
            'lastName': 'Педагог',
            'status': 'active',
          },
        ],
        rooms: const [
          {'id': 'room-a', 'name': 'Класс 1', 'branchId': 'branch-a'},
        ],
        scheduleMatrix: const [_coveredLesson],
        studentLessonTimelinePage: _coveredTimelinePage,
      );
      const capabilitySnapshot = CapabilitySnapshot(
        accountId: 'account-1',
        role: 'admin',
        accessVersion: 1,
        capabilities: {
          'crm.client.read.basic',
          'schedule.lesson.read.assigned',
        },
        scopes: {'schedule': 'branch'},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(api),
            capabilitySnapshotProvider.overrideWith(
              (ref) async => capabilitySnapshot,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: SizedBox(
                height: 760,
                child: ScheduleWidget(
                  title: 'Календарь занятий',
                  clientType: 'student',
                  clientId: 'student-1',
                  clientName: 'Анна Смирнова',
                  initialBranchId: 'branch-a',
                  canWrite: false,
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
      );
      await tester.pumpAndSettle();

      final coveredLesson = find.byKey(
        const ValueKey('schedule-lesson-lesson-device-covered'),
      );
      await tester.ensureVisible(coveredLesson);
      await tester.pumpAndSettle();
      await tester.tap(coveredLesson);
      await tester.pumpAndSettle();
      expect(find.text('Покрытие: '), findsOneWidget);
      expect(find.text('Абонемент'), findsOneWidget);
      await captureEvidence(tester, 'client-calendar-covered-lesson-details');

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RecurringSchedulePlanSection(
                  studentId: 'student-1',
                  fallbackLessons: const [],
                  branches: api.branches,
                  defaultBranchId: 'branch-a',
                  subscriptions: const [],
                  canWrite: false,
                  onChanged: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('student-timeline-lesson-device-covered')),
        findsOneWidget,
      );
      expect(find.text('Абонемент'), findsOneWidget);
      await captureEvidence(tester, 'client-timeline-covered-lesson');
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _lessonMarker(String id, IconData icon) => find.descendant(
  of: find.byKey(ValueKey('schedule-lesson-$id')),
  matching: find.byIcon(icon),
);

double _maxVerticalScrollOffset(WidgetTester tester, Finder root) {
  final offsets = tester
      .stateList<ScrollableState>(
        find.descendant(of: root, matching: find.byType(Scrollable)),
      )
      .where((state) => state.position.axis == Axis.vertical)
      .map((state) => state.position.pixels);
  return offsets.fold<double>(
    0,
    (maximum, value) => value > maximum ? value : maximum,
  );
}
