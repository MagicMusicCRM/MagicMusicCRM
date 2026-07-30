import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/mobile_context_stack.dart';
import 'package:magic_music_crm/core/workspace/shared_entity_cache.dart';
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
    'device workspace keeps tabs, conflicts, restart, accounts and logout safe',
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

      final conflictWorkspace = controller('account-1');
      final cleanTab = conflictWorkspace.open(link('shared-client'));
      final dirtyTab = conflictWorkspace.open(
        link('shared-client'),
        explicitNew: true,
      );
      conflictWorkspace.registerForm(
        dirtyTab,
        'client-form',
        expectedVersion: 4,
        draft: const {'name': 'local draft'},
      );
      conflictWorkspace.updateForm(dirtyTab, 'client-form', dirty: true);
      final refetched = <String>[];
      await WorkspaceInvalidationCoordinator(
        workspace: conflictWorkspace,
        cache: SharedEntityCache(),
        refetch: (tabId, _, _) async => refetched.add(tabId),
      ).handle(
        EntityInvalidationEvent(
          eventId: 'device-event',
          link: link('shared-client'),
          version: 5,
        ),
      );
      expect(refetched, [cleanTab]);
      final dirtyForm = conflictWorkspace.state.tabs
          .firstWhere((tab) => tab.tabId == dirtyTab)
          .forms['client-form']!;
      expect(dirtyForm.draft['name'], 'local draft');
      expect(dirtyForm.conflict?.serverVersion, 5);

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
    'device mobile stack restores a four-level chain and authenticated link',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final stack = container.read(mobileContextStackProvider.notifier);
      stack.start(link('student-1'));
      stack.push(
        link('lesson-1', type: EntityLinkType.lesson),
        currentViewState: ContextViewState(
          filters: const {'status': 'active'},
          date: DateTime.utc(2026, 7, 30),
          scrollOffset: 144,
          selectedColumn: 'students',
        ),
      );
      stack.push(link('homework-1', type: EntityLinkType.homework));
      stack.push(link('task-1', type: EntityLinkType.task));
      expect(container.read(mobileContextStackProvider).entries, hasLength(4));

      final serialized = container.read(mobileContextStackProvider).serialize();
      stack.clear();
      stack.restore(serialized);
      expect(
        container.read(mobileContextStackProvider).current?.link.entityId,
        'task-1',
      );
      stack.pop();
      stack.pop();
      stack.pop();
      final root = container.read(mobileContextStackProvider).current!;
      expect(root.viewState.filters['status'], 'active');
      expect(root.viewState.date, DateTime.utc(2026, 7, 30));
      expect(root.viewState.scrollOffset, 144);
      expect(root.viewState.selectedColumn, 'students');

      stack.openAuthenticatedDeepLink(
        home: link('home'),
        target: link('lesson-deep', type: EntityLinkType.lesson),
        authenticated: false,
      );
      expect(
        container.read(mobileContextStackProvider).awaitingAuthentication,
        isTrue,
      );
      stack.completeAuthentication(link('home'));
      final authenticated = container.read(mobileContextStackProvider);
      expect(authenticated.entries, hasLength(2));
      expect(authenticated.current?.link.entityId, 'lesson-deep');

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
