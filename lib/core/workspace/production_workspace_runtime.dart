import 'dart:async';

import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

typedef ProductionWorkspaceControllerFactory =
    WorkspaceController Function({
      required String accountId,
      required EntityLink initialLink,
      required String initialTitle,
      required WorkspaceSharedScope sharedScope,
      required WorkspaceTitleResolver titleResolver,
    });

typedef ProductionWorkspacePersistenceFactory =
    WorkspacePersistenceBinding Function({
      required WorkspaceController controller,
      required AccountWorkspaceStore store,
    });

/// Owns the mutable production workspace lifecycle outside the widget tree.
class ProductionWorkspaceRuntime {
  ProductionWorkspaceRuntime({
    required CapabilitySnapshot snapshot,
    required AccountWorkspaceStore store,
    required WorkspaceLogoutCoordinator logoutCoordinator,
    required Object realtime,
    EntityLink? initialLink,
    EntityRouteRegistry? registry,
    ProductionWorkspaceControllerFactory controllerFactory = _createController,
    ProductionWorkspacePersistenceFactory persistenceFactory =
        _createPersistence,
  }) : _snapshot = snapshot,
       _requestedDirectLink = initialLink,
       _store = store,
       _logoutCoordinator = logoutCoordinator,
       _realtime = realtime,
       _registry = registry ?? EntityRouteRegistry(),
       _controllerFactory = controllerFactory,
       _persistenceFactory = persistenceFactory {
    _start();
  }

  static final EntityLink _fallbackLink = EntityLink.typed(
    entityType: EntityLinkType.chat,
    entityId: 'home',
  );

  CapabilitySnapshot _snapshot;
  EntityLink? _requestedDirectLink;
  final AccountWorkspaceStore _store;
  final WorkspaceLogoutCoordinator _logoutCoordinator;
  final Object _realtime;
  final EntityRouteRegistry _registry;
  final ProductionWorkspaceControllerFactory _controllerFactory;
  final ProductionWorkspacePersistenceFactory _persistenceFactory;

  late WorkspaceController _controller;
  late WorkspacePersistenceBinding _persistence;
  Future<void> _restoreSettled = Future<void>.value();
  var _generation = 0;
  var _directLinkGeneration = 0;
  var _hasLiveController = false;
  var _disposed = false;

  WorkspaceController get controller => _controller;
  int get generation => _generation;
  Future<void> get restoreSettled => _restoreSettled;

  bool owns(WorkspaceController controller, int generation) {
    return _isCurrent(controller, generation);
  }

  void update({
    required CapabilitySnapshot snapshot,
    required EntityLink? initialLink,
  }) {
    if (_disposed) return;
    final previous = _snapshot;
    final identityChanged =
        previous.accountId != snapshot.accountId ||
        previous.role != snapshot.role;
    final capabilitiesChanged =
        previous.accessVersion != snapshot.accessVersion;
    _snapshot = snapshot;
    _requestedDirectLink = initialLink;
    _directLinkGeneration++;

    if (identityChanged || capabilitiesChanged) {
      final oldAccountId = previous.accountId;
      _invalidate();
      final reset = identityChanged
          ? _logoutCoordinator.logout(oldAccountId)
          : Future<void>.value();
      _teardown(alreadyInvalidated: true);
      _start(beforeRestore: reset);
      return;
    }
    _applyLatestDirectLink(_controller, _generation);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _teardown();
  }

  void _start({Future<void>? beforeRestore}) {
    final snapshot = _snapshot;
    final generation = ++_generation;
    final requested = _requestedDirectLink;
    final initialLink = _isAllowed(requested, snapshot)
        ? requested!
        : _fallbackLink;
    final controller = _controllerFactory(
      accountId: snapshot.accountId,
      initialLink: initialLink,
      initialTitle: _titleFor(initialLink, snapshot),
      sharedScope: WorkspaceSharedScope(
        session: snapshot,
        cache: _store,
        realtime: _realtime,
      ),
      titleResolver: (link) => _titleFor(link, snapshot),
    );
    _controller = controller;
    _hasLiveController = true;
    _logoutCoordinator.attach(controller);
    final persistence = _persistenceFactory(
      controller: controller,
      store: _store,
    )..suspend();
    _persistence = persistence;
    _restoreSettled = _restore(
      controller: controller,
      persistence: persistence,
      snapshot: snapshot,
      generation: generation,
      beforeRestore: beforeRestore,
    );
  }

