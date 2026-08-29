import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';

typedef WorkspaceRouteValidator = bool Function(EntityLink link);

abstract interface class WorkspaceKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureWorkspaceKeyValueStore implements WorkspaceKeyValueStore {
  const SecureWorkspaceKeyValueStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InMemoryWorkspaceKeyValueStore implements WorkspaceKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class AccountWorkspaceStore {
  const AccountWorkspaceStore(this._storage);

  final WorkspaceKeyValueStore _storage;

  Future<void> save(WorkspaceState state) {
    // Session teardown is not itself a consent to delete recovery data.
    // Explicit logout owns deletion; forced revocation keeps the encrypted
    // client-card draft so the same account can restore it after signing in.
    if (state.loggedOut) return Future<void>.value();
    return _storage.write(_key(state.accountId), jsonEncode(_serialize(state)));
  }

  Future<WorkspaceState> restore({
    required String accountId,
    required WorkspaceState fallback,
    required WorkspaceRouteValidator routeAllowed,
  }) async {
    if (fallback.accountId != accountId) {
      throw ArgumentError('Fallback belongs to another account.');
    }
    final encoded = await _storage.read(_key(accountId));
    if (encoded == null) return fallback;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != WorkspaceState.currentSchemaVersion ||
          decoded['accountId'] != accountId) {
        return fallback;
      }
      final rawTabs = decoded['tabs'];
      if (rawTabs is! List ||
          rawTabs.isEmpty ||
          rawTabs.length > WorkspaceController.maxTabs) {
        return fallback;
      }

      final tabs = <WorkspaceTabState>[];
      final tabIds = <String>{};
      for (final rawTab in rawTabs) {
        if (rawTab is! Map) return fallback;
        final tab = rawTab.map((key, value) => MapEntry(key.toString(), value));
        final rawRoutes = tab['routeStack'];
        if (rawRoutes is! List || rawRoutes.isEmpty) return fallback;
        final routes = _restoreRoutes(rawRoutes, routeAllowed);
        if (routes == null || routes.isEmpty) return fallback;
        final rawForward = tab['forwardStack'];
        final forward = rawForward == null
            ? const <ContextRouteState>[]
            : rawForward is List
            ? _restoreRoutes(rawForward, routeAllowed)
            : null;
        if (forward == null) return fallback;
        final tabId = tab['tabId']?.toString() ?? '';
        if (tabId.isEmpty || !tabIds.add(tabId)) return fallback;
        final forms = _restoreForms(tab['forms']);
        tabs.add(
          WorkspaceTabState(
            tabId: tabId,
            titleHint: tab['titleHint']?.toString() ?? '',
            routeStack: routes,
            forwardStack: forward,
            forms: forms,
          ),
        );
      }

      final activeTabId = decoded['activeTabId']?.toString() ?? '';
      if (!tabs.any((tab) => tab.tabId == activeTabId)) return fallback;
      return WorkspaceState(
        accountId: accountId,
        activeTabId: activeTabId,
        tabs: tabs,
      );
    } on FormatException {
      return fallback;
    } on TypeError {
      return fallback;
    } on ArgumentError {
      return fallback;
    }
  }

  Future<void> clear(String accountId) => _storage.delete(_key(accountId));

  static String _key(String accountId) {
    return 'magic_workspace:v${WorkspaceState.currentSchemaVersion}:'
        '${Uri.encodeComponent(accountId)}';
  }

  static Map<String, Object?> _serialize(WorkspaceState state) {
    return {
      'schemaVersion': state.schemaVersion,
      'accountId': state.accountId,
      'activeTabId': state.activeTabId,
      'tabs': [
        for (final tab in state.tabs)
          {
            'tabId': tab.tabId,
            'titleHint': tab.titleHint,
            'routeStack': [for (final route in tab.routeStack) route.toJson()],
            'forwardStack': [
              for (final route in tab.forwardStack) route.toJson(),
            ],
            'forms': [
              for (final form in tab.forms.values)
                if (_shouldPersistForm(form))
                  {
                    'formKey': form.formKey,
                    'dirty': true,
                    if (form.expectedVersion != null)
                      'expectedVersion': form.expectedVersion,
                    'draft': _jsonSafeMap(form.draft),
                  },
            ],
          },
      ],
    };
  }

  /// Only the client-card recovery draft is durable. Other workspace forms may
  /// contain short-lived credentials or secrets and remain memory-only.
  static bool _shouldPersistForm(WorkspaceFormState form) {
    return form.dirty &&
        form.formKey.startsWith('client-card:') &&
        form.draft.isNotEmpty;
  }

  static Map<String, WorkspaceFormState> _restoreForms(Object? rawForms) {
    if (rawForms == null) return const {};
    if (rawForms is! List || rawForms.length > 10) return const {};
    final forms = <String, WorkspaceFormState>{};
    for (final rawForm in rawForms) {
      if (rawForm is! Map) continue;
      final form = rawForm.map((key, value) => MapEntry(key.toString(), value));
      final formKey = form['formKey']?.toString() ?? '';
      final rawDraft = form['draft'];
      if (!formKey.startsWith('client-card:') ||
          form['dirty'] != true ||
          rawDraft is! Map) {
        continue;
      }
      final draft = _jsonSafeMap(
        rawDraft.map((key, value) => MapEntry(key.toString(), value)),
      );
      // Bound secure-storage snapshots. A normal client card, including its
      // 20k internal note, stays far below this limit.
      if (draft.isEmpty || jsonEncode(draft).length > 256 * 1024) continue;
      final rawExpectedVersion = form['expectedVersion'];
      final expectedVersion = rawExpectedVersion is num
          ? rawExpectedVersion.toInt()
          : int.tryParse(rawExpectedVersion?.toString() ?? '');
      forms[formKey] = WorkspaceFormState(
        formKey: formKey,
        dirty: true,
        expectedVersion: expectedVersion,
        draft: draft,
      );
    }
    return forms;
  }

  static Map<String, Object?> _jsonSafeMap(Map<String, Object?> source) {
    return {
      for (final entry in source.entries)
        entry.key: _jsonSafeValue(entry.value),
    };
  }

  static Object? _jsonSafeValue(Object? value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is Iterable) {
      return [for (final item in value) _jsonSafeValue(item)];
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafeValue(entry.value),
      };
    }
    return value.toString();
  }

  static List<ContextRouteState>? _restoreRoutes(
    List<Object?> rawRoutes,
    WorkspaceRouteValidator routeAllowed,
  ) {
    final routes = <ContextRouteState>[];
    for (final rawRoute in rawRoutes) {
      if (rawRoute is! Map) return null;
      final route = ContextRouteState.fromJson(
        rawRoute.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (!route.link.isSupported || !routeAllowed(route.link)) return null;
      routes.add(route);
    }
    return routes;
  }
}

