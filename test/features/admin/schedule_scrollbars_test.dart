import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_teacher_timeline.dart';

void main() {
  for (final teacherMode in [false, true]) {
    testWidgets(
      'one scrollbar per axis; headers stay synced teacher=$teacherMode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 720);
        addTearDown(tester.view.reset);
        final date = DateTime(2026, 9, 9);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: Scaffold(
              body: teacherMode
                  ? ScheduleTeacherTimeline(
                      date: date,
                      rows: [
                        for (var i = 0; i < 20; i++)
                          ScheduleTeacherRow(
                            id: '$i',
                            name: 'Преподаватель $i',
                            color: Colors.brown,
                            lessonCount: 0,
                            totalMinutes: 0,
                          ),
                      ],
                      entries: const [],
                      onCreateSlot: (_, _, _) {},
                      onOpenLesson: (_) {},
                    )
                  : ScheduleDayCanvas(
                      date: date,
                      columns: [
                        for (var i = 0; i < 20; i++)
                          ScheduleColumn(
                            id: '$i',
                            name: 'Аудитория $i',
                            color: Colors.brown,
                          ),
                      ],
                      entries: const [],
                      onCreateSlot: (_, _, _) {},
                      onOpenLesson: (_) {},
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bars = tester
            .widgetList<Scrollbar>(find.byType(Scrollbar))
            .toList();
        expect(
          bars,
          hasLength(2),
          reason: 'Only the right and bottom controls.',
        );
        for (final axis in Axis.values) {
          final bar = bars.singleWhere(
            (bar) => bar.controller!.position.axis == axis,
          );
          expect(bar.interactive, isTrue);
          expect(bar.controller!.position.maxScrollExtent, greaterThan(80));
          bar.controller!.jumpTo(80);
          await tester.pumpAndSettle();
          final positions = tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .map((state) => state.position)
              .where((position) => position.axis == axis);
          expect(positions, hasLength(2));
          expect(
            positions.map((position) => position.pixels),
            everyElement(80),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
