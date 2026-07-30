import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/workspace/desktop_workspace_shell.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

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

  testWidgets('linked open-new reports the ten-tab limit', (tester) async {
    final workspace = controller();
    for (var index = 1; index < WorkspaceController.maxTabs; index++) {
      workspace.open(link('client-$index'), explicitNew: true);
    }
    var limitReached = false;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceLinkedEntityButton(
          controller: workspace,
          link: link('client-11'),
          label: 'Клиент 11',
          onLimitReached: () => limitReached = true,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('workspace-open-new-client-client-11')),
    );
    expect(limitReached, isTrue);
    expect(workspace.state.tabs, hasLength(10));
  });

  test('reorder is persisted with active selection', () async {
    final workspace = controller();
    workspace.open(link('client-1'));
    workspace.open(link('client-2'));
    final active = workspace.state.activeTabId;
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    final binding = WorkspacePersistenceBinding(
      controller: workspace,
      store: store,
    );

    workspace.reorderTab(2, 0);
    await binding.flush();
    final restored = await store.restore(
      accountId: 'account-1',
      fallback: controller().state,
      routeAllowed: (_) => true,
    );

    expect(restored.activeTabId, active);
    expect(restored.tabs.map((tab) => tab.currentRoute.link.entityId), [
      'client-2',
      'home',
      'client-1',
    ]);
    binding.dispose();
  });

  testWidgets('hover menu duplicates and closes other tabs', (tester) async {
    final workspace = controller();
    final clientTab = workspace.open(link('client-1'), titleHint: 'Клиент');
    workspace.open(link('client-2'), titleHint: 'Другой');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopWorkspaceShell(
            controller: workspace,
            tabBuilder: (context, tab) => Text(tab.titleHint),
          ),
        ),
      ),
    );

    final select = find.byKey(ValueKey('workspace-tab-select-$clientTab'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(select));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('workspace-tab-menu-$clientTab')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workspace-tab-duplicate-$clientTab')),
    );
    await tester.pumpAndSettle();
    expect(workspace.state.tabs, hasLength(4));

    await mouse.moveTo(tester.getCenter(select));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('workspace-tab-menu-$clientTab')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('workspace-tab-close-others-$clientTab')),
    );
    await tester.pumpAndSettle();
    expect(workspace.state.tabs, hasLength(1));
    expect(workspace.state.activeTabId, clientTab);
  });

  test(
    'dirty close supports Save, Discard and Cancel without silent loss',
    () async {
      final workspace = controller();
      String dirtyTab(String id) {
        final tab = workspace.open(link(id), explicitNew: true);
        workspace.registerForm(tab, 'form-$id', draft: {'name': 'draft-$id'});
        workspace.updateForm(tab, 'form-$id', dirty: true);
        return tab;
      }

      final cancelTab = dirtyTab('cancel');
      expect(
        await workspace.closeTab(
          cancelTab,
          resolveDirty: (_) async => DirtyCloseDecision.cancel,
          saveDirty: (_) async => fail('cancel must not save'),
        ),
        isFalse,
      );
      expect(workspace.state.tabs.any((tab) => tab.tabId == cancelTab), isTrue);

      final saved = <String>[];
      final saveTab = dirtyTab('save');
      expect(
        await workspace.closeTab(
          saveTab,
          resolveDirty: (_) async => DirtyCloseDecision.save,
          saveDirty: (tab) async => saved.add(tab.tabId),
        ),
        isTrue,
      );
      expect(saved, [saveTab]);

      final discardTab = dirtyTab('discard');
      expect(
        await workspace.closeTab(
          discardTab,
          resolveDirty: (_) async => DirtyCloseDecision.discard,
          saveDirty: (_) async => fail('discard must not save'),
        ),
        isTrue,
      );
    },
  );
}
