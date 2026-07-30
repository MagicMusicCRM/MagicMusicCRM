import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    if (state.loggedOut) return clear(state.accountId);
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
        final routes = <ContextRouteState>[];
        for (final rawRoute in rawRoutes) {
          if (rawRoute is! Map) return fallback;
          final route = ContextRouteState.fromJson(
            rawRoute.map((key, value) => MapEntry(key.toString(), value)),
          );
          if (!route.link.isSupported || !routeAllowed(route.link)) {
            return fallback;
          }
          routes.add(route);
        }
        final tabId = tab['tabId']?.toString() ?? '';
        if (tabId.isEmpty || !tabIds.add(tabId)) return fallback;
        tabs.add(
          WorkspaceTabState(
            tabId: tabId,
            titleHint: tab['titleHint']?.toString() ?? '',
            routeStack: routes,
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
          },
      ],
    };
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
  bool _disposed = false;

  void _scheduleSave() {
    if (_disposed) return;
    final snapshot = _controller.state;
    _pending = _pending
        .catchError((Object _) {})
        .then((_) => _store.save(snapshot));
  }

  Future<void> flush() => _pending;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
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
    for (final controller in controllers) {
      controller.handleGlobalLogout();
    }
    await _store.clear(accountId);
  }
}
