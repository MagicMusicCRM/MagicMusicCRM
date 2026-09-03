import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

void main() {
  testWidgets('server results containing the current selection keep the query and remain selectable', (tester) async {
    SearchableSelectItem? selected;
    final items = [
      SearchableSelectItem(id: 'current', label: 'Иван Первый'),
      SearchableSelectItem(id: 'other', label: 'Иван Второй'),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 420,
      child: SearchablePickerField(
        label: 'Плательщик',
        selectedId: 'current',
        selectedLabel: 'Иван Первый',
        items: items,
        onSearch: (_) async => items,
        onSelected: (item) => selected = item,
      ),
    ))));
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Иван');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Иван');
    final result = find.descendant(of: find.byType(Scrollbar), matching: find.text('Иван Второй'));
    expect(result, findsOneWidget);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(selected?.id, 'other');
  });

  testWidgets(
    'disabling a picker discards a pending search and closes its menu',
    (tester) async {
      final result = Completer<List<SearchableSelectItem>>();
      Widget host(bool enabled) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: SearchablePickerField(
              label: 'Клиент',
              enabled: enabled,
              items: const [],
              onSearch: (_) => result.future,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(true));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Анна');
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(host(false));
      result.complete([
        SearchableSelectItem(id: 'found', label: 'Анна Найденная'),
      ]);
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsNothing);
      expect(find.text('Анна Найденная'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'disabled picker never searches or opens its menu when selection syncs',
    (tester) async {
      var searches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: SearchablePickerField(
                label: 'Клиент',
                enabled: false,
                selectedId: 'current',
                selectedLabel: 'Иван Иванов · Ученик',
                items: [
                  SearchableSelectItem(id: 'current', label: 'Иван Иванов'),
                ],
                onSearch: (_) async {
                  searches++;
                  return [];
                },
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(searches, 0);
      expect(find.byType(Scrollbar), findsNothing);
    },
  );

  testWidgets('searchable picker caps its menu at five scrollable rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: SearchablePickerField(
              label: 'Преподаватель',
              selectedId: '0',
              items: [
                for (var i = 0; i < 8; i++)
                  SearchableSelectItem(id: '$i', label: 'Иванов $i'),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final field = tester.widget<DropdownMenu<String>>(
      find.byType(DropdownMenu<String>),
    );
    expect(field.enableFilter, isTrue);
    expect(field.menuHeight, 256);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, controller.text.length);

    final scrollbar = find.byType(Scrollbar);
    expect(scrollbar, findsOneWidget);
    expect(tester.getSize(scrollbar).height, lessThanOrEqualTo(256));
    expect(
      find.descendant(of: scrollbar, matching: find.text('Иванов 7')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Иванов 7');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: scrollbar, matching: find.text('Иванов 7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: scrollbar, matching: find.text('Иванов 6')),
      findsNothing,
    );
  });

  testWidgets('server search replaces a selected value inline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: SearchablePickerField(
              label: 'Плательщик',
              selectedId: 'current',
              selectedLabel: 'Иван Иванов',
              items: [
                SearchableSelectItem(id: 'current', label: 'Иван Иванов'),
              ],
              onSearch: (_) async => [
                SearchableSelectItem(id: 'found', label: 'Петров Пётр'),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Петров');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Scrollbar).last,
        matching: find.text('Петров Пётр'),
      ),
      findsOneWidget,
    );
  });
}
