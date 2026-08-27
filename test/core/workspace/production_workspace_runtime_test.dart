import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_runtime.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

void main() {
  test(
    'dispose rejects a delayed restore and tears down every owner once',
    () async {
      final storage = _ControlledWorkspaceStorage()..blockNextRead();
      final store = AccountWorkspaceStore(storage);
      await _seedClient(
        store,
        accountId: 'account-a',
        clientId: 'stale-client',
      );
      final lifecycle = <String>[];
      final logout = _RecordingLogoutCoordinator(store, lifecycle);
      final runtime = ProductionWorkspaceRuntime(
        snapshot: _snapshot(accountId: 'account-a'),
        store: store,
        logoutCoordinator: logout,
        realtime: Object(),
        controllerFactory: _recordingControllerFactory(lifecycle),
        persistenceFactory: _recordingPersistenceFactory(lifecycle),
      );
      final controller = runtime.controller;
      final restore = runtime.restoreSettled;

      await storage.readStarted;
      runtime.dispose();
      runtime.dispose();
      storage.releaseRead();
      await restore;

      expect(controller.state.activeTab.currentRoute.link.entityId, 'home');
      expect(lifecycle, [
        'controller:account-a',
        'attach:account-a',
        'binding:account-a',
        'detach:account-a',
        'binding.dispose:account-a',
        'controller.dispose:account-a',
      ]);
      expect(logout.attachedControllers, isEmpty);
    },
  );

  test(
    'account and role resets clear before restore with exact lifecycle order',
    () async {
      final storage = _ControlledWorkspaceStorage();
      final store = AccountWorkspaceStore(storage);
      final lifecycle = <String>[];
      final logout = _RecordingLogoutCoordinator(store, lifecycle);
      final runtime = ProductionWorkspaceRuntime(
        snapshot: _snapshot(accountId: 'account-a', role: 'manager'),
        store: store,
        logoutCoordinator: logout,
        realtime: Object(),
        controllerFactory: _recordingControllerFactory(lifecycle),
        persistenceFactory: _recordingPersistenceFactory(lifecycle),
      );
      await runtime.restoreSettled;
      storage.operations.clear();

      runtime.update(
        snapshot: _snapshot(
          accountId: 'account-a',
          role: 'teacher',
          accessVersion: 2,
        ),
        initialLink: null,
      );
      await runtime.restoreSettled;
      _expectClearBeforeRestore(storage.operations, 'account-a');
      storage.operations.clear();

      runtime.update(
        snapshot: _snapshot(accountId: 'account-b', role: 'teacher'),
        initialLink: null,
      );
      await runtime.restoreSettled;
      _expectClearBeforeRestore(storage.operations, 'account-b');
      runtime.dispose();

      expect(lifecycle, [
        'controller:account-a',
        'attach:account-a',
        'binding:account-a',
        'logout:account-a',
        'detach:account-a',
        'binding.dispose:account-a',
        'controller.dispose:account-a',
        'controller:account-a',
        'attach:account-a',
        'binding:account-a',
        'logout:account-a',
        'detach:account-a',
        'binding.dispose:account-a',
        'controller.dispose:account-a',
        'controller:account-b',
        'attach:account-b',
        'binding:account-b',
        'detach:account-b',
        'binding.dispose:account-b',
        'controller.dispose:account-b',
      ]);
    },
  );

  test(
    'same account and role capability refresh filters cache without clearing it',
    () async {
      final storage = _ControlledWorkspaceStorage();
      final store = AccountWorkspaceStore(storage);
      await _seedPayment(store, accountId: 'account-a');
      storage.operations.clear();
      final runtime = ProductionWorkspaceRuntime(
        snapshot: _snapshot(
          accountId: 'account-a',
          capabilities: const {
            'crm.client.read.basic',
            'commerce.client_finance.read',
          },
        ),
        initialLink: EntityLink.typed(
          entityType: EntityLinkType.payment,
          entityId: 'forbidden-payment',
        ),
        store: store,
        logoutCoordinator: WorkspaceLogoutCoordinator(store),
        realtime: Object(),
      );

      await runtime.restoreSettled;
      storage.operations.clear();
      runtime.update(
        snapshot: _snapshot(accountId: 'account-a', accessVersion: 2),
        initialLink: EntityLink.typed(
          entityType: EntityLinkType.payment,
          entityId: 'forbidden-payment',
        ),
      );
      await runtime.restoreSettled;

      expect(
        storage.operations.where((entry) => entry.startsWith('delete:')),
        isEmpty,
      );
      expect(runtime.controller.state.tabs, hasLength(1));
      expect(
        runtime.controller.state.activeTab.currentRoute.link.rawEntityType,
        'chat',
      );
      expect(
        runtime.controller.state.activeTab.currentRoute.link.entityId,
        'home',
      );
      expect(runtime.controller.state.activeTab.titleHint, 'Главная');
      runtime.dispose();
    },
  );

  test(
    'latest allowed direct link wins after an older delayed restore',
    () async {
      final storage = _ControlledWorkspaceStorage()..blockNextRead();
      final store = AccountWorkspaceStore(storage);
      await _seedClient(
        store,
        accountId: 'account-a',
        clientId: 'cached-client',
      );
      storage.operations.clear();
      final runtime = ProductionWorkspaceRuntime(
        snapshot: _snapshot(accountId: 'account-a'),
        initialLink: _client('direct-a'),
        store: store,
        logoutCoordinator: WorkspaceLogoutCoordinator(store),
        realtime: Object(),
      );

      await storage.readStarted;
      runtime.update(
        snapshot: _snapshot(accountId: 'account-a'),
        initialLink: _client('direct-b'),
      );
      expect(
        runtime.controller.state.activeTab.currentRoute.link.entityId,
        'direct-b',
      );
      expect(
        storage.operations.where((operation) => operation.startsWith('write:')),
        isEmpty,
      );
      storage.releaseRead();
      await runtime.restoreSettled;

      final state = runtime.controller.state;
      expect(state.activeTab.currentRoute.link.entityId, 'direct-b');
      expect(
        state.tabs
            .expand((tab) => tab.routeStack)
            .map((route) => route.link.entityId),
        isNot(contains('direct-a')),
      );
      runtime.dispose();
    },
  );

  test(
    'persistence write failure does not fail a successful restored runtime',
    () async {
      final storage = _ControlledWorkspaceStorage();
      final store = AccountWorkspaceStore(storage);
      await _seedClient(
        store,
        accountId: 'account-a',
        clientId: 'cached-client',
      );
      storage.throwWrites = true;
      final runtime = ProductionWorkspaceRuntime(
        snapshot: _snapshot(accountId: 'account-a'),
        initialLink: _client('direct-client'),
        store: store,
        logoutCoordinator: WorkspaceLogoutCoordinator(store),
        realtime: Object(),
      );

      await expectLater(runtime.restoreSettled, completes);

      expect(
        runtime.controller.state.activeTab.currentRoute.link.entityId,
        'direct-client',
      );
      expect(runtime.controller.state.loggedOut, isFalse);
      runtime.dispose();
    },
  );

  test('direct-link dedupe uses raw type id and focus only', () async {
    final store = AccountWorkspaceStore(_ControlledWorkspaceStorage());
    final original = _client(
      'shared-id',
      variant: 'student',
      focus: 'profile',
      filter: const {'section': 'overview'},
      presentation: 'Первое имя',
    );
    final runtime = ProductionWorkspaceRuntime(
      snapshot: _snapshot(accountId: 'account-a'),
      initialLink: original,
      store: store,
      logoutCoordinator: WorkspaceLogoutCoordinator(store),
      realtime: Object(),
    );
    await runtime.restoreSettled;

    runtime.update(
      snapshot: _snapshot(accountId: 'account-a'),
      initialLink: _client(
        'shared-id',
        variant: 'student',
        focus: 'profile',
        filter: const {'section': 'history'},
        presentation: 'Новое имя',
      ),
    );
    expect(runtime.controller.state.activeTab.routeStack, hasLength(1));
    expect(
      runtime
          .controller
          .state
          .activeTab
          .currentRoute
          .link
          .presentation
          ?.primary,
      'Первое имя',
    );

    runtime.update(
      snapshot: _snapshot(accountId: 'account-a'),
      initialLink: _client('shared-id', variant: 'lead', focus: 'profile'),
    );
    runtime.update(
      snapshot: _snapshot(accountId: 'account-a'),
      initialLink: _client('shared-id', variant: 'lead', focus: 'history'),
    );
    expect(runtime.controller.state.activeTab.routeStack, hasLength(3));
    runtime.dispose();
  });
}

