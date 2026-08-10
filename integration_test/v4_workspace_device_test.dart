import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
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
