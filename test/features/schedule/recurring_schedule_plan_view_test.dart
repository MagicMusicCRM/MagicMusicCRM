import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_view.dart';

void main() {
  testWidgets('lesson tray fills its width and adapts when resized', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = List.generate(
      13,
      (index) => SchedulePlanTrayItem.fromMap({
        'id': 'lesson-$index',
        'scheduledAt': DateTime.utc(
          2026,
          9,
          4 + index * 7,
          12,
        ).toIso8601String(),
        'localDate': '2026-09-04',
        'localTime': '15:00',
        'state': 'scheduled',
        'settlementMarkers': const [],
        'relationMarker': 'none',
      }),
    );
    final plan = SchedulePlan.fromMap({
      'id': 'plan-width',
      'title': 'Вокал',
      'kind': 'individual',
      'activeFrom': '2026-09-01',
      'status': 'active',
      'version': 1,
    });
    for (final width in [1000.0, 360.0, 1440.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  child: RecurringSchedulePlanView(
                    plans: [plan],
                    loading: false,
                    error: null,
                    canWrite: true,
                    canCreatePlan: true,
                    groupMode: false,
                    hasGroupMembers: false,
                    fallbackLessons: const [],
                    trays: {
                      'plan-width': SchedulePlanTrayPage(
                        planId: 'plan-width',
                        items: items,
                        hasPrevious: false,
                        hasNext: false,
                        previousCursor: null,
                        nextCursor: null,
                      ),
                    },
                    loadingTrayIds: const {},
                    trayErrors: const {},
                    onCreate: () {},
                    onRetryPlans: () {},
                    onEnsureTray: (_) {},
                    onPageTray: (_, _) {},
                    onRetryTray: (_) {},
                    onEditPlan: (_, _) {},
                    onEditParticipants: (_) {},
                    onEndPlan: (_) {},
                    onOpenTrayItem: (_) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tray = tester.getRect(
        find.byKey(const Key('client-lesson-date-tray')),
      );
      final tiles =
          List.generate(
                13,
                (index) => find.byKey(ValueKey('client-lesson-lesson-$index')),
              )
              .where((finder) => finder.evaluate().isNotEmpty)
              .map(tester.getRect)
              .toList();
      final visible = tiles
          .where(
            (rect) =>
                rect.left >= tray.left - 0.01 &&
                rect.right <= tray.right + 0.01,
          )
          .toList();
      expect(visible.first.left, closeTo(tray.left, 0.01));
      expect(
        visible.map((rect) => rect.right).reduce((a, b) => a > b ? a : b),
        closeTo(tray.right, 0.01),
      );
      if (width >= 1000) expect(visible, hasLength(13));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'recurring plan view renders empty state and emits create intent',
    (tester) async {
      var createCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecurringSchedulePlanView(
              plans: const [],
              loading: false,
              error: null,
              canWrite: true,
              canCreatePlan: true,
              groupMode: false,
              hasGroupMembers: false,
              fallbackLessons: const [],
              trays: const {},
              loadingTrayIds: const {},
              trayErrors: const {},
              onCreate: () => createCalls += 1,
              onRetryPlans: () {},
              onEnsureTray: (_) {},
              onPageTray: (_, _) {},
              onRetryTray: (_) {},
              onEditPlan: (_, _) {},
              onEditParticipants: (_) {},
              onEndPlan: (_) {},
              onOpenTrayItem: (_) async {},
            ),
          ),
        ),
      );

      expect(find.text('Постоянных расписаний пока нет'), findsOneWidget);

      await tester.tap(find.byKey(const Key('schedule-plan-add')));
      await tester.pump();

      expect(createCalls, 1);
    },
  );

  testWidgets('recurring plan view guards duplicate lesson opens', (
    tester,
  ) async {
    final pendingOpen = Completer<void>();
    var openCalls = 0;
    final plan = SchedulePlan.fromMap({
      'id': 'plan-1',
      'kind': 'individual',
      'title': 'Фортепиано',
      'studentId': 'student-1',
      'activeFrom': '2026-08-01',
      'status': 'active',
      'version': 1,
      'rows': const [],
      'participants': const [],
    });
    const trayItem = SchedulePlanTrayItem(
      id: 'lesson-1',
      scheduledAt: '2026-08-25T12:00:00.000Z',
      localDate: '2026-08-25',
      localTime: '15:00',
      state: 'scheduled',
      settlementMarkers: [],
      relationMarker: 'none',
      predecessorId: null,
      successorId: null,
      teacherName: 'Педагог',
      roomName: 'Класс 1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecurringSchedulePlanView(
            plans: [plan],
            loading: false,
            error: null,
            canWrite: true,
            canCreatePlan: true,
            groupMode: false,
            hasGroupMembers: false,
            fallbackLessons: const [],
            trays: const {
              'plan-1': SchedulePlanTrayPage(
                planId: 'plan-1',
                items: [trayItem],
                hasPrevious: false,
                hasNext: false,
                previousCursor: null,
                nextCursor: null,
              ),
            },
            loadingTrayIds: const {},
            trayErrors: const {},
            onCreate: () {},
            onRetryPlans: () {},
            onEnsureTray: (_) {},
            onPageTray: (_, _) {},
            onRetryTray: (_) {},
            onEditPlan: (_, _) {},
            onEditParticipants: (_) {},
            onEndPlan: (_) {},
            onOpenTrayItem: (_) {
              openCalls += 1;
              return pendingOpen.future;
            },
          ),
        ),
      ),
    );

    final lesson = find.byKey(const ValueKey('client-lesson-lesson-1'));
    await tester.tap(lesson);
    await tester.tap(lesson);

    expect(openCalls, 1);

    pendingOpen.complete();
    await tester.pump();
  });
}
