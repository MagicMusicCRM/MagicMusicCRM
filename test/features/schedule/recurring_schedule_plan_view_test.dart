import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/models/student_lesson_timeline.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_view.dart';

void main() {
  for (final width in const [390.0, 768.0, 1440.0]) {
    testWidgets('shows one full-width student timeline at ${width.toInt()}', (
      tester,
    ) async {
      await _pumpView(tester, width: width);

      expect(find.text('Лента занятий'), findsOneWidget);
      expect(find.byKey(const Key('student-lesson-timeline')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-plan-tray-plan-a')),
        findsNothing,
      );
      expect(find.text('Разовое занятие'), findsOneWidget);
      expect(find.text('Абонемент'), findsOneWidget);
      expect(find.text('Отменено'), findsOneWidget);
      expect(find.text('Перенесено'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('student-timeline-lesson-cancelled')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('student-timeline-lesson-successor')),
        findsOneWidget,
      );

      final timeline = tester.getRect(
        find.byKey(const Key('student-lesson-timeline')),
      );
      expect(timeline.width, closeTo(width, 0.1));
      expect(
        tester.getRect(find.text('Разовое занятие')).width,
        greaterThan(70),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('opens the exact timeline lesson and pages globally', (
    tester,
  ) async {
    String? openedId;
    var nextCalls = 0;
    await _pumpView(
      tester,
      onOpenTimelineItem: (item) async => openedId = item.id,
      onNextTimeline: () => nextCalls++,
    );

    await tester.tap(
      find.byKey(const ValueKey('student-timeline-lesson-cancelled')),
    );
    await tester.tap(find.byKey(const Key('student-lesson-timeline-next')));

    expect(openedId, 'lesson-cancelled');
    expect(nextCalls, 1);
  });

  testWidgets('shows rule history and actions only on the current row', (
    tester,
  ) async {
    SchedulePlanRow? edited;
    SchedulePlanRow? removed;
    await _pumpView(
      tester,
      onEditPlan: (_, row) => edited = row,
      onRemoveRow: (_, row) => removed = row,
    );

    expect(find.text('Мария Иванова'), findsWidgets);
    expect(find.text('четверг'), findsOneWidget);
    expect(find.text('16:00 · 60 мин'), findsOneWidget);
    expect(find.text('1.09.2026 — без срока'), findsWidgets);
    expect(find.text('Класс 1'), findsWidgets);
    expect(find.text('Действует'), findsOneWidget);
    expect(find.text('Завершена'), findsOneWidget);
    expect(find.text('Исключение · 12.09.2026'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('schedule-plan-row-edit-series-current')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remove-plan-row-series-current')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-plan-row-edit-series-old')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('remove-plan-row-series-old')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('schedule-plan-row-edit-series-current')),
    );
    await tester.tap(
      find.byKey(const ValueKey('remove-plan-row-series-current')),
    );
    expect(edited?.id, 'series-current');
    expect(removed?.id, 'series-current');
  });
}

Future<void> _pumpView(
  WidgetTester tester, {
  double width = 768,
  Future<void> Function(StudentLessonTimelineItem item)? onOpenTimelineItem,
  VoidCallback? onNextTimeline,
  void Function(SchedulePlan plan, SchedulePlanRow? row)? onEditPlan,
  void Function(SchedulePlan plan, SchedulePlanRow row)? onRemoveRow,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: RecurringSchedulePlanView(
              plans: [_plan('plan-a'), _plan('plan-b')],
              loading: false,
              error: null,
              canWrite: true,
              canCreatePlan: true,
              groupMode: false,
              hasGroupMembers: false,
              fallbackLessons: const [],
              timelinePage: _timeline,
              timelineLoading: false,
              timelinePaging: false,
              timelineError: null,
              onCreate: () {},
              onRetryPlans: () {},
              onPreviousTimeline: () {},
              onNextTimeline: onNextTimeline ?? () {},
              onRetryTimeline: () {},
              onEditPlan: onEditPlan ?? (_, _) {},
              onRemoveRow: onRemoveRow ?? (_, _) {},
              onEditParticipants: (_) {},
              onEndPlan: (_) {},
              onOpenTimelineItem: onOpenTimelineItem ?? (_) async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SchedulePlan _plan(String id) => SchedulePlan.fromMap({
  'id': id,
  'kind': 'individual',
  'title': id == 'plan-a' ? 'Вокал' : 'Фортепиано',
  'studentId': 'student-1',
  'activeFrom': '2026-09-01',
  'status': 'active',
  'version': 4,
  'rows': id == 'plan-a'
      ? [
          {
            'id': 'series-current',
            'teacherId': 'teacher-1',
            'teacherName': 'Мария Иванова',
            'roomId': 'room-1',
            'roomName': 'Класс 1',
            'branchId': 'branch-1',
            'branchName': 'Сокол',
            'weekday': 4,
            'beginTime': '16:00',
            'durationMinutes': 60,
            'validFrom': '2026-09-01',
            'validUntil': null,
            'active': true,
          },
          {
            'id': 'series-old',
            'teacherId': 'teacher-2',
            'teacherName': 'Пётр Сидоров',
            'roomId': 'room-2',
            'roomName': 'Класс 2',
            'branchId': 'branch-1',
            'branchName': 'Сокол',
            'weekday': 2,
            'beginTime': '15:00',
            'durationMinutes': 45,
            'validFrom': '2026-08-01',
            'validUntil': '2026-08-31',
            'active': false,
          },
        ]
      : [],
  'participants': [],
  'ruleTimeline': id == 'plan-a'
      ? [
          _rule(
            id: 'series-current',
            sourceSeriesId: 'series-current',
            status: 'active',
            activeFrom: '2026-09-01',
            activeUntil: null,
            teacherName: 'Мария Иванова',
            roomName: 'Класс 1',
            weekday: 4,
            beginTime: '16:00',
            durationMinutes: 60,
            sortBucket: 0,
            sortAt: '2026-09-01',
          ),
          _rule(
            id: 'series-old',
            sourceSeriesId: 'series-old',
            status: 'expired',
            activeFrom: '2026-08-01',
            activeUntil: '2026-08-31',
            teacherName: 'Пётр Сидоров',
            roomName: 'Класс 2',
            weekday: 2,
            beginTime: '15:00',
            durationMinutes: 45,
            sortBucket: 3,
            sortAt: '2026-08-31',
          ),
        ]
      : [],
  'exceptions': id == 'plan-a'
      ? [
          {
            ..._rule(
              id: 'exception-1',
              sourceSeriesId: 'series-current',
              status: 'active',
              activeFrom: '2026-09-12',
              activeUntil: '2026-09-12',
              teacherName: 'Елена Орлова',
              roomName: 'Класс 3',
              weekday: 6,
              beginTime: '18:00',
              durationMinutes: 60,
              sortBucket: 2,
              sortAt: '2026-09-12',
            ),
            'kind': 'dated_exception',
            'scheduledDate': '2026-09-12',
            'lessonId': 'lesson-exception',
            'changedFields': ['teacherId', 'roomId'],
          },
        ]
      : [],
});

Map<String, dynamic> _rule({
  required String id,
  required String sourceSeriesId,
  required String status,
  required String activeFrom,
  required String? activeUntil,
  required String teacherName,
  required String roomName,
  required int weekday,
  required String beginTime,
  required int durationMinutes,
  required int sortBucket,
  required String sortAt,
}) => {
  'id': id,
  'kind': 'recurring_rule',
  'status': status,
  'activeFrom': activeFrom,
  'activeUntil': activeUntil,
  'scheduledDate': null,
  'teacherId': 'teacher-$id',
  'teacherName': teacherName,
  'roomId': 'room-$id',
  'roomName': roomName,
  'branchId': 'branch-1',
  'branchName': 'Сокол',
  'weekday': weekday,
  'beginTime': beginTime,
  'durationMinutes': durationMinutes,
  'changedFields': <String>[],
  'sortBucket': sortBucket,
  'sortAt': sortAt,
  'lessonId': null,
  'sourceSeriesId': sourceSeriesId,
};

final _timeline = StudentLessonTimelinePage.fromJson({
  'items': [
    _lesson('lesson-manual', 'manual', covered: true),
    _lesson('lesson-plan-a', 'generated', planId: 'plan-a'),
    _lesson('lesson-plan-b', 'generated', planId: 'plan-b'),
    _lesson(
      'lesson-cancelled',
      'generated',
      planId: 'plan-a',
      state: 'cancelled',
    ),
    _lesson(
      'lesson-rescheduled',
      'generated',
      planId: 'plan-a',
      state: 'rescheduled',
      successorId: 'lesson-successor',
    ),
    _lesson(
      'lesson-successor',
      'one_off_exception',
      planId: 'plan-a',
      predecessorId: 'lesson-cancelled',
    ),
  ],
  'previousCursor': null,
  'nextCursor': 'next-page',
  'hasPrevious': false,
  'hasNext': true,
});

Map<String, dynamic> _lesson(
  String id,
  String origin, {
  String? planId,
  String state = 'scheduled',
  bool covered = false,
  String? predecessorId,
  String? successorId,
}) => {
  'id': id,
  'version': 1,
  'scheduledAt': '2026-09-12T13:00:00.000Z',
  'durationMinutes': 60,
  'lifecycleState': state,
  'student': {'id': 'student-1', 'name': 'Анна Смирнова'},
  'group': null,
  'teacher': {'id': 'teacher-1', 'name': 'Мария Иванова'},
  'room': {'id': 'room-1', 'name': 'Класс 1'},
  'branch': {'id': 'branch-1', 'name': 'Сокол'},
  'origin': {'kind': origin, 'planId': planId, 'seriesId': null},
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