void _expectClearBeforeRestore(List<String> operations, String accountId) {
  final readIndex = operations.indexOf('read:$accountId');
  final clearIndex = operations.lastIndexWhere(
    (operation) => operation == 'delete:account-a',
  );
  expect(clearIndex, greaterThanOrEqualTo(0));
  expect(readIndex, greaterThan(clearIndex));
}

CapabilitySnapshot _snapshot({
  required String accountId,
  String role = 'manager',
  int accessVersion = 1,
  Set<String> capabilities = const {'crm.client.read.basic'},
}) => CapabilitySnapshot(
  accountId: accountId,
  role: role,
  accessVersion: accessVersion,
  capabilities: capabilities,
  scopes: const {},
);

EntityLink _client(
  String id, {
  String variant = 'student',
  String? focus,
  Map<String, dynamic> filter = const {},
  String? presentation,
}) => EntityLink.typed(
  entityType: EntityLinkType.client,
  entityId: id,
  variant: variant,
  optionalFocus: focus == null
      ? null
      : EntityLinkFocus(focus: focus, filter: filter),
  presentation: presentation == null
      ? null
      : EntityPresentationReference(primary: presentation),
);

Future<void> _seedClient(
  AccountWorkspaceStore store, {
  required String accountId,
  required String clientId,
}) async {
  final controller = _controller(
    accountId: accountId,
    initialLink: _client('home'),
    snapshot: _snapshot(accountId: accountId),
  )..open(_client(clientId), explicitNew: true);
  await store.save(controller.state);
  controller.dispose();
}