class WorkspacePersistenceBinding {
  WorkspacePersistenceBinding({
    required WorkspaceController controller,
    required AccountWorkspaceStore store,
  }) : _controller = controller,
       _store = store {
    controller.addListener(_scheduleSave);
  }

  final WorkspaceController _controller;
  final AccountWorkspaceStore _store;
  Future<void> _pending = Future.value();
  WorkspaceState? _bufferedState;
  bool _suspended = false;
  bool _disposed = false;

  void _scheduleSave() {
    if (_disposed) return;
    final snapshot = _controller.state;
    if (_suspended) {
      _bufferedState = snapshot;
      return;
    }
    _enqueue(snapshot);
  }

  void _enqueue(WorkspaceState snapshot) {
    _pending = _pending
        .catchError((Object _) {})
        .then((_) => _store.save(snapshot));
  }

  void suspend() {
    if (_disposed) return;
    _suspended = true;
  }

  void resume() {
    if (_disposed || !_suspended) return;
    _suspended = false;
    final buffered = _bufferedState;
    _bufferedState = null;
    if (buffered != null) _enqueue(buffered);
  }

  Future<void> flush() => _pending;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bufferedState = null;
    _controller.removeListener(_scheduleSave);
  }
}

class WorkspaceLogoutCoordinator {
  WorkspaceLogoutCoordinator(this._store);

  final AccountWorkspaceStore _store;
  final Map<String, Set<WorkspaceController>> _controllers = {};

  void attach(WorkspaceController controller) {
    (_controllers[controller.state.accountId] ??= {}).add(controller);
  }

  void detach(WorkspaceController controller) {
    _controllers[controller.state.accountId]?.remove(controller);
  }

  Future<void> logout(String accountId) async {
    final controllers = List<WorkspaceController>.of(
      _controllers[accountId] ?? const {},
    );
    await _saveDirtyControllers(controllers);
    for (final controller in controllers) {
      if (_isAttached(controller)) controller.handleGlobalLogout();
    }
    await _store.clear(accountId);
  }

  Future<void> logoutAll() async {
    final controllers = [
      for (final accountControllers in _controllers.values)
        ...accountControllers,
    ];
    await _saveDirtyControllers(controllers);
    for (final controller in controllers) {
      if (_isAttached(controller)) controller.handleGlobalLogout();
    }
    for (final accountId in _controllers.keys.toList(growable: false)) {
      await _store.clear(accountId);
    }
  }

  /// A revoked session cannot save through the API. Preserve encrypted local
  /// recovery drafts best-effort, then always tear down every live workspace.
  /// Unlike an explicit logout this intentionally does not clear the snapshot:
  /// the same account can recover it after signing in again.
  Future<void> forceLogoutAllPreservingDrafts() async {
    final controllers = [
      for (final accountControllers in _controllers.values)
        ...accountControllers,
    ];
    for (final controller in controllers) {
      if (controller.state.loggedOut) continue;
      try {
        await _store.save(controller.state);
      } on Object {
        // Credential/session removal must not be blocked by local I/O.
      }
    }
    for (final controller in controllers) {
      if (_isAttached(controller)) controller.handleGlobalLogout();
    }
  }

  bool _isAttached(WorkspaceController controller) {
    return _controllers[controller.state.accountId]?.contains(controller) ==
        true;
  }

  Future<void> _saveDirtyControllers(
    Iterable<WorkspaceController> controllers,
  ) async {
    for (final controller in controllers) {
      final saved = await controller.resolveAllDirtyTabs(
        decision: DirtyCloseDecision.save,
        saveDirty: controller.saveDirtyForms,
      );
      if (!saved) {
        throw StateError(
          'Workspace forms for "${controller.state.accountId}" were not saved.',
        );
      }
    }
  }
}

final accountWorkspaceStoreProvider = Provider<AccountWorkspaceStore>((ref) {
  return const AccountWorkspaceStore(SecureWorkspaceKeyValueStore());
});

final workspaceLogoutCoordinatorProvider = Provider<WorkspaceLogoutCoordinator>(
  (ref) => WorkspaceLogoutCoordinator(ref.watch(accountWorkspaceStoreProvider)),
);
