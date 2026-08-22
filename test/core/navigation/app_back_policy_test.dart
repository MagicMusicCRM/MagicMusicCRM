import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/app_back_policy.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

void main() {
  testWidgets('Back closes overlay, route, then local tab state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _LocalHistoryHome()));

    await tester.tap(find.text('Маршрут'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Диалог'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Верхний диалог'), findsNothing);
    expect(find.text('Вложенный маршрут'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Вложенный маршрут'), findsNothing);
    expect(find.text('Локальная история: есть'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Локальная история: закрыта'), findsOneWidget);
  });

  testWidgets('partial and full mobile sheets both dismiss before the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: _SheetHome()));

    await tester.tap(find.text('Лист'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsNothing);
    expect(find.text('Корень'), findsOneWidget);

    await tester.tap(find.text('Лист'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('magic-sheet-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Свернуть'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsNothing);
    expect(find.text('Корень'), findsOneWidget);
  });

  testWidgets('UI Back uses Navigator before desktop tab history', (
    tester,
  ) async {
    final controller = _workspaceController()
      ..push(
        'tab-1',
        EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: 'client-1',
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceNavigationScope(
          controller: controller,
          isDesktop: true,
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const AppBackButton(key: ValueKey('ui-back')),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('Вложенный маршрут')),
                        ),
                      ),
                    ),
                    child: const Text('Маршрут'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Маршрут'));
    await tester.pumpAndSettle();
    expect(controller.state.activeTab.routeStack, hasLength(2));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ui-back')), findsOneWidget);
    expect(controller.state.activeTab.routeStack, hasLength(2));

    await tester.tap(find.byKey(const ValueKey('ui-back')));
    await tester.pumpAndSettle();
    expect(controller.state.activeTab.routeStack, hasLength(1));
  });

  testWidgets(
    'deep-link return preserves source and falls back only when cold',
    (tester) async {
      final router = _deepLinkRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      await tester.tap(find.text('Открыть deep link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Закрыть deep link'));
      await tester.pumpAndSettle();
      expect(find.text('Источник'), findsOneWidget);

      router.go('/detail');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Закрыть deep link'));
      await tester.pumpAndSettle();
      expect(find.text('Источник'), findsOneWidget);
    },
  );
}

GoRouter _deepLinkRouter() => GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, _) => Scaffold(
        body: Column(
          children: [
            const Text('Источник'),
            FilledButton(
              onPressed: () => context.push('/detail'),
              child: const Text('Открыть deep link'),
            ),
          ],
        ),
      ),
    ),
    GoRoute(
      path: '/detail',
      builder: (context, _) => Scaffold(
        body: FilledButton(
          onPressed: () =>
              returnFromDeepLink(context, fallbackLocation: '/home'),
          child: const Text('Закрыть deep link'),
        ),
      ),
    ),
  ],
);

class _LocalHistoryHome extends StatefulWidget {
  const _LocalHistoryHome();

  @override
  State<_LocalHistoryHome> createState() => _LocalHistoryHomeState();
}

class _LocalHistoryHomeState extends State<_LocalHistoryHome> {
  var _hasHistory = true;

  @override
  Widget build(BuildContext context) {
    return AppBackScope(
      hasLocalHistory: _hasHistory,
      onBack: () => setState(() => _hasHistory = false),
      child: Scaffold(
        body: Column(
          children: [
            Text('Локальная история: ${_hasHistory ? 'есть' : 'закрыта'}'),
            FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const _NestedRoute()),
              ),
              child: const Text('Маршрут'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NestedRoute extends StatelessWidget {
  const _NestedRoute();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Вложенный маршрут'),
          FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(title: Text('Верхний диалог')),
            ),
            child: const Text('Диалог'),
          ),
        ],
      ),
    );
  }
}

class _SheetHome extends StatelessWidget {
  const _SheetHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Корень'),
          FilledButton(
            onPressed: () => showMagicSheet<void>(
              context,
              title: 'Проверка Back',
              builder: (_) => const SizedBox(height: 700),
            ),
            child: const Text('Лист'),
          ),
        ],
      ),
    );
  }
}

WorkspaceController _workspaceController() => WorkspaceController(
  accountId: 'account-1',
  initialLink: EntityLink.typed(
    entityType: EntityLinkType.chat,
    entityId: 'home',
  ),
  titleResolver: const EntityPresentationResolver().pageTitle,
  sharedScope: WorkspaceSharedScope(
    session: Object(),
    cache: Object(),
    realtime: Object(),
  ),
);
