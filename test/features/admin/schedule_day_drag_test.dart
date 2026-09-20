import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';

void main() {
  test('day moves preserve minutes horizontally and snap vertically', () {
    final start = DateTime(2026, 8, 8, 11, 15);
    expect(
      scheduleDayMoveStart(start, verticalDelta: 4, hourHeight: 64),
      start,
    );
    expect(
      scheduleDayMoveStart(start, verticalDelta: 64, hourHeight: 64),
      DateTime(2026, 8, 8, 12),
    );
    expect(
      scheduleDayMoveStart(start, verticalDelta: -64, hourHeight: 64),
      DateTime(2026, 8, 8, 10),
    );
  });

  for (final delta in [
    const Offset(368, 0),
    const Offset(0, 64),
    const Offset(368, 64),
    const Offset(0, 10),
    const Offset(-1000, 0),
    const Offset(0, 1000),
  ]) {
    testWidgets('day drag proposes $delta without mutating the lesson', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final proposals = <(String, DateTime)>[];
      final entry = ScheduleEntry(
        lesson: const {'id': 'lesson-1', 'version': 2},
        id: 'lesson-1',
        columnId: 'room-1',
        startLocal: DateTime(2026, 8, 8, 11, 15),
        durationMinutes: 45,
        title: 'Ученик',
        subtitle: 'Педагог',
        isTrial: false,
        conflicts: const [],
        highlighted: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleDayCanvas(
              date: DateTime(2026, 8, 8),
              fitToViewport: false,
              columns: const [
                ScheduleColumn(id: 'room-1', name: '1', color: Colors.blue),
                ScheduleColumn(id: 'room-2', name: '2', color: Colors.blue),
              ],
              entries: [entry],
              onCreateSlot: (_, _, _) {},
              onOpenLesson: (_) {},
              onProposeMove: (entry, room, start) async =>
                  proposals.add((room, start)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('schedule-lesson-lesson-1'));
      final before = tester.getRect(card);
      await tester.dragFrom(
        before.center,
        delta,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final rejected = delta.distance > 900 || delta == const Offset(0, 10);
      expect(
        proposals,
        rejected
            ? []
            : [
                (
                  delta.dx == 0 ? 'room-1' : 'room-2',
                  delta.dy == 0
                      ? DateTime(2026, 8, 8, 11, 15)
                      : DateTime(2026, 8, 8, 12),
                ),
              ],
      );
      expect(tester.getRect(card), before);
      expect(entry.durationMinutes, 45);
    });
  }

  testWidgets('read-only lesson cards have no move callback', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleDayCanvas(
            date: DateTime(2026, 8, 8),
            columns: const [
              ScheduleColumn(id: 'room-1', name: 'Сокол', color: Colors.blue),
            ],
            entries: [
              ScheduleEntry(
                lesson: const {'id': 'lesson-1'},
                id: 'lesson-1',
                columnId: 'room-1',
                startLocal: DateTime(2026, 8, 8, 10),
                durationMinutes: 60,
                title: 'Ученик',
                subtitle: 'Преподаватель',
                isTrial: false,
                conflicts: const [],
                highlighted: false,
              ),
            ],
            onCreateSlot: (_, _, _) {},
            onOpenLesson: (lesson) => opened.add(lesson['id'].toString()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Draggable<Map<String, dynamic>>), findsNothing);
    expect(find.byType(LongPressDraggable<Map<String, dynamic>>), findsNothing);
    expect(find.byType(DragTarget<Map<String, dynamic>>), findsNothing);

    await tester.tap(find.text('Ученик'));
    await tester.pumpAndSettle();
    expect(opened, ['lesson-1']);
  });
}
