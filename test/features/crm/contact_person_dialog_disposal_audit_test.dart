import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_dialogs.dart';

// Diagnostic isolation of the production dialog; no API or persistence claim.
void main() {
  for (final action in ['Сохранить', 'Отмена']) {
    testWidgets(
      'contact dialog $action releases controllers after route closes',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Map<String, dynamic>? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showEditContactPersonDialog(
                      context,
                      existing: {},
                      relationOptions: [],
                      isNew: true,
                    );
                  },
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Открыть'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Имя'),
          'Контакт',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Телефон'),
          '+79992221100',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Почта'),
          'contact@example.test',
        );
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        if (action == 'Сохранить') {
          expect(result?['name'], 'Контакт');
        } else {
          expect(result, isNull);
        }
      },
    );
  }
}
