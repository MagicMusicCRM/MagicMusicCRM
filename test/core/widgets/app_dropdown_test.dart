import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:magic_music_crm/core/widgets/choice_dropdown.dart';

void main() {
  testWidgets('compact dropdown leaves room for a list tile title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ListTile(
              title: const Text('Сотрудники'),
              trailing: AppDropdownButton<String>(
                value: 'read',
                items: const [
                  DropdownMenuItem(
                    value: 'read',
                    child: Text('Читать и писать'),
                  ),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TextField)).width, lessThan(200));
  });
  testWidgets(
    'single selection opens below anchor, searches, preserves nullable values and form reset',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? saved = 'initial';
      String? picked = 'initial';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: SizedBox(
                width: 340,
                child: AppDropdownButtonFormField<String>(
                  initialValue: 'one',
                  decoration: const InputDecoration(labelText: 'Источник'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Все источники')),
                    DropdownMenuItem(value: 'one', child: Text('Звонок')),
                    DropdownMenuItem(value: 'two', child: Text('Реклама')),
                  ],
                  onChanged: (v) => picked = v,
                  onSaved: (v) => saved = v,
                  validator: (v) => v == null ? 'Выберите источник' : null,
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final option = find.widgetWithText(MenuItemButton, 'Реклама');
      expect(
        tester.getTopLeft(option).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(field).dy),
      );
      await tester.enterText(field, 'рек');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Звонок'), findsNothing);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(picked, 'two');
      form.currentState!.save();
      expect(saved, 'two');
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Все источники'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Выберите источник'), findsOneWidget);
      form.currentState!.reset();
      await tester.pumpAndSettle();
      form.currentState!.save();
      expect(saved, 'one');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'multiselect remains open and opens above a bottom field without overlap',
    (tester) async {
      var selected = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: 340,
                child: StatefulBuilder(
                  builder: (context, setState) => ChoiceDropdown(
                    labels: const {'a': 'Занятие', 'b': 'Пробный урок'},
                    selected: selected,
                    multiple: true,
                    onChanged: (v) => setState(() => selected = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomLeft(find.widgetWithText(MenuItemButton, 'Пробный урок'))
            .dy,
        lessThanOrEqualTo(tester.getTopLeft(field).dy),
      );
      await tester.tap(find.text('Занятие'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Пробный урок'));
      await tester.pumpAndSettle();
      expect(selected, {'a', 'b'});
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(find.text('Выбрано: 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('disabled dropdown cannot open or change', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDropdownButton<String>(
            items: const [
              DropdownMenuItem(value: 'x', child: Text('Значение')),
            ],
            onChanged: null,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });
}
