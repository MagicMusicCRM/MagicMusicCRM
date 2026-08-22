import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';

void main() {
  testWidgets(
    'desktop owns one position and exposes a draggable vertical bar',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _Harness(
          platform: TargetPlatform.windows,
          child: MagicDesktopScrollbar(
            axis: Axis.vertical,
            controller: controller,
            builder: (context, ownedController) => SingleChildScrollView(
              controller: ownedController,
              child: const SizedBox(width: 800, height: 4000),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<Scrollbar>(
        find.byKey(const ValueKey('magic-desktop-scrollbar-vertical')),
      );
      expect(bar.thumbVisibility, isTrue);
      expect(bar.trackVisibility, isTrue);
      expect(bar.interactive, isTrue);
      expect(controller.positions, hasLength(1));

      final bounds = tester.getRect(find.byType(MagicDesktopScrollbar));
      await _dragMouse(
        tester,
        from: Offset(bounds.right - 5, bounds.top + 45),
        to: Offset(bounds.right - 5, bounds.bottom - 45),
      );
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        greaterThan(controller.position.maxScrollExtent / 2),
      );
    },
  );

  testWidgets('desktop horizontal thumb is mouse-draggable', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _Harness(
        platform: TargetPlatform.windows,
        child: MagicDesktopScrollbar(
          axis: Axis.horizontal,
          controller: controller,
          builder: (context, ownedController) => SingleChildScrollView(
            controller: ownedController,
            scrollDirection: Axis.horizontal,
            child: const SizedBox(width: 4000, height: 600),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.positions, hasLength(1));
    final bounds = tester.getRect(find.byType(MagicDesktopScrollbar));
    await _dragMouse(
      tester,
      from: Offset(bounds.left + 45, bounds.bottom - 5),
      to: Offset(bounds.right - 45, bounds.bottom - 5),
    );
    await tester.pumpAndSettle();

    expect(
      controller.offset,
      greaterThan(controller.position.maxScrollExtent / 2),
    );
  });

  testWidgets('mobile does not render a persistent desktop bar', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _Harness(
        platform: TargetPlatform.android,
        child: SizedBox(
          width: 300,
          height: 200,
          child: MagicDesktopScrollbar(
            axis: Axis.vertical,
            controller: controller,
            builder: (context, ownedController) => ListView.builder(
              controller: ownedController,
              itemCount: 50,
              itemBuilder: (context, index) => Text('Строка $index'),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('magic-desktop-scrollbar-vertical')),
      findsNothing,
    );
    expect(controller.positions, hasLength(1));
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('nested wheel keeps vertical ownership and Shift moves board', (
    tester,
  ) async {
    final page = ScrollController();
    final board = ScrollController();
    final column = ScrollController();
    addTearDown(page.dispose);
    addTearDown(board.dispose);
    addTearDown(column.dispose);

    await tester.pumpWidget(
      _Harness(
        platform: TargetPlatform.windows,
        child: MagicDesktopScrollbar(
          axis: Axis.vertical,
          controller: page,
          builder: (context, pageController) => SingleChildScrollView(
            controller: pageController,
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: MagicDesktopScrollbar(
                    axis: Axis.horizontal,
                    controller: board,
                    builder: (context, boardController) =>
                        SingleChildScrollView(
                          controller: boardController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: 1200,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                key: const ValueKey('nested-column'),
                                width: 300,
                                child: MagicDesktopScrollbar(
                                  axis: Axis.vertical,
                                  controller: column,
                                  builder: (context, columnController) =>
                                      ListView.builder(
                                        controller: columnController,
                                        itemExtent: 40,
                                        itemCount: 100,
                                        itemBuilder: (context, index) =>
                                            Text('Карточка $index'),
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final columnCenter = tester.getCenter(
      find.byKey(const ValueKey('nested-column')),
    );
    pointer.hover(columnCenter);

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
    await tester.pump();
    expect(column.offset, greaterThan(0));
    expect(board.offset, 0);
    expect(page.offset, 0);

    column.jumpTo(0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(column.offset, 0);
    expect(board.offset, greaterThan(0));
    expect(page.offset, 0);

    board.jumpTo(0);
    column.jumpTo(column.position.maxScrollExtent);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
    await tester.pump();
    expect(column.offset, column.position.maxScrollExtent);
    expect(page.offset, greaterThan(0));
  });
}

Future<void> _dragMouse(
  WidgetTester tester, {
  required Offset from,
  required Offset to,
}) async {
  final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  await mouse.moveTo(to);
  await tester.pumpAndSettle();
  await mouse.up();
}

class _Harness extends StatelessWidget {
  const _Harness({required this.platform, required this.child});

  final TargetPlatform platform;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(platform: platform),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      home: Scaffold(body: child),
    );
  }
}
