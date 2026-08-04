import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

void main() {
  testWidgets('desktop scrollables always expose a draggable scrollbar', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: ScrollConfiguration(
          behavior: NoGlowScrollBehavior(),
          child: ListView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            children: const [SizedBox(width: 2000, height: 100)],
          ),
        ),
      ),
    );

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.trackVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.bottom);
  });
}
