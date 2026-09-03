import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

void main() {
  testWidgets(
    'phone dialog scrolls long content above keyboard with reachable actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      for (final inset in [0.0, 320.0]) {
        var saved = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24),
                viewInsets: EdgeInsets.only(bottom: inset),
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMagicDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Редактирование'),
                    content: SingleChildScrollView(
                      key: const ValueKey('long-dialog-content'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 30; i++)
                            SizedBox(height: 48, child: Text('Строка $i')),
                          const TextField(key: ValueKey('last-dialog-field')),
                        ],
                      ),
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () {
                          saved = true;
                          Navigator.of(context).pop();
                        },
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Сохранить');
        expect(save.hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Развернуть'));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('long-dialog-content')),
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
        final lastField = find.byKey(const ValueKey('last-dialog-field'));
        expect(lastField.hitTestable(), findsOneWidget);
        await tester.enterText(lastField, 'Последняя строка');
        final frame = tester.getRect(
          find.byKey(const ValueKey('magic-sheet-frame')),
        );
        expect(frame.top, greaterThanOrEqualTo(24));
        expect(frame.bottom, lessThanOrEqualTo(844 - inset));
        expect(tester.getRect(save).bottom, lessThanOrEqualTo(frame.bottom));
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('phone dialog close and swipe respect a blocked pop', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    var blocked = 0;
    var canLeave = false;
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showMagicDialog<int>(
                context: context,
                builder: (context) => StatefulBuilder(
                  builder: (context, setLocalState) => PopScope<int>(
                    canPop: canLeave,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) blocked++;
                    },
                    child: AlertDialog(
                      title: const Text('Изменения'),
                      content: const Text('Черновик сохранён в форме'),
                      actions: [
                        TextButton(
                          onPressed: () => setLocalState(() => canLeave = true),
                          child: const Text('Разрешить выход'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('magic-modal-close')));
    await tester.pumpAndSettle();
    expect(blocked, 1);
    await tester.fling(
      find.byKey(const ValueKey('magic-sheet-handle')),
      const Offset(0, 650),
      1500,
    );
    await tester.pumpAndSettle();
    expect(blocked, 2);
    expect(find.text('Черновик сохранён в форме'), findsOneWidget);
    await tester.tap(find.text('Разрешить выход'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('magic-modal-close')));
    await tester.pumpAndSettle();
    expect(find.text('Изменения'), findsNothing);
    expect(result, isNull);
  });

  testWidgets('desktop sheets are centered rounded dialogs with close', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [600.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 900);
      await _pumpSheetHost(
        tester,
        longContent: false,
        platform: TargetPlatform.windows,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final frame = find.byKey(const ValueKey('magic-sheet-frame'));
      expect(tester.getCenter(frame), Offset(width / 2, 450));
      expect(find.byKey(const ValueKey('magic-sheet-handle')), findsNothing);
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      expect(frame, findsNothing);
    }
  });

  testWidgets('phone handle swipe and close dismiss the sheet', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await _pumpSheetHost(tester, longContent: false);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(const ValueKey('magic-sheet-handle')),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsNothing);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsNothing);
  });

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
      expect(find.byTooltip('Свернуть'), findsOneWidget);
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

      expect(find.byTooltip('Свернуть'), findsOneWidget);
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
  TargetPlatform platform = TargetPlatform.android,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
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
