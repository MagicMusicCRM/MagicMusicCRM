import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';

/// Pumps the picker sheet and returns nothing — the caller drives it via
/// finders. [onSearch] left null keeps the widget in local-filter mode.
Future<void> pumpPicker(
  WidgetTester tester, {
  required List<SearchableSelectItem> items,
  Future<List<SearchableSelectItem>> Function(String)? onSearch,
}) async {
  // The sheet is 75% of the viewport and its list is lazy: on the default
  // 600px-tall test surface only ~5 rows build, which would make a broken
  // limit look correct. Give it room to render more than five.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SearchableSelect(
          title: 'Ученик',
          hintText: 'Поиск…',
          items: items,
          onSelected: (_) {},
          onSearch: onSearch,
        ),
      ),
    ),
  );
}

SearchableSelectItem item(String id, String label, {String? subtitle}) =>
    SearchableSelectItem(id: id, label: label, subtitle: subtitle);

void main() {
  testWidgets('empty query keeps the whole list (browsing, not searching)', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      items: [for (var i = 0; i < 8; i++) item('$i', 'Ученик $i')],
    );

    for (var i = 0; i < 8; i++) {
      expect(find.text('Ученик $i'), findsOneWidget);
    }
  });

  testWidgets('shows at most five matches', (tester) async {
    await pumpPicker(
      tester,
      items: [for (var i = 0; i < 9; i++) item('$i', 'Иванов $i')],
    );

    await tester.enterText(find.byType(TextField), 'иванов');
    await tester.pump();

    expect(find.textContaining('Иванов'), findsNWidgets(5));
  });

  testWidgets('ranks exact, then prefix, then word-start, then mid-word', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      items: [
        item('mid', 'Селиванов Пётр'),
        item('word', 'Петров Иван'),
        item('prefix', 'Иванов Сергей'),
        item('exact', 'иван'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'иван');
    await tester.pump();

    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where(
          (t) =>
              t == 'иван' ||
              t == 'Иванов Сергей' ||
              t == 'Петров Иван' ||
              t == 'Селиванов Пётр',
        )
        .toList();

    expect(shown, [
      'иван', // exact
      'Иванов Сергей', // starts with
      'Петров Иван', // word boundary
      'Селиванов Пётр', // buried mid-word
    ]);
  });

  testWidgets('local mode drops non-matches', (tester) async {
    await pumpPicker(
      tester,
      items: [item('a', 'Иванов'), item('b', 'Сидоров')],
    );

    await tester.enterText(find.byType(TextField), 'иванов');
    await tester.pump();

    expect(find.text('Иванов'), findsOneWidget);
    expect(find.text('Сидоров'), findsNothing);
  });

  testWidgets('server mode keeps rows that matched on unseen fields', (
    tester,
  ) async {
    // The server matches phone/custom data, which the label does not show.
    // Ranking must not throw such a row away — it is the very hit the user
    // searched for.
    await pumpPicker(
      tester,
      items: const [],
      onSearch: (_) async => [item('found', 'Пётр Смирнов')],
    );

    await tester.enterText(find.byType(TextField), '89161234567');
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pump();

    expect(find.text('Пётр Смирнов'), findsOneWidget);
  });
}
