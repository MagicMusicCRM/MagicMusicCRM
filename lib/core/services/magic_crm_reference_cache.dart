import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/hollihop_service.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

final magicCrmReferenceCacheProvider = Provider<MagicCrmReferenceCache>((ref) {
  return MagicCrmReferenceCache(
    crm: ref.watch(magicCrmServiceProvider),
    hollihop: ref.watch(hollihopServiceProvider),
  );
});

class MagicCrmReferenceCache {
  final MagicCrmService _crm;
  final HolliHopService _hollihop;
  final Duration ttl;
  final Map<String, _ReferenceEntry<Object>> _entries = {};

  MagicCrmReferenceCache({
    required MagicCrmService crm,
    required HolliHopService hollihop,
    this.ttl = const Duration(minutes: 10),
  }) : _crm = crm,
       _hollihop = hollihop;

  Future<List<Map<String, dynamic>>> branches({bool forceRefresh = false}) {
    return _get(
      'branches',
      () => _crm.listBranches(limit: 100),
      forceRefresh: forceRefresh,
    );
  }

  Future<List<Map<String, dynamic>>> rooms({
    String? branchId,
    bool forceRefresh = false,
  }) {
    return _get(
      'rooms:${branchId ?? 'all'}',
      () => _crm.listRooms(branchId: branchId, limit: 100),
      forceRefresh: forceRefresh,
    );
  }

  Future<List<Map<String, dynamic>>> leadStatuses({bool forceRefresh = false}) {
    return _get(
      'lead_statuses',
      () => _crm.listLeadStatuses(limit: 100),
      forceRefresh: forceRefresh,
    );
  }

  Future<List<String>> disciplines({bool forceRefresh = false}) {
    return _get(
      'disciplines',
      _hollihop.getDisciplines,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<String>> levels({bool forceRefresh = false}) {
    return _get('levels', _hollihop.getLevels, forceRefresh: forceRefresh);
  }

  Future<List<String>> categories({bool forceRefresh = false}) {
    return _get(
      'categories',
      _hollihop.getCategories,
      forceRefresh: forceRefresh,
    );
  }

  void invalidate({
    bool branches = false,
    bool rooms = false,
    bool leadStatuses = false,
    bool disciplines = false,
    bool levels = false,
    bool categories = false,
  }) {
    final prefixes = <String>[
      if (branches) 'branches',
      if (rooms) 'rooms:',
      if (leadStatuses) 'lead_statuses',
      if (disciplines) 'disciplines',
      if (levels) 'levels',
      if (categories) 'categories',
    ];
    if (prefixes.isEmpty) {
      _entries.clear();
      return;
    }
    _entries.removeWhere(
      (key, _) =>
          prefixes.any((prefix) => key == prefix || key.startsWith(prefix)),
    );
  }

  Future<void> warm() async {
    await Future.wait([
      branches(),
      rooms(),
      leadStatuses(),
      disciplines(),
      levels(),
      categories(),
    ]);
  }

  Future<T> _get<T>(
    String key,
    Future<T> Function() loader, {
    required bool forceRefresh,
  }) async {
    final entry = _entries[key];
    final now = DateTime.now();
    if (!forceRefresh && entry != null) {
      try {
        final typedValue = entry.value as T;
        if (!entry.isExpired(now, ttl)) return typedValue;
        entry.refreshing ??= _refresh(
          key,
          loader,
        ).then<void>((_) {}, onError: (_) {});
        return typedValue;
      } on TypeError {
        _entries.remove(key);
      }
    }

    return _refresh(key, loader);
  }

  Future<T> _refresh<T>(String key, Future<T> Function() loader) async {
    try {
      final value = await loader();
      _entries[key] = _ReferenceEntry<Object>(
        value: value as Object,
        fetchedAt: DateTime.now(),
      );
      return value;
    } finally {
      final entry = _entries[key];
      if (entry != null) entry.refreshing = null;
    }
  }
}

class _ReferenceEntry<T extends Object> {
  final T value;
  final DateTime fetchedAt;
  Future<void>? refreshing;

  _ReferenceEntry({required this.value, required this.fetchedAt});

  bool isExpired(DateTime now, Duration ttl) => now.difference(fetchedAt) > ttl;
}