  Future<void> _restore({
    required WorkspaceController controller,
    required WorkspacePersistenceBinding persistence,
    required CapabilitySnapshot snapshot,
    required int generation,
    Future<void>? beforeRestore,
  }) async {
    late final WorkspaceState restored;
    try {
      await beforeRestore;
      if (!_isCurrent(controller, generation)) return;
      restored = await _store.restore(
        accountId: snapshot.accountId,
        fallback: controller.state,
        routeAllowed: (link) => _isAllowed(link, snapshot),
      );
    } on Object {
      // The safe fallback remains live when local cache I/O is unavailable.
      if (_isCurrent(controller, generation)) {
        _applyLatestDirectLink(controller, generation);
        persistence.resume();
        await _flushPersistence(persistence);
      }
      return;
    }
    if (!_isCurrent(controller, generation)) return;
    controller.restore(restored);
    _applyLatestDirectLink(controller, generation);
    if (_isCurrent(controller, generation)) {
      persistence.resume();
      await _flushPersistence(persistence);
    }
  }

  Future<void> _flushPersistence(
    WorkspacePersistenceBinding persistence,
  ) async {
    try {
      await persistence.flush();
    } on Object {
      // Restored state remains usable when best-effort local persistence fails.
    }
  }

  void _applyLatestDirectLink(WorkspaceController controller, int generation) {
    final directGeneration = _directLinkGeneration;
    final directLink = _requestedDirectLink;
    final snapshot = _snapshot;
    if (!_isCurrent(controller, generation) ||
        directLink == null ||
        !_isAllowed(directLink, snapshot) ||
        _sameLink(controller.state.activeTab.currentRoute.link, directLink)) {
      return;
    }
    if (directGeneration != _directLinkGeneration) return;
    controller.push(controller.state.activeTabId, directLink);
  }

  void _invalidate() {
    _generation++;
    _directLinkGeneration++;
  }

  void _teardown({bool alreadyInvalidated = false}) {
    if (!alreadyInvalidated) _invalidate();
    if (!_hasLiveController) return;
    _hasLiveController = false;
    final controller = _controller;
    _logoutCoordinator.detach(controller);
    _persistence.dispose();
    controller.dispose();
  }

  bool _isCurrent(WorkspaceController controller, int generation) {
    return !_disposed &&
        _hasLiveController &&
        generation == _generation &&
        identical(controller, _controller);
  }

  bool _isAllowed(EntityLink? link, CapabilitySnapshot snapshot) {
    return link != null && _registry.resolve(link, snapshot).canOpen;
  }

  String _titleFor(EntityLink link, CapabilitySnapshot snapshot) {
    if (_sameLink(link, _fallbackLink)) return 'Главная';
    return _registry.resolve(link, snapshot).canonicalLocation?.title ??
        'Главная';
  }

  static bool _sameLink(EntityLink? left, EntityLink? right) {
    return left?.rawEntityType == right?.rawEntityType &&
        left?.entityId == right?.entityId &&
        left?.optionalFocus?.focus == right?.optionalFocus?.focus;
  }
}

WorkspaceController _createController({
  required String accountId,
  required EntityLink initialLink,
  required String initialTitle,
  required WorkspaceSharedScope sharedScope,
  required WorkspaceTitleResolver titleResolver,
}) => WorkspaceController(
  accountId: accountId,
  initialLink: initialLink,
  initialTitle: initialTitle,
  sharedScope: sharedScope,
  titleResolver: titleResolver,
);

WorkspacePersistenceBinding _createPersistence({
  required WorkspaceController controller,
  required AccountWorkspaceStore store,
}) => WorkspacePersistenceBinding(controller: controller, store: store);
