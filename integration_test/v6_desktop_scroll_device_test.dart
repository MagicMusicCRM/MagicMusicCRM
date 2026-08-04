import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows device drags both owned scrollbar axes', (tester) async {
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
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.drag(find.byType(ListView).last, const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(vertical.offset, greaterThan(0));
    expect(horizontal.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
