import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/models/student_lesson_timeline.dart';
import 'package:magic_music_crm/core/widgets/lesson_settlement_corner.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_view.dart';

const _keys = [
  'lesson',
  'trial_lesson',
  'partially_paid_lesson',
  'free_lesson',
  'paid_miss',
  'unpaid_miss',
];
const _names = [
  'Анна Смирнова',
  'Александр Константинопольский',
  'Мария Волкова',
  'Дмитрий Соколов',
  'Екатерина Новикова',
  'Группа · вокал',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'real day and timeline keep persistent settlement backgrounds legible',
    (tester) async {
      tester.view.physicalSize = const Size(1120, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final entries = [
        for (var room = 0; room < 6; room++)
          for (var slot = 0; slot < 5; slot++)
            ScheduleEntry(
              lesson: {
                'settlement_type_key': _keys[room],
                'lifecycle_state': slot == 0
                    ? 'successfully_completed'
                    : 'scheduled',
              },
              id: '$room-$slot',
              columnId: 'r$room',
              startLocal: DateTime(
                2026,
                9,
                13,
                [10, 12, 12, 15, 18][slot],
                slot == 2 ? 15 : 0,
              ),
              durationMinutes: [60, 15, 15, 90, 30][slot],
              title: _names[(room + slot) % 6],
              subtitle: 'Мария Иванова',
              isTrial: false,
              conflicts: const [],
              highlighted: false,
            ),
      ];
      final timeline = StudentLessonTimelinePage.fromJson({
        'windowStart': '2026-09-10T00:00:00',
        'previousCursor': null,
        'nextCursor': null,
        'hasPrevious': false,
        'hasNext': false,
        'items': [
          for (var i = 0; i < 30; i++)
            {
              'id': 't$i',
              'version': 1,
              'scheduledAt': DateTime(2026, 9, 10 + i, 12).toIso8601String(),
              'durationMinutes': 60,
              'lifecycleState': i < 3 ? 'successfully_completed' : 'scheduled',
              'student': {'id': 'student', 'name': 'Анна Смирнова'},
              'origin': {'kind': 'manual'},
              'settlement': {
                'coveredBySubscription': i % 6 == 0,
                'settlementTypeKey': _keys[i % 6],
              },
              'reschedule': {'actionableLessonId': 't$i'},
            },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.production,
          home: RepaintBoundary(
            key: const Key('visual'),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Фон списания в реальных виджетах · тестовые данные',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        for (final key in _keys)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: LessonSettlementCorner(
                                  settlementTypeKey: key,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                LessonSettlementCorner.labelFor(key)!,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ScheduleDayCanvas(
                        date: DateTime(2026, 9, 13),
                        columns: [
                          for (var i = 0; i < 6; i++)
                            ScheduleColumn(
                              id: 'r$i',
                              name: 'Аудитория ${i + 1}',
                              color: AppColor.text2,
                            ),
                        ],
                        entries: entries,
                        onCreateSlot: (_, _, _) {},
                        onOpenLesson: (_) {},
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Лента клиента · 2 строки по 15 ячеек · узкая ширина 720 px',
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 720,
                        child: StudentLessonTimelineView(
                          page: timeline,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('student-timeline-t29')),
        findsOneWidget,
      );
      final short = find.byKey(const ValueKey('schedule-lesson-1-1'));
      final cell = find.byKey(const ValueKey('student-timeline-t1'));
      expect(tester.getSize(short).height, lessThanOrEqualTo(20));
      expect(tester.getSize(cell).width, lessThan(45));
      await expectLater(
        find.byKey(const Key('visual')),
        matchesGoldenFile('goldens/lesson_settlement_corners.png'),
      );
    },
  );
}
