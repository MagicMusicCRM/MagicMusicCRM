import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';

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
