import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/core/widgets/magic_drawer.dart';
import 'package:magic_music_crm/core/widgets/magic_menu.dart';
import 'package:magic_music_crm/core/widgets/magic_shimmer.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';

/// Smoke coverage for the P0 shared v7 component library (KVA-193). These
/// widgets are not mounted in app screens yet, so this locks their basic
/// build + interaction correctness before reskin phases adopt them.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('SkeletonBox renders a static box under reduced motion',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(
            body: Center(child: SkeletonBox(width: 100, height: 16)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonBox), findsOneWidget);
    // Dispose the widget tree to release the animation controller cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('showMagicSheet shows title/footer and pops the chosen value',
      (tester) async {
    int? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showMagicSheet<int>(
                context,
                title: 'Добавить расход',
                subtitle: 'Подзаголовок',
                icon: Icons.payments_outlined,
                builder: (_) => const Text('тело'),
                actions: [
                  Builder(
                    builder: (sheetContext) => FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(42),
                      child: const Text('Сохранить'),
                    ),
                  ),
                ],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить расход'), findsOneWidget);
    expect(find.text('тело'), findsOneWidget);

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Добавить расход'), findsNothing);
    expect(result, 42);
  });

  testWidgets('showMagicDrawer opens and closes', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showMagicDrawer<void>(
              context,
              title: 'Карточка клиента',
              builder: (_) => const Text('drawer-body'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Карточка клиента'), findsOneWidget);
    expect(find.text('drawer-body'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Карточка клиента'), findsNothing);
  });

  testWidgets('showMagicMenu shows items and returns the tapped value',
      (tester) async {
    String? picked;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showMagicMenu<String>(
                context,
                globalPosition: const Offset(120, 120),
                items: const [
                  MagicMenuItem(
                    value: 'edit',
                    label: 'Изменить',
                    icon: Icons.edit_outlined,
                  ),
                  MagicMenuItem(
                    value: 'delete',
                    label: 'Удалить',
                    icon: Icons.delete_outline,
                    danger: true,
                  ),
                ],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Изменить'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(picked, 'delete');
  });

  testWidgets('MagicToast inserts and dismisses an overlay toast',
      (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => MagicToast.show(
              context,
              'Сохранено',
              detail: 'Изменения применены',
              type: MagicToastType.success,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump(); // insert
    await tester.pump(const Duration(milliseconds: 200)); // enter animation
    expect(find.text('Сохранено'), findsOneWidget);

    MagicToast.dismiss();
    await tester.pump();
    expect(find.text('Сохранено'), findsNothing);
  });
}
