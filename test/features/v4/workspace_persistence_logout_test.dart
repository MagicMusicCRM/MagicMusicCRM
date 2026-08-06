import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

void main() {
  EntityLink link(String id) =>
      EntityLink.typed(entityType: EntityLinkType.client, entityId: id);

  WorkspaceController controller(String accountId) => WorkspaceController(
    accountId: accountId,
    initialLink: link('home'),
    sharedScope: WorkspaceSharedScope(
      session: Object(),
      cache: Object(),
      realtime: Object(),
    ),
  );

  test('persists route context and order without dirty form values', () async {
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    final workspace = controller('account-1');
    final clientTab = workspace.open(link('client-1'), titleHint: 'Клиент');
    workspace.updateEntityPresentation(
      link('client-1'),
      const EntityPresentationReference(primary: 'Иванов Иван'),
    );
    workspace.updateCurrentView(
      clientTab,
      ContextViewState(
        filters: const {'status': 'student'},
        date: DateTime.utc(2026, 7, 30),
        scrollOffset: 88,
        selectedColumn: 'active',
      ),
    );
    workspace.registerForm(
      clientTab,
      'secret-form',
      draft: const {'token': 'must-not-persist', 'name': 'dirty-value'},
    );
    workspace.updateForm(clientTab, 'secret-form', dirty: true);

    await store.save(workspace.state);
    final encoded = backend.values.values.single;
    expect(encoded, isNot(contains('must-not-persist')));
    expect(encoded, isNot(contains('dirty-value')));
    expect(jsonDecode(encoded), isA<Map<String, dynamic>>());

    final restored = await store.restore(
      accountId: 'account-1',
      fallback: controller('account-1').state,
      routeAllowed: (_) => true,
    );
    expect(restored.tabs, hasLength(2));
    expect(restored.activeTab.currentRoute.viewState.scrollOffset, 88);
    expect(restored.activeTab.currentRoute.viewState.selectedColumn, 'active');
    expect(
      restored.activeTab.currentRoute.link.presentation?.primary,
      'Иванов Иван',
    );
    expect(restored.activeTab.forms, isEmpty);
  });

  test('persists and restores per-tab Back and Forward history', () async {
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    final workspace = controller('account-1');
    workspace.push('tab-1', link('client-1'));
    workspace.push('tab-1', link('client-2'));
    workspace.back('tab-1');
    await store.save(workspace.state);

    final restored = await store.restore(
      accountId: 'account-1',
      fallback: controller('account-1').state,
      routeAllowed: (_) => true,
    );

    expect(restored.activeTab.currentRoute.link.entityId, 'client-1');
    expect(restored.activeTab.forwardStack.single.link.entityId, 'client-2');
  });

  test('account namespace prevents cross-account restore', () async {
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    final first = controller('account-1')..open(link('private-client'));
    await store.save(first.state);

    final fallback = controller('account-2').state;
    final restored = await store.restore(
      accountId: 'account-2',
      fallback: fallback,
      routeAllowed: (_) => true,
    );
    expect(restored, same(fallback));
    expect(
      restored.tabs.any(
        (tab) => tab.currentRoute.link.entityId == 'private-client',
      ),
      isFalse,
    );
  });

  test('corrupt or capability-forbidden snapshot uses safe fallback', () async {
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    final workspace = controller('account-1')..open(link('forbidden-client'));
    await store.save(workspace.state);
    final fallback = controller('account-1').state;

    final denied = await store.restore(
      accountId: 'account-1',
      fallback: fallback,
      routeAllowed: (candidate) => candidate.entityId != 'forbidden-client',
    );
    expect(denied, same(fallback));

    backend.values[backend.values.keys.single] = '{bad-json';
    final corrupt = await store.restore(
      accountId: 'account-1',
      fallback: fallback,
      routeAllowed: (_) => true,
    );
    expect(corrupt, same(fallback));
  });

  test(
    'global logout clears two windows and persisted state under 2 seconds',
    () async {
      final backend = InMemoryWorkspaceKeyValueStore();
      final store = AccountWorkspaceStore(backend);
      final first = controller('account-1')..open(link('client-1'));
      final second = controller('account-1')..open(link('client-2'));
      await store.save(first.state);
      final coordinator = WorkspaceLogoutCoordinator(store)
        ..attach(first)
        ..attach(second);

      final stopwatch = Stopwatch()..start();
      await coordinator.logout('account-1');
      stopwatch.stop();

      expect(first.state.loggedOut, isTrue);
      expect(second.state.loggedOut, isTrue);
      expect(backend.values, isEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(() => first.open(link('late-event')), throwsA(isA<StateError>()));
    },
  );
}
