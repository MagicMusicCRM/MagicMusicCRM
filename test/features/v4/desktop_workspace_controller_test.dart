import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';

void main() {
  EntityLink link(String id) =>
      EntityLink.typed(entityType: EntityLinkType.client, entityId: id);

  WorkspaceController controller() => WorkspaceController(
    accountId: 'account-1',
    initialLink: link('home'),
    sharedScope: WorkspaceSharedScope(
      session: Object(),
      cache: Object(),
      realtime: Object(),
    ),
  );

  test(
    'normal open focuses existing entity and explicit new duplicates it',
    () {
      final workspace = controller();
      final first = workspace.open(link('client-1'));
      final focused = workspace.open(link('client-1'));
      final duplicate = workspace.open(link('client-1'), explicitNew: true);

      expect(focused, first);
      expect(duplicate, isNot(first));
      expect(workspace.state.tabs, hasLength(3));
      expect(workspace.state.activeTabId, duplicate);
    },
  );

  test('route and form state remain isolated per tab', () {
    final workspace = controller();
    final first = workspace.open(link('client-1'));
    final second = workspace.open(link('client-2'));

    workspace.push(
      first,
      EntityLink.typed(entityType: EntityLinkType.lesson, entityId: 'lesson-1'),
      currentViewState: ContextViewState(
        filters: const {'status': 'lead'},
        scrollOffset: 120,
      ),
    );
    workspace.registerForm(first, 'client-form', expectedVersion: 4);
    workspace.updateForm(
      first,
      'client-form',
      dirty: true,
      draft: const {'name': 'Локальный ввод'},
    );

    expect(
      workspace.state.tabs.firstWhere((tab) => tab.tabId == first).routeStack,
      hasLength(2),
    );
    expect(
      workspace.state.tabs.firstWhere((tab) => tab.tabId == second).routeStack,
      hasLength(1),
    );
    expect(
      workspace.state.tabs.firstWhere((tab) => tab.tabId == first).forms,
      contains('client-form'),
    );
    expect(
      workspace.state.tabs.firstWhere((tab) => tab.tabId == second).forms,
      isEmpty,
    );
  });

  testWidgets('top strip switches tabs without replacing shared scope', (
    tester,
  ) async {
    final workspace = controller();
    final shared = workspace.sharedScope;
    workspace.open(link('client-1'), titleHint: 'Клиент');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopWorkspaceShell(
            controller: workspace,
            tabBuilder: (context, tab) => Text(
              '${tab.currentRoute.link.entityId}:'
              '${identical(shared, workspace.sharedScope)}',
            ),
          ),
        ),
      ),
    );

    expect(find.text('client-1:true'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
    await tester.pump();
    expect(find.text('home:true'), findsOneWidget);
    expect(workspace.sharedScope, same(shared));
  });

  test('workspace rejects an eleventh tab', () {
    final workspace = controller();
    for (var index = 1; index < WorkspaceController.maxTabs; index++) {
      workspace.open(link('client-$index'), explicitNew: true);
    }

    expect(
      () => workspace.open(link('client-11'), explicitNew: true),
      throwsA(isA<WorkspaceLimitReached>()),
    );
    expect(workspace.state.tabs, hasLength(10));
  });
}
