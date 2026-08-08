import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';

void main() {
  testWidgets('lesson cards never expose drag-and-drop editing', (
    tester,
  ) async {
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
