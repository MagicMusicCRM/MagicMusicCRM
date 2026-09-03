import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

void main() {
  testWidgets('desktop forms retain the lesson editor reading width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    for (final preferredWidth in [360.0, 520.0, 680.0]) {
      await _openForm(tester, TargetPlatform.windows, preferredWidth);
      final field = tester.getRect(find.byKey(const Key('form-field')));
      expect(
        field.width,
        greaterThanOrEqualTo(650),
        reason: 'A legacy $preferredWidth width must not squeeze the form.',
      );
      expect(field.center.dx, closeTo(640, 1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'phone forms use the sheet width instead of their intrinsic width',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
      await _openForm(tester, TargetPlatform.android, 200);
      final field = tester.getRect(find.byKey(const Key('form-field')));
      // The sheet border takes two pixels, and the dialog has 24px side padding.
      expect(field.width, greaterThanOrEqualTo(310));
      expect(field.left, greaterThanOrEqualTo(16));
      expect(field.right, lessThanOrEqualTo(344));
      expect(find.text('Сохранить').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openForm(
  WidgetTester tester,
  TargetPlatform platform,
  double width,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMagicDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Настройки'),
                content: SizedBox(
                  width: width,
                  child: const TextField(
                    key: Key('form-field'),
                    decoration: InputDecoration(labelText: 'Название'),
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Сохранить'),
                  ),
                ],
              ),
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
