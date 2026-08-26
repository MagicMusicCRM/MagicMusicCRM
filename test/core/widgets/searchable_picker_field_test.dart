import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

void main() {
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
