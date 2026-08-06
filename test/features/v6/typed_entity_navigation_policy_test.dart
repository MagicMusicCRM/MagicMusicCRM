import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

void main() {
  const snapshot = CapabilitySnapshot(
    accountId: 'account-1',
    role: 'director',
    accessVersion: 1,
    capabilities: {
      'crm.client.read.basic',
      'crm.client.write',
      'crm.comment.read.shared',
      'schedule.lesson.read.assigned',
      'schedule.lesson.write',
      'workflow.task.read',
      'commerce.client_finance.read',
      'commerce.package.read',
      'system.settings.manage',
      'report.status.read',
    },
    scopes: {},
  );

  WorkspaceController controller() => WorkspaceController(
    accountId: 'account-1',
    initialLink: EntityLink.typed(
      entityType: EntityLinkType.chat,
      entityId: 'home',
    ),
    sharedScope: WorkspaceSharedScope(
      session: Object(),
      cache: Object(),
      realtime: Object(),
    ),
    titleResolver: const EntityPresentationResolver().pageTitle,
  );

  testWidgets(
    'all typed entities use current-tab history or explicit new tab',
    (tester) async {
      final workspace = controller();
      final navigationKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceNavigationScope(
              controller: workspace,
              isDesktop: true,
              child: SizedBox(key: navigationKey),
            ),
          ),
        ),
      );

      final links = <EntityLink>[
        EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: 'student-1',
          variant: 'student',
          presentation: const EntityPresentationReference(
            primary: 'Иванов Иван',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: 'lead-1',
          variant: 'lead',
        ),
        EntityLink.typed(
          entityType: EntityLinkType.lesson,
          entityId: 'lesson-1',
        ),
        EntityLink.typed(entityType: EntityLinkType.task, entityId: 'task-1'),
        EntityLink.typed(
          entityType: EntityLinkType.subscription,
          entityId: 'subscription-1',
        ),
        EntityLink.typed(
          entityType: EntityLinkType.payment,
          entityId: 'payment-1',
        ),
        EntityLink.typed(entityType: EntityLinkType.user, entityId: 'user-1'),
        EntityLink.typed(
          entityType: EntityLinkType.homework,
          entityId: 'homework-1',
        ),
        EntityLink.typed(entityType: EntityLinkType.chat, entityId: 'chat-1'),
        EntityLink.typed(
          entityType: EntityLinkType.report,
          entityId: 'report-1',
        ),
        EntityLink.typed(
          entityType: EntityLinkType.teacher,
          entityId: 'teacher-1',
        ),
        EntityLink.typed(entityType: EntityLinkType.group, entityId: 'group-1'),
        EntityLink.typed(entityType: EntityLinkType.room, entityId: 'room-1'),
        EntityLink.typed(
          entityType: EntityLinkType.branch,
          entityId: 'branch-1',
        ),
        EntityLink.typed(
          entityType: EntityLinkType.scheduleSeries,
          entityId: 'series-1',
        ),
        EntityLink.typed(
          entityType: EntityLinkType.comment,
          entityId: 'comment-1',
        ),
        EntityLink.typed(
          entityType: EntityLinkType.clientSource,
          entityId: 'source-1',
        ),
        EntityLink.typed(
          entityType: EntityLinkType.clientStatus,
          entityId: 'status-1',
        ),
        EntityLink.typed(
          entityType: EntityLinkType.subscriptionPackage,
          entityId: 'package-1',
        ),
      ];

      for (var index = 0; index < links.length; index++) {
        final resolution = await navigateEntityLink(
          navigationKey.currentContext!,
          snapshot,
          links[index],
          sourceViewState: index == 0
              ? ContextViewState(
                  filters: const {'branch': 'branch-1'},
                  scrollOffset: 84,
                )
              : null,
        );
        expect(resolution.state, EntityRouteState.resolved);
        expect(
          resolution.location,
          startsWith('/manager?'),
          reason: links[index].rawEntityType,
        );
        expect(workspace.state.activeTab.currentRoute.link, same(links[index]));
      }

      expect(workspace.state.tabs, hasLength(1));
      expect(workspace.state.activeTab.routeStack, hasLength(links.length + 1));
      for (var index = 0; index < links.length; index++) {
        workspace.back('tab-1');
      }
      expect(
        workspace.state.activeTab.currentRoute.viewState.filters['branch'],
        'branch-1',
      );
      expect(workspace.state.activeTab.currentRoute.viewState.scrollOffset, 84);

      await navigateEntityLink(
        navigationKey.currentContext!,
        snapshot,
        links.first,
        target: EntityOpenTarget.newTab,
      );
      expect(workspace.state.tabs, hasLength(2));
      expect(workspace.state.activeTab.currentRoute.link, same(links.first));
      expect(workspace.state.activeTab.titleHint, 'Ученик · Иванов Иван');
    },
  );

  testWidgets('forbidden, missing and tombstone states share one safe result', (
    tester,
  ) async {
    final workspace = controller();
    final navigationKey = GlobalKey();
    const teacher = CapabilitySnapshot(
      accountId: 'teacher-1',
      role: 'teacher',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic'},
      scopes: {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceNavigationScope(
            controller: workspace,
            isDesktop: true,
            child: SizedBox(key: navigationKey),
          ),
        ),
      ),
    );

    final forbidden = await navigateEntityLink(
      navigationKey.currentContext!,
      teacher,
      EntityLink.typed(
        entityType: EntityLinkType.payment,
        entityId: 'secret-payment',
      ),
    );
    final missing = await navigateEntityLink(
      navigationKey.currentContext!,
      teacher,
      EntityLink.fromJson(const {'entityType': 'unknown', 'entityId': 'x'}),
    );
    final tombstone = await navigateEntityLink(
      navigationKey.currentContext!,
      teacher,
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'archived-client',
      ),
      lifecycle: EntityLifecycleState.archived,
    );
    final deleted = await navigateEntityLink(
      navigationKey.currentContext!,
      teacher,
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'deleted-client',
      ),
      lifecycle: EntityLifecycleState.deleted,
    );
    await tester.pump();

    expect(forbidden.state, EntityRouteState.forbidden);
    expect(missing.state, EntityRouteState.unknown);
    expect(tombstone.state, EntityRouteState.archived);
    expect(deleted.state, EntityRouteState.deleted);
    expect(workspace.state.activeTab.routeStack, hasLength(1));
    expect(find.text('Связанная запись недоступна.'), findsOneWidget);
    expect(find.textContaining('secret-payment'), findsNothing);
    expect(find.textContaining('archived-client'), findsNothing);
    expect(find.textContaining('deleted-client'), findsNothing);
  });

  testWidgets('compact policy uses the mobile router stack', (tester) async {
    final workspace = controller();
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => WorkspaceNavigationScope(
            controller: workspace,
            isDesktop: false,
            child: Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => navigateEntityLink(
                    context,
                    snapshot,
                    EntityLink.typed(
                      entityType: EntityLinkType.client,
                      entityId: 'student-mobile',
                      variant: 'student',
                    ),
                  ),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/manager',
          builder: (context, state) => Scaffold(
            body: Text(
              '${state.uri.queryParameters['section']}:'
              '${state.uri.queryParameters['entityType']}:'
              '${state.uri.queryParameters['entityId']}',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('clients:student:student-mobile'), findsOneWidget);
    expect(workspace.state.activeTab.routeStack, hasLength(1));

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Открыть'), findsOneWidget);
  });
}
