import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/v7/v7_nav_shell.dart';

/// Behaviour + layout coverage for the v7 nav shell (KVA-194 / P1-1). Visual
/// fidelity needs on-device review, but this locks: correct destinations,
/// selection callbacks, the «Ещё» overflow (>5 phone tabs), and — importantly —
/// that nothing overflows at phone/desktop sizes (headless can't see pixels).
void main() {
  List<V7NavDestination> dest(int n) => [
        for (var i = 0; i < n; i++)
          V7NavDestination(
            icon: Icons.circle_outlined,
            selectedIcon: Icons.circle,
            label: 'Tab$i',
          ),
      ];

  Widget desktopHost(Widget shell) => MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [shell, const Expanded(child: SizedBox())],
          ),
        ),
      );

  Widget mobileHost(Widget shell) =>
      MaterialApp(home: Scaffold(bottomNavigationBar: shell, body: const SizedBox()));

  testWidgets('desktop rail renders all destinations and reports taps',
      (tester) async {
    int? tapped;
    await tester.pumpWidget(desktopHost(
      V7NavShell(
        isDesktop: true,
        destinations: dest(8),
        selectedIndex: 0,
        onSelected: (i) => tapped = i,
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Tab0'), findsOneWidget);
    expect(find.text('Tab7'), findsOneWidget);

    await tester.tap(find.text('Tab3'));
    expect(tapped, 3);
  });

  testWidgets('phone bar with <=5 destinations shows all, no «Ещё»',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(mobileHost(
      V7NavShell(
        isDesktop: false,
        destinations: dest(5),
        selectedIndex: 0,
        onSelected: (_) {},
      ),
    ));
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(find.text('Tab4'), findsOneWidget);
    expect(find.text('Ещё'), findsNothing);
  });

  testWidgets('phone bar with >5 destinations shows 4 primary + «Ещё» overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int? tapped;
    await tester.pumpWidget(mobileHost(
      V7NavShell(
        isDesktop: false,
        destinations: dest(8),
        selectedIndex: 0,
        onSelected: (i) => tapped = i,
      ),
    ));
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    // 4 primary tabs + «Ещё»; later tabs live in the overflow menu.
    expect(find.text('Tab0'), findsOneWidget);
    expect(find.text('Tab3'), findsOneWidget);
    expect(find.text('Tab4'), findsNothing);
    expect(find.text('Ещё'), findsOneWidget);

    // Opening «Ещё» reveals the overflow items and taps map to the right index.
    await tester.tap(find.text('Ещё'));
    await tester.pumpAndSettle();
    expect(find.text('Tab5'), findsOneWidget);
    await tester.tap(find.text('Tab5'));
    await tester.pumpAndSettle();
    expect(tapped, 5);
  });

  testWidgets('badge count renders on a destination', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(mobileHost(
      V7NavShell(
        isDesktop: false,
        destinations: const [
          V7NavDestination(
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            label: 'Клиенты',
            badgeCount: 7,
          ),
          V7NavDestination(
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            label: 'Чат',
          ),
        ],
        selectedIndex: 0,
        onSelected: (_) {},
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('7'), findsOneWidget);
  });
}
