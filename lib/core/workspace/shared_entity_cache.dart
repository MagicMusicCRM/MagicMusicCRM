import 'dart:collection';

import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';

class EntityCacheVersionKey {
  const EntityCacheVersionKey({
    required this.entityType,
    required this.entityId,
    required this.projectionScope,
    required this.version,
  });

  final String entityType;
  final String entityId;
  final String projectionScope;
  final int version;

  @override
  bool operator ==(Object other) {
    return other is EntityCacheVersionKey &&
        other.entityType == entityType &&
        other.entityId == entityId &&
        other.projectionScope == projectionScope &&
        other.version == version;
  }

  @override
  int get hashCode =>
      Object.hash(entityType, entityId, projectionScope, version);
}

class EntityCacheEntry<T> {
  const EntityCacheEntry({
    required this.key,
    required this.value,
    required this.fetchedAt,
  });

  final EntityCacheVersionKey key;
  final T value;
  final DateTime fetchedAt;
}

class SharedEntityCache {
  final Map<EntityCacheVersionKey, EntityCacheEntry<Object?>> _entries = {};
  final Map<String, EntityCacheVersionKey> _latest = {};

  EntityCacheEntry<T> put<T>({
    required EntityLink link,
    required String projectionScope,
    required int version,
    required T value,
  }) {
    final key = EntityCacheVersionKey(
      entityType: link.rawEntityType,
      entityId: link.entityId,
      projectionScope: projectionScope,
      version: version,
    );
    final entry = EntityCacheEntry<T>(
      key: key,
      value: value,
      fetchedAt: DateTime.now().toUtc(),
    );
    _entries[key] = entry;
    final latestKey = _latestIdentity(link, projectionScope);
    final current = _latest[latestKey];
    if (current == null || version >= current.version) {
      _latest[latestKey] = key;
    }
    return entry;
  }

  EntityCacheEntry<T>? latest<T>(
    EntityLink link, {
    required String projectionScope,
  }) {
    final key = _latest[_latestIdentity(link, projectionScope)];
    if (key == null) return null;
    final entry = _entries[key];
    return entry is EntityCacheEntry<T> ? entry : null;
  }

  void invalidate(EntityLink link, {required int serverVersion}) {
    final staleKeys = _entries.keys
        .where(
          (key) =>
              key.entityType == link.rawEntityType &&
              key.entityId == link.entityId &&
              key.version < serverVersion,
        )
        .toList(growable: false);
    for (final key in staleKeys) {
      _entries.remove(key);
    }
    final identities = _latest.keys
        .where((identity) => identity.startsWith(_entityPrefix(link)))
        .toList(growable: false);
    for (final identity in identities) {
      final current = _latest[identity];
      if (current != null && current.version < serverVersion) {
        _latest.remove(identity);
      }
    }
  }

  void clear() {
    _entries.clear();
    _latest.clear();
  }

  static String _latestIdentity(EntityLink link, String projectionScope) =>
      '${_entityPrefix(link)}$projectionScope';

  static String _entityPrefix(EntityLink link) =>
      '${link.rawEntityType}:${link.entityId}:';
}

class EntityInvalidationEvent {
  const EntityInvalidationEvent({
    required this.eventId,
    required this.link,
    required this.version,
  });

  final String eventId;
  final EntityLink link;
  final int version;
}

typedef WorkspaceTabRefetch =
    Future<void> Function(String tabId, EntityLink link, int version);

class WorkspaceInvalidationCoordinator {
  WorkspaceInvalidationCoordinator({
    required this.workspace,
    required this.cache,
    required this.refetch,
  });

  final WorkspaceController workspace;
  final SharedEntityCache cache;
  final WorkspaceTabRefetch refetch;
  final LinkedHashSet<String> _seenEventIds = LinkedHashSet();

  Future<bool> handle(EntityInvalidationEvent event) async {
    if (event.eventId.isEmpty || !_seenEventIds.add(event.eventId)) {
      return false;
    }
    if (_seenEventIds.length > 512) {
      _seenEventIds.remove(_seenEventIds.first);
    }

    try {
      cache.invalidate(event.link, serverVersion: event.version);
      final matchingTabs = workspace.state.tabs
          .where(
            (tab) =>
                tab.currentRoute.link.rawEntityType ==
                    event.link.rawEntityType &&
                tab.currentRoute.link.entityId == event.link.entityId,
          )
          .toList(growable: false);
      final refetches = <Future<void>>[];
      for (final tab in matchingTabs) {
        final dirtyForms = tab.forms.values
            .where((form) => form.dirty)
            .toList(growable: false);
        if (dirtyForms.isNotEmpty) {
          for (final form in dirtyForms) {
            workspace.markFormConflict(
              tab.tabId,
              form.formKey,
              serverVersion: event.version,
              source: 'realtime',
            );
          }
        } else {
          refetches.add(refetch(tab.tabId, event.link, event.version));
        }
      }
      await Future.wait(refetches);
      return true;
    } catch (_) {
      _seenEventIds.remove(event.eventId);
      rethrow;
    }
  }

  bool handleWriteError({
    required String tabId,
    required String formKey,
    required Object error,
  }) {
    if (error is! MagicApiException || error.statusCode != 409) return false;
    final version = _serverVersion(error.details);
    if (version == null) return false;
    workspace.markFormConflict(
      tabId,
      formKey,
      serverVersion: version,
      source: 'write-409',
    );
    return true;
  }

  static int? _serverVersion(Object? details) {
    if (details is! Map) return null;
    for (final key in const ['currentVersion', 'serverVersion', 'version']) {
      final value = details[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }
}
