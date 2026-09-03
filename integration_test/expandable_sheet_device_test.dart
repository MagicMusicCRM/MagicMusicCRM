import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('API35 expands mobile sheet and keeps keyboard action visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showMagicSheet<void>(
                  context,
                  title: 'Оплата ученика',
                  subtitle: 'Проверка Android API 35',
                  icon: Icons.payments_outlined,
                  actions: [
                    Builder(
                      builder: (sheetContext) => FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Сохранить'),
                      ),
                    ),
                  ],
                  builder: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const TextField(
                        decoration: InputDecoration(labelText: 'Сумма'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 24),
                      for (var index = 0; index < 20; index++)
                        SizedBox(height: 52, child: Text('Поле оплаты $index')),
                    ],
                  ),
                ),
                child: const Text('Открыть sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть sheet'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Развернуть'), findsOneWidget);
    await tester.tap(find.byTooltip('Развернуть'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Свернуть'), findsOneWidget);
    debugPrint('V6_SHEET_EXPANDED_READY_FOR_ADB');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 45)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(TextField));
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '12500');
    await tester.pumpAndSettle();
    final sheetBottom = tester
        .getRect(find.byKey(const ValueKey('magic-sheet-frame')))
        .bottom;
    final actionBottom = tester.getRect(find.text('Сохранить')).bottom;
    expect(actionBottom, lessThanOrEqualTo(sheetBottom));

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Оплата ученика'), findsNothing);
    debugPrint('V6_SHEET_DEVICE_PASS');
  });
}
