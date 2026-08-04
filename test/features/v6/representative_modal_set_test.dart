import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_details_sheet.dart';

void main() {
  testWidgets('lesson quick view expands and confirmation stays concise', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var deleted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLessonDetailsSheet(
                context,
                teacherName: 'Пётр Педагогов',
                studentName: 'Анна Смирнова',
                roomName: 'Зал 1',
                timeRange: '14:00–15:00',
                currentStatus: 'scheduled',
                conflicts: const [],
                lessonId: 'lesson-1',
                onEdit: () {},
                onDelete: () async => deleted++,
              ),
              child: const Text('Открыть занятие'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть занятие'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    expect(find.text('Развернуть'), findsOneWidget);
    expect(find.text('Анна Смирнова'), findsNWidgets(2));

    await tester.tap(find.text('Удалить занятие'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Удалить занятие?'), findsOneWidget);
    await tester.tap(find.text('Оставить'));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
  });

  testWidgets('selection uses sheet on compact and drawer on desktop', (
    tester,
  ) async {
    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => SearchableSelect.show(
                  context: context,
                  title: 'Выберите клиента',
                  hintText: 'Поиск',
                  items: [SearchableSelectItem(id: '1', label: 'Анна')],
                  onSelected: (_) {},
                ),
                child: const Text('Выбрать'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Выбрать'));
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.reset);
    await pumpAt(390);
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    expect(find.text('Выберите клиента'), findsOneWidget);
    Navigator.of(tester.element(find.text('Анна'))).pop();
    await tester.pumpAndSettle();

    await pumpAt(1200);
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsNothing);
    expect(find.byTooltip('Закрыть'), findsOneWidget);
    expect(find.text('Выберите клиента'), findsOneWidget);
  });
}
