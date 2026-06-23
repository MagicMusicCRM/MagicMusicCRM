import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';

/// A CRM realtime invalidation hint (carries no PII — listeners refetch via API).
class CrmChangedEvent {
  final String entity; // lesson | lead | student | payment | task | comment
  final String action; // created | updated | deleted
  final String? id;
  final String? branchId;

  const CrmChangedEvent({
    required this.entity,
    required this.action,
    this.id,
    this.branchId,
  });

  factory CrmChangedEvent.fromMap(Map<String, dynamic> map) => CrmChangedEvent(
        entity: map['entity']?.toString() ?? '',
        action: map['action']?.toString() ?? '',
        id: map['id']?.toString(),
        branchId: map['branchId']?.toString(),
      );
}

/// App-level realtime stream of CRM changes. Kept alive (not autoDispose) so a
/// single staff socket serves every screen; connection failures are swallowed
/// (realtime is best-effort — screens still work via manual refresh / re-entry).
final crmRealtimeProvider = StreamProvider<CrmChangedEvent>((ref) {
  final service = ref.watch(magicRealtimeServiceProvider);
  final controller = StreamController<CrmChangedEvent>.broadcast();
  MagicRealtimeConnection? connection;

  Future<void> start() async {
    try {
      final conn = await service.connect();
      connection = conn;
      conn.onCrmChanged((payload) {
        if (!controller.isClosed) {
          controller.add(CrmChangedEvent.fromMap(payload));
        }
      });
    } catch (_) {
      // Best-effort: leave the stream open but empty.
    }
  }

  start();

  ref.onDispose(() {
    connection?.dispose();
    controller.close();
  });

  return controller.stream;
});
