import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

void main() {
  EntityLink link(String id) =>
      EntityLink.typed(entityType: EntityLinkType.client, entityId: id);

  WorkspaceController controller(String accountId) => WorkspaceController(
    accountId: accountId,
    initialLink: link('home'),
    titleResolver: const EntityPresentationResolver().pageTitle,
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

  test('restores encrypted client-card draft with its base version', () async {
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    final workspace = controller('account-1');
    final clientTab = workspace.open(link('client-1'), titleHint: 'Клиент');
    const formKey = 'client-card:lead:client-1';
    workspace.registerForm(
      clientTab,
      formKey,
      expectedVersion: 7,
      draft: const {
        'schemaVersion': 1,
        'entityType': 'lead',
        'entityId': 'client-1',
        'lead': {
          'expectedVersion': 7,
          'core': {'phone': '+79990001122'},
        },
      },
    );
    workspace.updateForm(clientTab, formKey, dirty: true, expectedVersion: 7);

    await store.save(workspace.state);
    final restored = await store.restore(
      accountId: 'account-1',
      fallback: controller('account-1').state,
      routeAllowed: (_) => true,
    );

    final form = restored.activeTab.forms[formKey];
    expect(form?.dirty, isTrue);
    expect(form?.expectedVersion, 7);
    expect(
      ((form?.draft['lead'] as Map)['core'] as Map)['phone'],
      '+79990001122',
    );
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
    'suspended binding buffers only the latest state until resume',
    () async {
      final backend = _CountingWorkspaceStore();
      final store = AccountWorkspaceStore(backend);
      final workspace = controller('account-1');
      final binding = WorkspacePersistenceBinding(
        controller: workspace,
        store: store,
      )..suspend();
      addTearDown(binding.dispose);
      addTearDown(workspace.dispose);

      workspace.push('tab-1', link('client-1'));
      workspace.push('tab-1', link('client-2'));
      await binding.flush();

      expect(backend.values, isEmpty);
      expect(backend.writeCount, 0);

      binding.resume();
      await binding.flush();

      expect(backend.writeCount, 1);
      expect(backend.values.values.single, contains('client-2'));
    },
  );

  test(
    'global logout clears two windows and persisted state under 2 seconds',
    () async {
      final backend = InMemoryWorkspaceKeyValueStore();
      final store = AccountWorkspaceStore(backend);
      final first = controller('account-1')..open(link('client-1'));
      final second = controller('account-1')..open(link('client-2'));
      await store.save(first.state);
      final firstBinding = WorkspacePersistenceBinding(
        controller: first,
        store: store,
      );
      final secondBinding = WorkspacePersistenceBinding(
        controller: second,
        store: store,
      );
      addTearDown(firstBinding.dispose);
      addTearDown(secondBinding.dispose);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final coordinator = WorkspaceLogoutCoordinator(store)
        ..attach(first)
        ..attach(second);

      final stopwatch = Stopwatch()..start();
      await coordinator.logout('account-1');
      await Future.wait([firstBinding.flush(), secondBinding.flush()]);
      stopwatch.stop();

      expect(first.state.loggedOut, isTrue);
      expect(second.state.loggedOut, isTrue);
      expect(backend.values, isEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(() => first.open(link('late-event')), throwsA(isA<StateError>()));
    },
  );

  test('global logout saves every dirty window and fails closed', () async {
    final backend = InMemoryWorkspaceKeyValueStore();
    final store = AccountWorkspaceStore(backend);
    final first = controller('account-1');
    final second = controller('account-1');
    final saves = <String>[];
    first.registerForm(
      first.state.activeTabId,
      'first',
      onSave: () async {
        saves.add('first');
        return true;
      },
    );
    second.registerForm(
      second.state.activeTabId,
      'second',
      onSave: () async {
        saves.add('second');
        return false;
      },
    );
    first.updateForm(first.state.activeTabId, 'first', dirty: true);
    second.updateForm(second.state.activeTabId, 'second', dirty: true);
    final coordinator = WorkspaceLogoutCoordinator(store)
      ..attach(first)
      ..attach(second);

    await expectLater(coordinator.logoutAll(), throwsA(isA<StateError>()));

    expect(saves, containsAll(['first', 'second']));
    expect(first.state.loggedOut, isFalse);
    expect(second.state.loggedOut, isFalse);
    expect(second.state.activeTab.hasDirtyForms, isTrue);
  });

  test(
    'forced logout preserves a local draft and never waits for network save',
    () async {
      final backend = InMemoryWorkspaceKeyValueStore();
      final store = AccountWorkspaceStore(backend);
      final workspace = controller('account-1');
      const formKey = 'client-card:lead:home';
      var networkSaveCalls = 0;
      workspace.registerForm(
        workspace.state.activeTabId,
        formKey,
        expectedVersion: 3,
        draft: const {
          'schemaVersion': 1,
          'entityType': 'lead',
          'entityId': 'home',
          'lead': {
            'expectedVersion': 3,
            'core': {'firstName': 'Черновик'},
          },
        },
        onSave: () async {
          networkSaveCalls++;
          return false;
        },
      );
      workspace.updateForm(
        workspace.state.activeTabId,
        formKey,
        dirty: true,
        expectedVersion: 3,
      );
      final binding = WorkspacePersistenceBinding(
        controller: workspace,
        store: store,
      );
      addTearDown(binding.dispose);
      addTearDown(workspace.dispose);
      final coordinator = WorkspaceLogoutCoordinator(store)..attach(workspace);

      await coordinator.forceLogoutAllPreservingDrafts();
      await binding.flush();

      final restored = await store.restore(
        accountId: 'account-1',
        fallback: controller('account-1').state,
        routeAllowed: (_) => true,
      );

      expect(networkSaveCalls, 0);
      expect(workspace.state.loggedOut, isTrue);
      expect(backend.values.values.single, contains('Черновик'));
      expect(restored.activeTab.forms[formKey]?.dirty, isTrue);
      expect(
        ((restored.activeTab.forms[formKey]?.draft['lead'] as Map)['core']
            as Map)['firstName'],
        'Черновик',
      );
    },
  );
}

class _CountingWorkspaceStore extends InMemoryWorkspaceKeyValueStore {
  var writeCount = 0;

  @override
  Future<void> write(String key, String value) {
    writeCount++;
    return super.write(key, value);
  }
}
