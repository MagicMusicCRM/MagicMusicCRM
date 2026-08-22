import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows mouse wheel and Shift+wheel traverse owned axes', (
    tester,
  ) async {
    final vertical = ScrollController();
    final horizontal = ScrollController();
    addTearDown(() {
      vertical.dispose();
      horizontal.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
        ),
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: MagicDesktopScrollbar(
                  axis: Axis.vertical,
                  controller: vertical,
                  builder: (context, controller) => ListView.builder(
                    controller: controller,
                    itemCount: 100,
                    itemExtent: 60,
                    itemBuilder: (context, index) => ColoredBox(
                      color: index.isEven ? Colors.white : Colors.black12,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: MagicDesktopScrollbar(
                  axis: Axis.horizontal,
                  controller: horizontal,
                  builder: (context, controller) => ListView.builder(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    itemCount: 100,
                    itemExtent: 60,
                    itemBuilder: (context, index) => ColoredBox(
                      color: index.isEven ? Colors.white : Colors.black12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(vertical.positions, hasLength(1));
    expect(horizontal.positions, hasLength(1));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(ListView).first)),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await tester.pump();

    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(ListView).last)),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    expect(vertical.offset, greaterThan(0));
    expect(horizontal.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
