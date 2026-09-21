import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/lesson_settlement_corner.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_legends.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_filters_sheet.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_shared.dart';
import 'package:magic_music_crm/core/models/student_lesson_timeline.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_view.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets('timeline legend selects several types and clears back to all', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudentLessonTimelineView(
            page: StudentLessonTimelinePage.fromJson({
              'items': [
                for (final type in ['lesson', 'trial_lesson', 'free_lesson'])
                  {
                    'id': type,
                    'version': 1,
                    'scheduledAt': '2026-09-18T10:00:00Z',
                    'durationMinutes': 60,
                    'lifecycleState': 'scheduled',
                    'student': {'id': 'student', 'name': 'Клиент'},
                    'group': null,
                    'teacher': null,
                    'room': null,
                    'branch': null,
                    'origin': {
                      'kind': 'manual',
                      'planId': null,
                      'seriesId': null,
                    },
                    'settlement': {
                      'coveredBySubscription': false,
                      'settlementTypeKey': type,
                    },
                    'reschedule': {
                      'predecessorId': null,
                      'successorId': null,
                      'actionableLessonId': type,
                    },
                  },
              ],
              'hasPrevious': false,
              'hasNext': false,
              'previousCursor': null,
              'nextCursor': null,
            }),
            loading: false,
            paging: false,
            error: null,
            onPrevious: () {},
            onNext: () {},
            onRetry: () {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LessonSettlementCorner), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('timeline-settlement-legend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('type-filter-trial_lesson')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settlement-background-lesson')),
      findsOneWidget,
      reason: 'legend only',
    );
    expect(
      find.byKey(const ValueKey('settlement-background-trial_lesson')),
      findsNWidgets(2),
    );
    await tester.tap(find.byKey(const ValueKey('type-filter-free_lesson')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settlement-background-free_lesson')),
      findsNWidgets(2),
    );
    await tester.tap(find.text('Сбросить выбор'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settlement-background-lesson')),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule financial multiselect preserves both sets and resets', (
    tester,
  ) async {
    ScheduleFilterResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScheduleFiltersPanel(
              initialBranchId: null,
              initialMode: DayViewMode.byRoom,
              branches: const [],
              isDayView: true,
              initialOnlyTrial: false,
              initialOnlyConflicts: false,
              initialTeacherId: null,
              teacherOptions: const [],
              loadFinancialCatalog: (_) async => {
                'teacherCompensationRules': [
                  {'stableKey': 'standard', 'label': 'Полная ставка'},
                  {'stableKey': 'none', 'label': 'Без оплаты'},
                ],
              },
              onApply: (value) => result = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('financial-filter-Списание клиента')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('type-filter-lesson')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('type-filter-trial_lesson')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('financial-filter-Оплата преподавателю')),
    );
    await tester.tap(
      find.byKey(const ValueKey('financial-filter-Оплата преподавателю')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Полная ставка'));
    await tester.tap(find.text('Полная ставка'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Применить'));
    await tester.tap(find.text('Применить'));
    expect(result!.settlementTypes, {'lesson', 'trial_lesson'});
    expect(result!.compensationRules, {'standard'});
    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Применить'));
    await tester.tap(find.text('Применить'));
    expect(result!.settlementTypes, isEmpty);
    expect(result!.compensationRules, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ordinary lesson has a persistent settlement background', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 60,
            height: 40,
            child: LessonSettlementCorner(
              settlementTypeKey: 'lesson',
              child: Text('Урок'),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('settlement-background-lesson')),
      findsOneWidget,
    );
  });
  testWidgets('schedule legend wraps without horizontal scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 640, child: ScheduleDayLegend())),
      ),
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
    expect(
      find.text('Фон — тип списания · значок — статус').hitTestable(),
      findsOneWidget,
    );
  });
}
