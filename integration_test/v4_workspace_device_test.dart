import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  EntityLink link(String id, {EntityLinkType type = EntityLinkType.client}) {
    return EntityLink.typed(entityType: type, entityId: id);
  }

  WorkspaceController controller(String accountId) {
    return WorkspaceController(
      accountId: accountId,
      initialLink: link('home', type: EntityLinkType.report),
      sharedScope: WorkspaceSharedScope(
        session: Object(),
        cache: Object(),
        realtime: Object(),
      ),
    );
  }

  testWidgets(
    'device workspace keeps tabs, restart, accounts and logout safe',
    (tester) async {
      final backend = InMemoryWorkspaceKeyValueStore();
      final store = AccountWorkspaceStore(backend);
      final firstWindow = controller('account-1');
      final secondWindow = controller('account-1');

      for (var index = 1; index < WorkspaceController.maxTabs; index++) {
        firstWindow.open(link('client-$index'), explicitNew: true);
      }
      expect(firstWindow.state.tabs, hasLength(10));
      expect(
        () => firstWindow.open(link('client-10'), explicitNew: true),
        throwsA(isA<WorkspaceLimitReached>()),
      );

      firstWindow.reorderTab(9, 0);
      final reorderedActive = firstWindow.state.activeTabId;
      await store.save(firstWindow.state);
      final restored = await store.restore(
        accountId: 'account-1',
        fallback: controller('account-1').state,
        routeAllowed: (_) => true,
      );
      expect(restored.activeTabId, reorderedActive);
      expect(restored.tabs.first.currentRoute.link.entityId, 'client-9');

      final otherAccount = await store.restore(
        accountId: 'account-2',
        fallback: controller('account-2').state,
        routeAllowed: (_) => true,
      );
      expect(otherAccount.tabs, hasLength(1));
      expect(
        otherAccount.tabs.any(
          (tab) => tab.currentRoute.link.entityId == 'client-9',
        ),
        isFalse,
      );

      final logout = WorkspaceLogoutCoordinator(store)
        ..attach(firstWindow)
        ..attach(secondWindow);
      final stopwatch = Stopwatch()..start();
      await logout.logout('account-1');
      stopwatch.stop();
      expect(firstWindow.state.loggedOut, isTrue);
      expect(secondWindow.state.loggedOut, isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text(
              'workspace-device-pass:${Platform.operatingSystem}',
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      );
      expect(
        find.text('workspace-device-pass:${Platform.operatingSystem}'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Windows linked entities keep ten tabs history restart and logout safe',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 900);
      addTearDown(tester.view.reset);

      const snapshot = CapabilitySnapshot(
        accountId: 'uat-012-director',
        role: 'director',
        accessVersion: 1,
        capabilities: {
          'crm.client.read.basic',
          'schedule.lesson.write',
          'workflow.task.read',
          'commerce.client_finance.read',
          'system.settings.manage',
        },
        scopes: {},
      );
      final entities = <EntityLink>[
        EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: 'student-1',
          variant: 'student',
          presentation: const EntityPresentationReference(
            primary: 'Иванов Иван',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.teacher,
          entityId: 'teacher-1',
          presentation: const EntityPresentationReference(
            primary: 'Петрова Анна',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.lesson,
          entityId: 'lesson-1',
          presentation: const EntityPresentationReference(
            primary: 'Вокал 12 августа',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.group,
          entityId: 'group-1',
          presentation: const EntityPresentationReference(
            primary: 'Младший ансамбль',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.room,
          entityId: 'room-1',
          presentation: const EntityPresentationReference(
            primary: 'Аудитория Рояль',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.branch,
          entityId: 'branch-1',
          presentation: const EntityPresentationReference(
            primary: 'Филиал Центр',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.scheduleSeries,
          entityId: 'series-1',
          presentation: const EntityPresentationReference(
            primary: 'Постоянный план Иванова',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.task,
          entityId: 'task-1',
          presentation: const EntityPresentationReference(
            primary: 'Позвонить родителю',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.payment,
          entityId: 'payment-1',
          presentation: const EntityPresentationReference(
            primary: 'Оплата 4 500 ₽',
          ),
        ),
        EntityLink.typed(
          entityType: EntityLinkType.user,
          entityId: 'user-1',
          presentation: const EntityPresentationReference(
            primary: 'Сидоров Алексей',
          ),
        ),
      ];
      final backend = InMemoryWorkspaceKeyValueStore();
      final store = AccountWorkspaceStore(backend);

      Widget app(Key key, {EntityLink? initialLink}) => ProviderScope(
        overrides: [accountWorkspaceStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: ProductionWorkspaceHost(
              key: key,
              snapshot: snapshot,
              initialLink: initialLink,
              tabBuilder: (context, tab) {
                final currentIndex = entities.indexWhere(
                  (entity) =>
                      entity.rawEntityType ==
                          tab.currentRoute.link.rawEntityType &&
                      entity.entityId == tab.currentRoute.link.entityId,
                );
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Открыта: ${tab.currentRoute.link.entityId}',
                        key: const ValueKey('uat-012-current-entity'),
                      ),
                      if (currentIndex >= 0 &&
                          currentIndex + 1 < entities.length)
                        EntityLinkText(
                          key: ValueKey(
                            'uat-012-open-${entities[currentIndex + 1].entityId}',
                          ),
                          text:
                              entities[currentIndex + 1].presentation!.primary,
                          onPressed: () => navigateEntityLink(
                            context,
                            snapshot,
                            entities[currentIndex + 1],
                            target: EntityOpenTarget.newTab,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        app(const ValueKey('uat-012-first-run'), initialLink: entities.first),
      );
      await tester.pumpAndSettle();

      for (var index = 1; index < entities.length; index++) {
        await tester.tap(
          find.byKey(ValueKey('uat-012-open-${entities[index].entityId}')),
        );
        await tester.pumpAndSettle();
      }

      var shell = tester.widget<DesktopWorkspaceShell>(
        find.byType(DesktopWorkspaceShell),
      );
      expect(shell.controller.state.tabs, hasLength(10));
      expect(
        shell.controller.state.tabs.first.currentRoute.link.entityId,
        'student-1',
      );
      expect(
        shell.controller.state.activeTab.currentRoute.link.entityId,
        'user-1',
      );
      expect(
        find.byKey(const ValueKey('context-ancestor-section:configuration')),
        findsOneWidget,
      );
      expect(find.text('Пользователь · Сидоров Алексей'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('context-ancestor-section:configuration')),
      );
      await tester.pumpAndSettle();
      expect(
        shell.controller.state.activeTab.currentRoute.link.entityId,
        '__section__',
      );

      await tester.tap(find.byKey(const ValueKey('context-back')));
      await tester.pumpAndSettle();
      expect(
        shell.controller.state.activeTab.currentRoute.link.entityId,
        'user-1',
      );
      expect(shell.controller.state.activeTab.forwardStack, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('context-forward')));
      await tester.pumpAndSettle();
      expect(
        shell.controller.state.activeTab.currentRoute.link.entityId,
        '__section__',
      );

      shell.controller.selectTab(shell.controller.state.tabs.first.tabId);
      await tester.pumpAndSettle();
      expect(find.text('Открыта: student-1'), findsOneWidget);
      expect(shell.controller.state.tabs, hasLength(10));

      shell.controller.selectTab(shell.controller.state.tabs.last.tabId);
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(const ValueKey('uat-012-restart')));
      await tester.pumpAndSettle();

      shell = tester.widget<DesktopWorkspaceShell>(
        find.byType(DesktopWorkspaceShell),
      );
      expect(shell.controller.state.tabs, hasLength(10));
      expect(
        shell.controller.state.tabs.first.currentRoute.link.entityId,
        'student-1',
      );
      expect(
        shell.controller.state.activeTab.currentRoute.link.entityId,
        '__section__',
      );
      expect(shell.controller.state.activeTab.routeStack, hasLength(2));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProductionWorkspaceHost)),
      );
      await container
          .read(workspaceLogoutCoordinatorProvider)
          .logout(snapshot.accountId);
      await tester.pumpAndSettle();

      expect(backend.values, isEmpty);
      expect(find.byType(DesktopWorkspaceShell), findsOneWidget);
      expect(shell.controller.state.loggedOut, isTrue);
      expect(
        find.byKey(const ValueKey('uat-012-current-entity')),
        findsNothing,
      );
    },
  );

  testWidgets('device validates the six-role release navigation boundary', (
    tester,
  ) async {
    const roles = [
      'client',
      'teacher',
      'admin',
      'manager',
      'director',
      'system_admin',
    ];
    final desktopTabs = <String, List<int>>{
      for (final role in roles) role: crmVisibleTabs(role, isDesktop: true),
    };
    final mobileTabs = <String, List<int>>{
      for (final role in roles) role: crmVisibleTabs(role, isDesktop: false),
    };

    expect(desktopTabs['client'], isEmpty);
    expect(desktopTabs['teacher'], [0, 1, 2]);
    expect(desktopTabs['admin'], [0, 2, 3, 6]);
    expect(desktopTabs['manager'], isNot(contains(5)));
    expect(desktopTabs['director'], isNot(contains(5)));
    expect(desktopTabs['system_admin'], desktopTabs['director']);
    expect(mobileTabs['manager'], contains(6));
    expect(mobileTabs['manager'], isNot(contains(5)));
    expect(crmHasSchoolFinanceAccess('director'), isTrue);
    expect(crmHasSchoolFinanceAccess('system_admin'), isTrue);
    for (final role in const ['client', 'teacher', 'admin', 'manager']) {
      expect(crmHasSchoolFinanceAccess(role), isFalse, reason: role);
    }

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('six-role-device-pass'))),
    );
    expect(find.text('six-role-device-pass'), findsOneWidget);
  });

  testWidgets('device route stack restores a four-level context chain', (
    tester,
  ) async {
    final workspace = controller('account-1');
    workspace.replaceCurrentLink(
      'tab-1',
      link('student-1'),
      viewState: ContextViewState(
        filters: const {'status': 'active'},
        date: DateTime.utc(2026, 7, 30),
        scrollOffset: 144,
        selectedColumn: 'students',
      ),
    );
    workspace.push('tab-1', link('lesson-1', type: EntityLinkType.lesson));
    workspace.push('tab-1', link('homework-1', type: EntityLinkType.homework));
    workspace.push('tab-1', link('task-1', type: EntityLinkType.task));
    expect(workspace.state.activeTab.routeStack, hasLength(4));

    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    await store.save(workspace.state);
    final restored = await store.restore(
      accountId: 'account-1',
      fallback: controller('account-1').state,
      routeAllowed: (_) => true,
    );
    expect(restored.activeTab.currentRoute.link.entityId, 'task-1');
    expect(
      restored.activeTab.routeStack.first.viewState.filters['status'],
      'active',
    );
    expect(restored.activeTab.routeStack.first.viewState.scrollOffset, 144);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
