import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';
import 'package:magic_music_crm/core/widgets/v7/v7_nav_shell.dart';
import 'package:magic_music_crm/features/admin/presentation/screens/profile_detail_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/workspace_entity_surface.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';

void main() {
  const snapshot = CapabilitySnapshot(
    accountId: 'account-1',
    role: 'manager',
    accessVersion: 1,
    capabilities: {'crm.client.read.basic'},
    scopes: {},
  );

  testWidgets(
    'desktop production host mounts existing workspace with 10 tabs',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);
      final backend = InMemoryWorkspaceKeyValueStore();
      final store = AccountWorkspaceStore(backend);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [accountWorkspaceStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1200, 800)),
              child: Scaffold(
                body: ProductionWorkspaceHost(
                  snapshot: snapshot,
                  tabBuilder: (_, tab) =>
                      Text('${tab.tabId}:${tab.currentRoute.link.entityId}'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shell = tester.widget<DesktopWorkspaceShell>(
        find.byType(DesktopWorkspaceShell),
      );
      for (var index = 1; index < 10; index++) {
        shell.controller.open(
          EntityLink.typed(
            entityType: EntityLinkType.client,
            entityId: 'client-$index',
            variant: 'student',
          ),
          explicitNew: true,
        );
      }
      await tester.pump();

      expect(shell.controller.state.tabs, hasLength(10));
      expect(find.text('tab-10:client-9'), findsOneWidget);
    },
  );

  testWidgets('compact host keeps one mobile route stack without tab strip', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountWorkspaceStoreProvider.overrideWithValue(
            AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(600, 800)),
            child: Scaffold(
              body: ProductionWorkspaceHost(
                snapshot: snapshot,
                tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DesktopWorkspaceShell), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('desktop direct link reconstructs its canonical context path', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountWorkspaceStoreProvider.overrideWithValue(
            AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ProductionWorkspaceHost(
              snapshot: snapshot,
              initialLink: EntityLink.typed(
                entityType: EntityLinkType.client,
                entityId: 'student-direct',
                variant: 'student',
                presentation: const EntityPresentationReference(
                  primary: 'Иванов Иван',
                ),
              ),
              tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('context-ancestor-section:clients')),
        matching: find.text('Клиенты'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context-current'))).data,
      'Ученик · Иванов Иван',
    );
  });

  testWidgets('a new direct link updates the current workspace history', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.reset);
    final store = AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore());
    const hostKey = ValueKey('stable-workspace');

    Widget app(String id) => ProviderScope(
      overrides: [accountWorkspaceStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: Scaffold(
          body: ProductionWorkspaceHost(
            key: hostKey,
            snapshot: snapshot,
            initialLink: EntityLink.typed(
              entityType: EntityLinkType.client,
              entityId: id,
              variant: 'student',
            ),
            tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app('student-first'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app('student-second'));
    await tester.pumpAndSettle();

    final shell = tester.widget<DesktopWorkspaceShell>(
      find.byType(DesktopWorkspaceShell),
    );
    expect(shell.controller.state.tabs, hasLength(1));
    expect(shell.controller.state.activeTab.routeStack, hasLength(2));
    expect(
      shell.controller.state.activeTab.currentRoute.link.entityId,
      'student-second',
    );
  });

  testWidgets('restart restores permitted tabs and logout clears cache', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);

    Widget app(Key key) => ProviderScope(
      overrides: [accountWorkspaceStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: Scaffold(
          body: ProductionWorkspaceHost(
            key: key,
            snapshot: snapshot,
            tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(const ValueKey('first-run')));
    await tester.pumpAndSettle();
    var shell = tester.widget<DesktopWorkspaceShell>(
      find.byType(DesktopWorkspaceShell),
    );
    shell.controller.open(
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'restored-client',
        variant: 'student',
      ),
      explicitNew: true,
    );
    await tester.pumpAndSettle();
    expect(backend.values, isNotEmpty);

    await tester.pumpWidget(app(const ValueKey('second-run')));
    await tester.pumpAndSettle();
    shell = tester.widget<DesktopWorkspaceShell>(
      find.byType(DesktopWorkspaceShell),
    );
    expect(shell.controller.state.tabs, hasLength(2));
    expect(
      shell.controller.state.activeTab.currentRoute.link.entityId,
      'restored-client',
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductionWorkspaceHost)),
    );
    await container
        .read(workspaceLogoutCoordinatorProvider)
        .logout(snapshot.accountId);
    await tester.pump();
    expect(backend.values, isEmpty);
    expect(
      tester
          .widget<DesktopWorkspaceShell>(find.byType(DesktopWorkspaceShell))
          .controller
          .state
          .loggedOut,
      isTrue,
    );
    expect(find.text('restored-client'), findsNothing);
  });

  testWidgets('role downgrade clears cached privileged tabs', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    const director = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'director',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic', 'commerce.client_finance.read'},
      scopes: {},
    );
    const teacher = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'teacher',
      accessVersion: 2,
      capabilities: {'crm.client.read.basic'},
      scopes: {},
    );

    Widget app(CapabilitySnapshot actor) => ProviderScope(
      overrides: [accountWorkspaceStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: Scaffold(
          body: ProductionWorkspaceHost(
            snapshot: actor,
            tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(director));
    await tester.pumpAndSettle();
    var shell = tester.widget<DesktopWorkspaceShell>(
      find.byType(DesktopWorkspaceShell),
    );
    shell.controller.open(
      EntityLink.typed(
        entityType: EntityLinkType.payment,
        entityId: 'private-payment',
      ),
      explicitNew: true,
    );
    await tester.pumpAndSettle();
    expect(backend.values.values.single, contains('private-payment'));

    await tester.pumpWidget(app(teacher));
    await tester.pumpAndSettle();
    shell = tester.widget<DesktopWorkspaceShell>(
      find.byType(DesktopWorkspaceShell),
    );
    expect(backend.values.values.single, isNot(contains('private-payment')));
    expect(shell.controller.state.tabs, hasLength(1));
    expect(shell.controller.state.activeTab.currentRoute.link.entityId, 'home');
  });

  testWidgets('desktop rail owns section changes for every workspace surface', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountWorkspaceStoreProvider.overrideWithValue(
            AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
          ),
        ],
        child: MaterialApp(
          home: ProductionWorkspaceHost(
            snapshot: snapshot,
            tabBuilder: (_, tab) => Text(
              '${tab.currentRoute.link.rawEntityType}:'
              '${tab.currentRoute.link.entityId}',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(V7NavShell), findsOneWidget);
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();

    expect(find.text('client_status:__section__'), findsOneWidget);
    expect(find.byType(V7NavShell), findsOneWidget);
  });

  test(
    'user links mount profile and permissions inside the same workspace',
    () {
      const settingsSnapshot = CapabilitySnapshot(
        accountId: 'account-1',
        role: 'director',
        accessVersion: 1,
        capabilities: {'system.settings.manage'},
        scopes: {},
      );
      for (final entry in const [
        (focus: 'profile', type: ProfileDetailScreen),
        (focus: 'permissions', type: AccessEditorSheet),
      ]) {
        final surface = buildStaffWorkspaceSurface(
          snapshot: settingsSnapshot,
          route: ContextRouteState(
            link: EntityLink.typed(
              entityType: EntityLinkType.user,
              entityId: 'user-1',
              optionalFocus: EntityLinkFocus(focus: entry.focus),
            ),
            viewState: ContextViewState(),
          ),
          tabId: 'tab-1',
        );
        expect(surface.runtimeType, entry.type);
      }
    },
  );
}
