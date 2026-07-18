import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

/// A CRM realtime invalidation hint (carries no PII — listeners refetch via API).
class CrmChangedEvent {
  final String entity; // lesson | lead | student | payment | task | comment
  final String action; // created | updated | deleted
  final String? id;
  final String? branchId;
  /// Recipient-scoped user ids (e.g. a task's assignee) for targeted UI hints.
  final List<String> affectedUserIds;

  const CrmChangedEvent({
    required this.entity,
    required this.action,
    this.id,
    this.branchId,
    this.affectedUserIds = const [],
  });

  factory CrmChangedEvent.fromMap(Map<String, dynamic> map) => CrmChangedEvent(
    entity: map['entity']?.toString() ?? '',
    action: map['action']?.toString() ?? '',
    id: map['id']?.toString(),
    branchId: map['branchId']?.toString(),
    affectedUserIds: (map['affectedUserIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
  );

  bool get isFallbackPoll => action == 'poll';
}

/// App-level realtime stream of CRM changes. Kept alive (not autoDispose) so a
/// single staff/client socket serves every screen. It also emits low-frequency
/// fallback invalidation events so screens continue to refetch if Socket.IO is
/// unavailable, a tab wakes from sleep, or an event is missed.
final crmRealtimeProvider = StreamProvider<CrmChangedEvent>((ref) {
  final service = ref.watch(magicRealtimeServiceProvider);
  final controller = StreamController<CrmChangedEvent>.broadcast();
  MagicRealtimeConnection? connection;
  Timer? fallbackTimer;
  DateTime lastSocketEventAt = DateTime.fromMillisecondsSinceEpoch(0);

  void emit(CrmChangedEvent event) {
    if (!controller.isClosed) controller.add(event);
  }

  Future<void> start() async {
    try {
      final conn = await service.connect();
      connection = conn;
      conn.onCrmChanged((payload) {
        lastSocketEventAt = DateTime.now();
        emit(CrmChangedEvent.fromMap(payload));
      });
    } catch (_) {
      // Best-effort: fallback polling below keeps screens eventually fresh.
    }
  }

  var fallbackTick = 0;
  fallbackTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    fallbackTick++;
    // If realtime is active and has just delivered a CRM event, avoid a needless
    // duplicate refresh burst. Idle sockets still get a periodic API truth check.
    if (DateTime.now().difference(lastSocketEventAt) <
        const Duration(seconds: 25)) {
      return;
    }
    // Клиентов сервер НЕ подключает к broadcast-комнате crm.changed
    // (realtime.gateway.ts пускает туда только staff), поэтому для клиента окно
    // подавления не срабатывает никогда и 30-секундный опрос всех сущностей
    // превращался в постоянный самоDDoS (~1000 клиентов × 10 событий / 30 с).
    // Клиентам хватает редкой сверки: раз в 5 минут (каждый 10-й тик).
    // Роль читается лениво на каждом тике — без пересоздания сокета при её
    // загрузке; пока роль неизвестна, консервативно считаем клиентом.
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    final isStaff = role != null && role.isNotEmpty && role != 'client';
    if (!isStaff && fallbackTick % 10 != 0) return;
    for (final entity in _fallbackCrmEntities) {
      emit(CrmChangedEvent(entity: entity, action: 'poll'));
    }
  });

  start();

  ref.onDispose(() {
    fallbackTimer?.cancel();
    connection?.dispose();
    controller.close();
  });

  return controller.stream;
});

const _fallbackCrmEntities = <String>[
  'lesson',
  'lead',
  'student',
  'payment',
  'subscription',
  'task',
  'group',
  'comment',
  'chat_work',
  'notification',
];