Future<void> _seedPayment(
  AccountWorkspaceStore store, {
  required String accountId,
}) async {
  final snapshot = _snapshot(
    accountId: accountId,
    capabilities: const {
      'crm.client.read.basic',
      'commerce.client_finance.read',
    },
  );
  final controller = _controller(
    accountId: accountId,
    initialLink: EntityLink.typed(
      entityType: EntityLinkType.payment,
      entityId: 'forbidden-payment',
    ),
    snapshot: snapshot,
  );
  await store.save(controller.state);
  controller.dispose();
}

WorkspaceController _controller({
  required String accountId,
  required EntityLink initialLink,
  required CapabilitySnapshot snapshot,
}) {
  final registry = EntityRouteRegistry();
  return WorkspaceController(
    accountId: accountId,
    initialLink: initialLink,
    initialTitle: 'Seed',
    sharedScope: WorkspaceSharedScope(
      session: snapshot,
      cache: Object(),
      realtime: Object(),
    ),
    titleResolver: (link) =>
        registry.resolve(link, snapshot).canonicalLocation?.title ?? 'Главная',
  );
}

ProductionWorkspaceControllerFactory _recordingControllerFactory(
  List<String> lifecycle,
) {
  return ({
    required accountId,
    required initialLink,
    required initialTitle,
    required sharedScope,
    required titleResolver,
  }) {
    lifecycle.add('controller:$accountId');
    return _RecordingWorkspaceController(
      lifecycle: lifecycle,
      accountId: accountId,
      initialLink: initialLink,
      initialTitle: initialTitle,
      sharedScope: sharedScope,
      titleResolver: titleResolver,
    );
  };
}

ProductionWorkspacePersistenceFactory _recordingPersistenceFactory(
  List<String> lifecycle,
) {
  return ({required controller, required store}) {
    lifecycle.add('binding:${controller.state.accountId}');
    return _RecordingPersistenceBinding(
      lifecycle: lifecycle,
      controller: controller,
      store: store,
    );
  };
}

class _RecordingWorkspaceController extends WorkspaceController {
  _RecordingWorkspaceController({
    required this.lifecycle,
    required super.accountId,
    required super.initialLink,
    required super.initialTitle,
    required super.sharedScope,
    required super.titleResolver,
  });

  final List<String> lifecycle;
  var _disposed = false;

  @override
  void dispose() {
    if (_disposed) throw StateError('controller disposed twice');
    _disposed = true;
    lifecycle.add('controller.dispose:${state.accountId}');
    super.dispose();
  }
}

class _RecordingPersistenceBinding extends WorkspacePersistenceBinding {
  _RecordingPersistenceBinding({
    required this.lifecycle,
    required super.controller,
    required super.store,
  }) : accountId = controller.state.accountId;

  final List<String> lifecycle;
  final String accountId;
  var _disposed = false;

  @override
  void dispose() {
    if (_disposed) throw StateError('binding disposed twice');
    _disposed = true;
    lifecycle.add('binding.dispose:$accountId');
    super.dispose();
  }
}

class _RecordingLogoutCoordinator extends WorkspaceLogoutCoordinator {
  _RecordingLogoutCoordinator(super.store, this.lifecycle);

  final List<String> lifecycle;
  final Set<WorkspaceController> attachedControllers = {};

  @override
  void attach(WorkspaceController controller) {
    lifecycle.add('attach:${controller.state.accountId}');
    attachedControllers.add(controller);
    super.attach(controller);
  }

  @override
  void detach(WorkspaceController controller) {
    lifecycle.add('detach:${controller.state.accountId}');
    attachedControllers.remove(controller);
    super.detach(controller);
  }

  @override
  Future<void> logout(String accountId) {
    lifecycle.add('logout:$accountId');
    return super.logout(accountId);
  }
}

class _ControlledWorkspaceStorage extends InMemoryWorkspaceKeyValueStore {
  final List<String> operations = [];
  Completer<void>? _readGate;
  Completer<void>? _readStarted;
  var throwWrites = false;

  Future<void> get readStarted => _readStarted?.future ?? Future.value();

  void blockNextRead() {
    _readGate = Completer<void>();
    _readStarted = Completer<void>();
  }

  void releaseRead() {
    if (_readGate?.isCompleted == false) _readGate!.complete();
  }

  @override
  Future<String?> read(String key) async {
    final accountId = _accountId(key);
    operations.add('read:$accountId');
    final gate = _readGate;
    if (gate != null) {
      _readStarted?.complete();
      await gate.future;
      _readGate = null;
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    operations.add('write:${_accountId(key)}');
    if (throwWrites) throw StateError('controlled write failure');
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    operations.add('delete:${_accountId(key)}');
    return super.delete(key);
  }

  static String _accountId(String key) =>
      Uri.decodeComponent(key.split(':').last);
}
