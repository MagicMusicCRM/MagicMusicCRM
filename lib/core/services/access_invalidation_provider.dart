import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

class AccessInvalidatedEvent {
  final int accessVersion;
  final String scope;

  const AccessInvalidatedEvent({
    required this.accessVersion,
    required this.scope,
  });

  factory AccessInvalidatedEvent.fromMap(Map<String, dynamic> map) {
    final rawVersion = map['accessVersion'];
    return AccessInvalidatedEvent(
      accessVersion: rawVersion is num
          ? rawVersion.toInt()
          : int.tryParse(rawVersion?.toString() ?? '') ?? 0,
      scope: map['scope']?.toString() ?? 'user',
    );
  }
}

/// Keeps one account-scoped listener alive at router level. An invalidation
/// clears the current access/session projection immediately; the router then
/// refetches server truth and redirects if the actor's role route changed.
///
/// Capability-aware navigation consumes the same event stream, so it never
/// needs a second Socket.IO connection.
final accessInvalidationProvider = StreamProvider<AccessInvalidatedEvent>((
  ref,
) {
  final service = ref.watch(magicRealtimeServiceProvider);
  final controller = StreamController<AccessInvalidatedEvent>.broadcast();
  MagicRealtimeConnection? connection;

  Future<void> start() async {
    try {
      final conn = await service.connect();
      connection = conn;
      conn.onAccessInvalidated((payload) {
        final event = AccessInvalidatedEvent.fromMap(payload);
        if (event.accessVersion < 1 || controller.isClosed) return;
        ref.invalidate(capabilitySnapshotProvider);
        ref.invalidate(releaseGateStatusProvider);
        controller.add(event);
      });
    } catch (_) {
      // REST guards remain authoritative when realtime is unavailable.
    }
  }

  start();
  ref.onDispose(() {
    connection?.dispose();
    controller.close();
  });
  return controller.stream;
});
