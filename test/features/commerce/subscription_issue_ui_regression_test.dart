import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_sheet.dart';

const _package = <String, dynamic>{
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'name': 'Вокал — 8 занятий',
  'basePriceMinor': '800000',
  'currencyCode': 'RUB',
};
const _recipientId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

Future<void> _openSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showSubscriptionIssueFormSheet(
              context,
              package: _package,
              recipientStudentId: _recipientId,
              recipientLabel: 'Иванов Иван',
              searchPayers: (_) async => const <SearchableSelectItem>[],
              onPreview: (_) async => throw StateError('not expected'),
              onSubmit: (_) async => throw StateError('not expected'),
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _editableText(WidgetTester tester, Key key) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

List<String> _finalPriceTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('subscription-issue-final')),
        matching: find.byType(Text),
      ),
    )
    .map((widget) => widget.data ?? '')
    .toList(growable: false);

void main() {
  testWidgets('discount mode change clears the visible amount', (tester) async {
    await _openSheet(tester);
    await _tap(tester, const Key('subscription-discount-percent'));
    await tester.enterText(
      find.byKey(const Key('subscription-discount-value')),
      '20',
    );

    await _tap(tester, const Key('subscription-discount-fixed'));

    expect(
      _editableText(tester, const Key('subscription-discount-value')),
      isEmpty,
    );
  });

  testWidgets('over-base fixed discount hides the invalid total', (
    tester,
  ) async {
    await _openSheet(tester);
    await _tap(tester, const Key('subscription-discount-fixed'));
    await tester.enterText(
      find.byKey(const Key('subscription-discount-value')),
      '8000,01',
    );
    await tester.pump();

    expect(_finalPriceTexts(tester), contains('Не указано'));
  });

  testWidgets('malformed percent hides the invalid total', (tester) async {
    await _openSheet(tester);
    await _tap(tester, const Key('subscription-discount-percent'));
    await tester.enterText(
      find.byKey(const Key('subscription-discount-value')),
      ',',
    );
    await tester.pump();

    expect(_finalPriceTexts(tester), contains('Не указано'));
  });

  testWidgets('non-positive surcharge hides the invalid total', (tester) async {
    await _openSheet(tester);
    await _tap(tester, const Key('subscription-surcharge-toggle'));
    await tester.enterText(
      find.byKey(const Key('subscription-surcharge-amount')),
      '0',
    );
    await tester.pump();

    expect(_finalPriceTexts(tester), contains('Не указано'));
  });
}
