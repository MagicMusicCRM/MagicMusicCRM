import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/section_unseen_service.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';
import 'package:magic_music_crm/core/navigation/responsive_navigation_shell.dart';
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

  testWidgets('compact host keeps one mobile route stack with navigation', (
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
    expect(find.byType(ResponsiveNavigationShell), findsOneWidget);
    expect(find.text('Чат'), findsOneWidget);
    expect(find.text('Клиенты'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);

    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();

    expect(find.text('__section__'), findsOneWidget);
    expect(find.byType(ResponsiveNavigationShell), findsOneWidget);
  });

  testWidgets('compact teacher can switch between all assigned surfaces', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    const teacher = CapabilitySnapshot(
      accountId: 'teacher-1',
      role: 'teacher',
      accessVersion: 1,
      capabilities: {'schedule.lesson.read.assigned', 'crm.client.read.basic'},
      scopes: {'schedule': 'assigned', 'client': 'assigned'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountWorkspaceStoreProvider.overrideWithValue(
            AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
          ),
        ],
        child: MaterialApp(
          home: ProductionWorkspaceHost(
            snapshot: teacher,
            tabBuilder: (_, tab) => Text(
              '${tab.currentRoute.link.rawEntityType}:'
              '${tab.currentRoute.link.entityId}',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in const ['Чат', 'Расписание', 'Ученики']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Расписание'));
    await tester.pumpAndSettle();
    expect(find.text('lesson_list:__section__'), findsOneWidget);

    await tester.tap(find.text('Ученики'));
    await tester.pumpAndSettle();
    expect(find.text('client_status:__section__'), findsOneWidget);
  });

  testWidgets('compact direct link wins over a restored clients board', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.reset);
    final store = AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore());

    Widget app({required Key key, EntityLink? initialLink}) => ProviderScope(
      overrides: [accountWorkspaceStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: Scaffold(
          body: ProductionWorkspaceHost(
            key: key,
            snapshot: snapshot,
            initialLink: initialLink,
            tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(key: const ValueKey('persist-board')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      app(
        key: const ValueKey('open-student'),
        initialLink: EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: 'student-direct',
          variant: 'student',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DesktopWorkspaceShell), findsNothing);
    expect(find.text('student-direct'), findsOneWidget);
    expect(find.text('home'), findsNothing);
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

  testWidgets('direct client chat keeps its partner in the workspace route', (
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
          home: ProductionWorkspaceHost(
            snapshot: snapshot,
            tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductionWorkspaceHost)),
    );
    container
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(CrmNavigationRequest.directChat('client-a'));
    await tester.pumpAndSettle();

    final link = tester
        .widget<DesktopWorkspaceShell>(find.byType(DesktopWorkspaceShell))
        .controller
        .state
        .activeTab
        .currentRoute
        .link;
    expect(link.entityType, EntityLinkType.chat);
    expect(link.optionalFocus?.filter['partnerId'], 'client-a');
  });

  testWidgets('schedule requests reuse the canonical Schedule tab', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.reset);
    const scheduleSnapshot = CapabilitySnapshot(
      accountId: 'account-1',
      role: 'manager',
      accessVersion: 1,
      capabilities: {'schedule.lesson.write'},
      scopes: {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountWorkspaceStoreProvider.overrideWithValue(
            AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
          ),
        ],
        child: MaterialApp(
          home: ProductionWorkspaceHost(
            snapshot: scheduleSnapshot,
            tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductionWorkspaceHost)),
    );
    final firstDate = DateTime.utc(2026, 8, 12);
    container
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(
          CrmNavigationRequest.schedule(
            date: firstDate,
            clientType: 'lead',
            clientId: 'lead-1',
          ),
        );
    await tester.pumpAndSettle();

    final shell = tester.widget<DesktopWorkspaceShell>(
      find.byType(DesktopWorkspaceShell),
    );
    expect(shell.controller.state.activeTab.titleHint, 'Расписание');
    expect(
      shell.controller.state.activeTab.currentRoute.link.entityId,
      '__section__',
    );
    expect(
      shell
          .controller
          .state
          .activeTab
          .currentRoute
          .viewState
          .filters['clientId'],
      'lead-1',
    );

    final tabCount = shell.controller.state.tabs.length;
    container
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(
          CrmNavigationRequest.schedule(date: DateTime.utc(2026, 8, 13)),
        );
    await tester.pumpAndSettle();

    expect(shell.controller.state.tabs, hasLength(tabCount));
    expect(shell.controller.state.activeTab.titleHint, 'Расписание');
    expect(
      shell.controller.state.activeTab.currentRoute.viewState.date,
      DateTime.utc(2026, 8, 13),
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

    expect(find.byType(ResponsiveNavigationShell), findsOneWidget);
    await tester.tap(find.text('Клиенты'));
    await tester.pumpAndSettle();

    expect(find.text('client_status:__section__'), findsOneWidget);
    expect(find.byType(ResponsiveNavigationShell), findsOneWidget);
  });

  testWidgets(
    'constrained 839 host routes CRM requests through the mobile authority',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);
      late WorkspaceController controller;
      final router = GoRouter(
        initialLocation: '/manager',
        routes: [
          GoRoute(
            path: '/manager',
            builder: (context, state) => Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 839,
                  child: ProductionWorkspaceHost(
                    snapshot: snapshot,
                    tabBuilder: (context, tab) {
                      controller = WorkspaceNavigationScope.maybeOf(
                        context,
                      )!.controller;
                      return Text(tab.currentRoute.link.entityId);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountWorkspaceStoreProvider.overrideWithValue(
              AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProductionWorkspaceHost)),
      );
      container
          .read(crmNavigationRequestProvider.notifier)
          .navigateTo(
            CrmNavigationRequest(
              link: EntityLink.typed(
                entityType: EntityLinkType.client,
                entityId: 'mobile-client',
                variant: 'student',
              ),
              sourceState: ContextViewState(),
              openInNewTab: true,
            ),
          );
      await tester.pumpAndSettle();

      expect(find.byType(DesktopWorkspaceShell), findsNothing);
      expect(router.state.uri.queryParameters['entityId'], 'mobile-client');
      expect(controller.state.tabs, hasLength(1));
    },
  );

  testWidgets('dirty Save cannot mutate a replacement runtime', (tester) async {
    await _expectDirtyDecisionGuard(tester, actionLabel: 'Сохранить');
  });

  testWidgets('dirty Discard cannot mutate a replacement runtime', (
    tester,
  ) async {
    await _expectDirtyDecisionGuard(tester, actionLabel: 'Не сохранять');
  });

  testWidgets('same section is marked again after workspace identity changes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final actor = ValueNotifier(_workspaceSnapshot('account-a'));
    addTearDown(actor.dispose);
    final marks = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountWorkspaceStoreProvider.overrideWithValue(
            AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
          ),
          sectionUnseenServiceProvider.overrideWith(
            (ref) => _RecordingSectionUnseenService(ref, marks),
          ),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: actor,
            builder: (context, current, _) => ProductionWorkspaceHost(
              snapshot: current,
              initialLink: _studentLink('same-section-client'),
              tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(marks, ['clients']);

    actor.value = _workspaceSnapshot('account-b', accessVersion: 2);
    await tester.pumpAndSettle();

    expect(marks, ['clients', 'clients']);
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

Future<void> _expectDirtyDecisionGuard(
  WidgetTester tester, {
  required String actionLabel,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.reset);
  final actor = ValueNotifier(_workspaceSnapshot('account-a'));
  addTearDown(actor.dispose);
  var replacementSaves = 0;
  var replacementDiscards = 0;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountWorkspaceStoreProvider.overrideWithValue(
          AccountWorkspaceStore(InMemoryWorkspaceKeyValueStore()),
        ),
      ],
      child: MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: actor,
          builder: (context, current, _) => Scaffold(
            body: ProductionWorkspaceHost(
              key: const ValueKey('generation-safe-host'),
              snapshot: current,
              tabBuilder: (_, tab) => Text(tab.currentRoute.link.entityId),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final oldController = tester
      .widget<DesktopWorkspaceShell>(find.byType(DesktopWorkspaceShell))
      .controller;
  final oldTabId = oldController.state.activeTabId;
  oldController.push(oldTabId, _studentLink('old-client'));
  oldController.registerForm(oldTabId, 'editor');
  oldController.updateForm(oldTabId, 'editor', dirty: true);
  await tester.pump();

  await tester.tap(find.byKey(const ValueKey('context-back')));
  await tester.pump();
  expect(find.text('Сохранить изменения?'), findsOneWidget);

  actor.value = _workspaceSnapshot('account-b', accessVersion: 2);
  await tester.pumpAndSettle();
  final replacement = tester
      .widget<DesktopWorkspaceShell>(find.byType(DesktopWorkspaceShell))
      .controller;
  expect(replacement, isNot(same(oldController)));
  final replacementTabId = replacement.state.activeTabId;
  replacement.push(replacementTabId, _studentLink('replacement-client'));
  replacement.registerForm(
    replacementTabId,
    'editor',
    onSave: () async {
      replacementSaves++;
      return true;
    },
    onDiscard: () => replacementDiscards++,
  );
  replacement.updateForm(replacementTabId, 'editor', dirty: true);
  await tester.pump();

  await tester.tap(find.text(actionLabel));
  await tester.pumpAndSettle();

  expect(replacementSaves, 0);
  expect(replacementDiscards, 0);
  expect(
    replacement.state.activeTab.currentRoute.link.entityId,
    'replacement-client',
  );
  expect(replacement.state.activeTab.forms['editor']!.dirty, isTrue);
}

CapabilitySnapshot _workspaceSnapshot(
  String accountId, {
  int accessVersion = 1,
}) => CapabilitySnapshot(
  accountId: accountId,
  role: 'manager',
  accessVersion: accessVersion,
  capabilities: const {'crm.client.read.basic'},
  scopes: const {},
);

EntityLink _studentLink(String id) => EntityLink.typed(
  entityType: EntityLinkType.client,
  entityId: id,
  variant: 'student',
);

class _RecordingSectionUnseenService extends SectionUnseenService {
  _RecordingSectionUnseenService(super.ref, this.marks);

  final List<String> marks;

  @override
  Future<Map<String, int>> unseen() async => const {};

  @override
  Future<void> markSeen(String section) async {
    marks.add(section);
  }
}
