import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

void main() {
  testWidgets(
    'portrait sheet is full width and reaches all three snap states',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
      await _pumpSheetHost(tester, longContent: true);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final frame = find.byKey(const ValueKey('magic-sheet-frame'));
      final initial = tester.getSize(frame);
      expect(initial.width, 360);
      expect(initial.height, closeTo(800 * 0.58, 2));
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('magic-sheet-state')))
            .label,
        contains('частично развернуто'),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('magic-sheet-handle'))),
      );
      await gesture.moveBy(const Offset(0, -250));
      await gesture.up();
      await tester.pumpAndSettle();
      final middle = tester.getSize(frame).height;
      expect(middle, closeTo(800 * 0.9, 3));

      await tester.tap(find.byKey(const ValueKey('magic-sheet-toggle')));
      await tester.pumpAndSettle();
      final expanded = tester.getSize(frame).height;
      expect(expanded, closeTo(800, 2));
      expect(find.text('Свернуть'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('magic-sheet-state')))
            .label,
        contains('развернуто'),
      );

      await tester.drag(
        find.byKey(const ValueKey('magic-sheet-body-scroll')),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      final frameRect = tester.getRect(frame);
      final lastFieldRect = tester.getRect(find.text('Поле 39'));
      final footerRect = tester.getRect(
        find.byKey(const ValueKey('magic-sheet-footer')),
      );
      expect(lastFieldRect.bottom, lessThanOrEqualTo(footerRect.top));
      expect(footerRect.bottom, lessThanOrEqualTo(frameRect.bottom));

      await tester.tap(find.byKey(const ValueKey('magic-sheet-toggle')));
      await tester.pumpAndSettle();
      expect(tester.getSize(frame).height, closeTo(800 * 0.58, 2));
    },
  );

  testWidgets('keyboard inset keeps the last field and sticky action visible', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await _pumpSheetHost(
      tester,
      media: const MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 24),
        viewInsets: EdgeInsets.only(bottom: 320),
      ),
      longContent: true,
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('magic-sheet-toggle')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('magic-sheet-body-scroll')),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();

    final frameRect = tester.getRect(
      find.byKey(const ValueKey('magic-sheet-frame')),
    );
    final footerRect = tester.getRect(
      find.byKey(const ValueKey('magic-sheet-footer')),
    );
    expect(frameRect.bottom, lessThanOrEqualTo(524));
    expect(footerRect.bottom, lessThanOrEqualTo(frameRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short landscape content expands without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 360);
    addTearDown(tester.view.reset);
    await _pumpSheetHost(tester, longContent: false);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('magic-sheet-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('magic-sheet-frame'))).height,
      closeTo(360, 2),
    );
    expect(find.text('Короткое содержимое'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion expands immediately without zero-duration crash',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await _pumpSheetHost(
        tester,
        media: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
        longContent: true,
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('magic-sheet-toggle')));
      await tester.pump();

      expect(find.text('Свернуть'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('magic-sheet-frame'))).height,
        closeTo(844, 2),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpSheetHost(
  WidgetTester tester, {
  required bool longContent,
  MediaQueryData? media,
}) {
  return tester.pumpWidget(
    MaterialApp(
      builder: media == null
          ? null
          : (context, child) => MediaQuery(data: media, child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMagicSheet<void>(
              context,
              title: 'Редактор',
              subtitle: 'Проверка mobile sheet',
              icon: Icons.edit,
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Сохранить'),
                ),
              ],
              builder: (_) => longContent
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < 40; index++)
                          SizedBox(height: 48, child: Text('Поле $index')),
                      ],
                    )
                  : const Text('Короткое содержимое'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}
