import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_card.dart';

void main() {
  testWidgets('drag feedback stays compact, responsive, and gold', (
    tester,
  ) async {
    await _pumpCard(tester, width: 320);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StudentBoardCard)),
    );
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();

    final feedback = find.byKey(const ValueKey('student-card-drag-feedback'));
    expect(feedback, findsOneWidget);
    expect(tester.getSize(feedback).width, 272);
    expect(
      find.descendant(
        of: feedback,
        matching: find.byIcon(Icons.drag_indicator_rounded),
      ),
      findsOneWidget,
    );
    final decoration = tester.widget<Container>(feedback).decoration;
    expect(decoration, isA<BoxDecoration>());
    expect(
      (decoration! as BoxDecoration).border,
      Border.all(color: AppTheme.primaryGold, width: 2),
    );

    await gesture.up();
  });

  testWidgets('discipline and metric badges retain the frozen gold styling', (
    tester,
  ) async {
    await _pumpCard(tester, width: 400);

    final disciplineBadge = find.ancestor(
      of: find.text('Вокал'),
      matching: find.byType(Container),
    );
    final metricBadge = find.ancestor(
      of: find.byIcon(Icons.task_alt_rounded),
      matching: find.byType(Container),
    );

    expect(disciplineBadge, findsOneWidget);
    expect(metricBadge, findsOneWidget);
    expect(
      (tester.widget<Container>(disciplineBadge).decoration! as BoxDecoration)
          .color,
      AppTheme.primaryGold.withAlpha(51),
    );
    expect(
      (tester.widget<Container>(metricBadge).decoration! as BoxDecoration)
          .color,
      AppTheme.primaryGold.withAlpha(36),
    );
  });
}

Future<void> _pumpCard(WidgetTester tester, {required double width}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark().copyWith(platform: TargetPlatform.windows),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: SizedBox(
            width: width - 20,
            child: StudentBoardCard(
              student: const {
                'id': 'student-1',
                'first_name': 'Анна',
                'last_name': 'Иванова',
                'phone': '+70000000000',
                'custom_data': {'discipline': 'Вокал'},
                'open_tasks_count': 2,
                'lessons_count': 3,
                'groups_count': 1,
              },
              isPending: false,
              onTap: () {},
              onOpenChat: (_) {},
              onDragUpdate: (_) {},
              onDragEnd: () {},
            ),
          ),
        ),
      ),
    ),
  );
}
