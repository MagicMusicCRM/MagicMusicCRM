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
      for (final label in [
        'Разовое занятие',
        'Абонемент',
        'Отменено',
        'Перенесено',
      ]) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip && (widget.message?.contains(label) ?? false),
          ),
          findsWidgets,
        );
      }
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
      final grid = tester.getRect(
        find.byKey(const Key('student-lesson-timeline-grid')),
      );
      final tiles = _timeline.items
          .map(
            (item) => tester.getRect(
              find.byKey(ValueKey('student-timeline-${item.id}')),
            ),
          )
          .toList();
      expect(tiles.map((tile) => tile.top.round()).toSet(), hasLength(2));
      expect(
        tiles.every(
          (tile) => tile.top >= grid.top && tile.bottom <= grid.bottom,
        ),
        isTrue,
      );
      expect(grid.height, closeTo(84, 0.1));
      for (final tile in tiles) {
        expect(tile.height, closeTo(40, 0.1));
        expect(tile.width, inInclusiveRange(78, 90));
      }
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
      onOpenTimelineItem: (lessonId) async => openedId = lessonId,
      onNextTimeline: () => nextCalls++,
    );

    await tester.tap(
      find.byKey(const ValueKey('student-timeline-lesson-cancelled')),
    );
    await tester.tap(find.byKey(const Key('student-lesson-timeline-next')));

    expect(openedId, 'lesson-cancelled');
    expect(nextCalls, 1);
  });

  testWidgets('opens the actionable successor from a rescheduled source', (
    tester,
  ) async {
    String? openedId;
    await _pumpView(
      tester,
      onOpenTimelineItem: (lessonId) async => openedId = lessonId,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('student-timeline-successor-lesson-rescheduled'),
      ),
    );
    await tester.pumpAndSettle();

    expect(openedId, 'lesson-successor');
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
    await tester.tap(
      find.byKey(const PageStorageKey('schedule-plan-expansion-plan-a')),
    );
    await tester.pumpAndSettle();

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

  testWidgets('individual plans collapse and page in groups of three', (
    tester,
  ) async {
    await _pumpView(
      tester,
      plans: [
        for (final id in ['plan-a', 'plan-b', 'plan-c', 'plan-d']) _plan(id),
      ],
    );
    expect(find.byKey(const ValueKey('schedule-plan-plan-d')), findsNothing);
    expect(find.text('1–3 из 4'), findsOneWidget);
    expect(find.text('Действует'), findsNothing);
    final toggle = find.byKey(
      const PageStorageKey('schedule-plan-expansion-plan-a'),
    );
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Действует'), findsOneWidget);
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Действует'), findsNothing);
    await tester.tap(find.byTooltip('Следующие записи'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-plan-plan-d')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-plan-plan-a')), findsNothing);
    await tester.tap(find.byTooltip('Предыдущие записи'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-plan-plan-a')), findsOneWidget);
    expect(find.text('Действует'), findsNothing);
  });

  testWidgets('temporary individual plan shows at most three rule records', (
    tester,
  ) async {
    final plan = SchedulePlan.fromMap({
      'id': 'temporary',
      'kind': 'individual',
      'title': 'Временное расписание',
      'studentId': 'student-1',
      'activeFrom': '2026-09-01',
      'activeUntil': '2026-10-01',
      'status': 'active',
      'version': 1,
      'rows': [],
      'participants': [],
      'ruleTimeline': [
        for (var i = 0; i < 7; i++)
          _rule(
            id: 'rule-$i',
            sourceSeriesId: 'rule-$i',
            status: 'active',
            activeFrom: '2026-09-01',
            activeUntil: '2026-10-01',
            teacherName: 'Педагог $i',
            roomName: 'Класс $i',
            weekday: i + 1,
            beginTime: '16:00',
            durationMinutes: 60,
            sortBucket: 0,
            sortAt: '2026-09-01',
          ),
      ],
    });
    await _pumpView(tester, plans: [plan]);
    final toggle = find.byKey(
      const PageStorageKey('schedule-plan-expansion-temporary'),
    );
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(find.text('Педагог $i'), findsOneWidget);
    }
    expect(find.text('Педагог 3'), findsNothing);
    await tester.tap(find.byTooltip('Следующие записи'));
    await tester.pumpAndSettle();
    expect(find.text('Педагог 0'), findsNothing);
    expect(find.text('Педагог 3'), findsOneWidget);
    expect(find.text('Педагог 6'), findsNothing);
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Педагог 3'), findsNothing);
  });

  for (final textScale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'two-row timeline scrolls locally before requesting API page at scale $textScale',
      (tester) async {
        var nextCalls = 0;
        final timeline = StudentLessonTimelinePage.fromJson({
          'items': [
            for (var i = 0; i < 24; i++) _lesson('scroll-$i', 'manual'),
          ],
          'hasPrevious': false,
          'hasNext': true,
          'nextCursor': 'more',
        });
        await _pumpView(
          tester,
          width: 390,
          textScale: textScale,
          plans: [],
          timeline: timeline,
          onNextTimeline: () => nextCalls++,
        );
        final first = find.byKey(const ValueKey('student-timeline-scroll-0'));
        final left = tester.getTopLeft(first).dx;
        await tester.tap(find.byKey(const Key('student-lesson-timeline-next')));
        await tester.pumpAndSettle();
        expect(nextCalls, 0);
        if (first.evaluate().isNotEmpty) {
          expect(tester.getTopLeft(first).dx, lessThan(left));
        }
        for (var i = 0; i < 15 && nextCalls == 0; i++) {
          await tester.tap(
            find.byKey(const Key('student-lesson-timeline-next')),
          );
          await tester.pumpAndSettle();
        }
        expect(nextCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pumpView(
  WidgetTester tester, {
  double width = 768,
  Future<void> Function(String lessonId)? onOpenTimelineItem,
  VoidCallback? onNextTimeline,
  void Function(SchedulePlan plan, SchedulePlanRow? row)? onEditPlan,
  void Function(SchedulePlan plan, SchedulePlanRow row)? onRemoveRow,
  List<SchedulePlan>? plans,
  StudentLessonTimelinePage? timeline,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: RecurringSchedulePlanView(
              plans: plans ?? [_plan('plan-a'), _plan('plan-b')],
              loading: false,
              error: null,
              canWrite: true,
              canCreatePlan: true,
              groupMode: false,
              hasGroupMembers: false,
              fallbackLessons: const [],
              timelinePage: timeline ?? _timeline,
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
