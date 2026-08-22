import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';

void main() {
  testWidgets('page states expose retry and concise empty guidance', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MagicPageState(
          kind: MagicPageStateKind.error,
          title: 'Не удалось загрузить задачи',
          actionLabel: 'Повторить',
          onAction: () => retries++,
        ),
      ),
    );
    await tester.tap(find.text('Повторить'));
    expect(retries, 1);

    await tester.pumpWidget(
      const MaterialApp(
        home: MagicPageState(
          kind: MagicPageStateKind.empty,
          title: 'Нет задач',
          message: 'Создайте первую задачу.',
        ),
      ),
    );
    expect(find.text('Нет задач'), findsOneWidget);
    expect(find.text('Создайте первую задачу.'), findsOneWidget);
  });
}
