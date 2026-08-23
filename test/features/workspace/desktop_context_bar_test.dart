import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/magic_context_bar.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';

void main() {
  const snapshot = CapabilitySnapshot(
    accountId: 'account-1',
    role: 'director',
    accessVersion: 1,
    capabilities: {'crm.client.read.basic'},
    scopes: {},
  );

  EntityLink student(String id) => EntityLink.typed(
    entityType: EntityLinkType.client,
    entityId: id,
    variant: 'student',
  );

  WorkspaceController controller() => WorkspaceController(
    accountId: 'account-1',
    initialLink: student('student-1'),
    initialTitle: 'Ученик',
    titleResolver: const EntityPresentationResolver().pageTitle,
    sharedScope: WorkspaceSharedScope(
      session: Object(),
      cache: Object(),
      realtime: Object(),
    ),
  );

  testWidgets('ancestor, Back and Forward stay inside the active tab', (
    tester,
  ) async {
    final workspace = controller();
    final initial = EntityRouteRegistry()
        .resolve(student('student-1'), snapshot)
        .canonicalLocation!;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: workspace,
            builder: (context, _) {
              final tab = workspace.state.activeTab;
              final location = EntityRouteRegistry()
                  .resolve(tab.currentRoute.link, snapshot)
                  .canonicalLocation!;
              return MagicContextBar(
                controller: workspace,
                tab: tab,
                location: location,
              );
            },
          ),
        ),
      ),
    );

    expect(find.text(initial.title), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('context-current')),
        matching: find.byType(TextButton),
      ),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(workspace.state.tabs, hasLength(1));
    expect(workspace.state.activeTab.currentRoute.link.entityId, '__section__');

    await tester.tap(find.byKey(const ValueKey('context-back')));
    await tester.pump();
    expect(workspace.state.activeTab.currentRoute.link.entityId, 'student-1');
    expect(workspace.state.activeTab.forwardStack, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('context-forward')));
    await tester.pump();
    expect(workspace.state.activeTab.currentRoute.link.entityId, '__section__');
  });

  testWidgets('one to eight long nodes fit desktop target widths', (
    tester,
  ) async {
    final workspace = controller();
    final root = EntityLink.typed(
      entityType: EntityLinkType.clientStatus,
      entityId: '__section__',
      optionalFocus: EntityLinkFocus(focus: 'section'),
    );

    for (final width in const [840.0, 1000.0, 1200.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 120);
      final ancestors = [
        for (var index = 0; index < 8; index++)
          AppBreadcrumbNode(
            routeName: 'ancestor-$index',
            title: 'Очень длинное русское название уровня $index',
            location: '/manager?section=clients&level=$index',
            link: root,
          ),
      ];
      final location = CanonicalAppLocation(
        link: student('student-1'),
        routeName: 'entity:student',
        location: '/students/student-1',
        title: 'Текущая карточка ученика с длинным русским заголовком',
        requiredCapabilities: const {'crm.client.read.basic'},
        surfaceKind: AppSurfaceKind.primary,
        ancestors: ancestors,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: MagicContextBar(
                controller: workspace,
                tab: workspace.state.activeTab,
                location: location,
                actions: [
                  MagicContextAction(
                    label: 'Изменить',
                    icon: Icons.edit,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'width=$width');
      expect(find.byKey(const ValueKey('context-path-menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-current')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('context-actions-menu')),
        findsOneWidget,
      );
    }
    addTearDown(tester.view.reset);
  });
}
