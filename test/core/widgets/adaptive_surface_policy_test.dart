import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';

void main() {
  test('declarative policy covers 360, 600 and 840 widths', () {
    for (final width in const [360.0, 600.0, 839.0]) {
      expect(
        AdaptiveSurfacePolicy.containerFor(AppSurfaceKind.primary, width),
        AdaptiveSurfaceContainer.route,
      );
      expect(
        AdaptiveSurfacePolicy.containerFor(AppSurfaceKind.comparison, width),
        AdaptiveSurfaceContainer.route,
      );
      expect(
        AdaptiveSurfacePolicy.containerFor(AppSurfaceKind.quickView, width),
        AdaptiveSurfaceContainer.sheet,
      );
      expect(
        AdaptiveSurfacePolicy.containerFor(AppSurfaceKind.selection, width),
        AdaptiveSurfaceContainer.sheet,
      );
      expect(
        AdaptiveSurfacePolicy.containerFor(AppSurfaceKind.confirmation, width),
        AdaptiveSurfaceContainer.sheet,
      );
    }
    expect(
      AdaptiveSurfacePolicy.containerFor(AppSurfaceKind.quickView, 840),
      AdaptiveSurfaceContainer.dialog,
    );
    expect(
      AdaptiveSurfacePolicy.containerFor(AppSurfaceKind.selection, 840),
      AdaptiveSurfaceContainer.dialog,
    );
  });

  testWidgets('Client and Payment primary jobs reuse their route callback', (
    tester,
  ) async {
    var routeCalls = 0;
    var contentBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              await showMagicAdaptiveSurface<void>(
                context,
                kind: AppSurfaceKind.primary,
                title: 'Карточка клиента / Оплата',
                builder: (_) {
                  contentBuilds++;
                  return const Text('duplicate-content');
                },
                openRoute: () async {
                  routeCalls++;
                },
              );
            },
            child: const Text('Открыть primary'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть primary'));
    await tester.pump();
    expect(routeCalls, 1);
    expect(contentBuilds, 0);
    expect(find.text('duplicate-content'), findsNothing);
  });

  testWidgets(
    'Lesson quick view opens one surface and returns from both devices',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final width in const [360.0, 600.0, 839.0, 840.0]) {
        tester.view.physicalSize = Size(width, 720);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              platform: width >= 840
                  ? TargetPlatform.windows
                  : TargetPlatform.android,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showMagicAdaptiveSurface<void>(
                    context,
                    kind: AppSurfaceKind.quickView,
                    title: 'Занятие',
                    subtitle: 'Краткий просмотр',
                    icon: Icons.calendar_today,
                    builder: (surfaceContext) {
                      return FilledButton(
                        onPressed: () => Navigator.pop(surfaceContext),
                        child: const Text('Закрыть занятие'),
                      );
                    },
                  ),
                  child: const Text('Открыть занятие'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Открыть занятие'));
        await tester.pumpAndSettle();
        expect(
          find.text('Закрыть занятие'),
          findsOneWidget,
          reason: 'width=$width',
        );
        expect(find.text('Занятие'), findsOneWidget);
        expect(find.byTooltip('Закрыть'), findsOneWidget);

        await tester.tap(find.text('Закрыть занятие'));
        await tester.pumpAndSettle();
        expect(find.text('Занятие'), findsNothing);
      }
    },
  );

  testWidgets('short confirmation stays a modal decision', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showMagicAdaptiveSurface<void>(
                context,
                kind: AppSurfaceKind.confirmation,
                title: 'Удалить запись?',
                builder: (dialogContext) => TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Отменить'),
                ),
              ),
              child: const Text('Открыть confirmation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть confirmation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsOneWidget);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsNothing);
  });
}
