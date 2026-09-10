import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_data_controller.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_draft_controller.dart';

class _Api extends MagicApiClient {
  _Api()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());
  final pending = <Completer<Map<String, dynamic>>>[];
  final paths = <String>[];
  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    paths.add(path);
    if (path.endsWith('/card')) return await pending.removeAt(0).future as T;
    return <String, dynamic>{} as T;
  }
}

void main() {
  test(
    'read owner rejects late student snapshots and never requests teacher finance',
    () async {
      final api = _Api();
      final data = ClientCardDataController(
        crm: MagicCrmService(api),
        resolveRole: () async => 'teacher',
      );
      addTearDown(data.dispose);
      final old = Completer<Map<String, dynamic>>(),
          fresh = Completer<Map<String, dynamic>>();
      api.pending.addAll([old, fresh]);
      final first = data.loadStudent('student-a'),
          second = data.loadStudent('student-a');
      fresh.complete({
        'student': {'id': 'student-a', 'firstName': 'Новый'},
      });
      await second;
      final snapshot = data.student;
      old.complete({
        'student': {'id': 'student-a', 'firstName': 'Старый'},
      });
      expect(await first, isNull);
      expect(identical(data.student, snapshot), isTrue);
      expect(api.paths.where((p) => p.endsWith('/commerce')), isEmpty);
      expect(data.student!.commerce, isNull);
    },
  );
  test('disposed read owner rejects a late result', () async {
    final api = _Api();
    final data = ClientCardDataController(
      crm: MagicCrmService(api),
      resolveRole: () async => 'teacher',
    );
    final result = Completer<Map<String, dynamic>>();
    api.pending.add(result);
    final load = data.loadStudent('student-a');
    data.dispose();
    result.complete({
      'student': {'id': 'student-a'},
    });
    expect(await load, isNull);
    expect(data.student, isNull);
  });
  test('draft owner coalesces edits and serializes writes', () async {
    bool dirty = true;
    final requests = <int>[];
    final gates = <Completer<bool>>[];
    late ClientCardDraftController draft;
    draft = ClientCardDraftController(
      isDirty: () => dirty,
      isValid: () => true,
      onChanged: () {},
      persist: (revision) async {
        requests.add(revision);
        final gate = Completer<bool>();
        gates.add(gate);
        final result = await gate.future;
        if (revision == draft.revision) dirty = false;
        return result;
      },
    );
    addTearDown(draft.dispose);
    draft.revision = 1;
    final first = draft.run();
    draft.revision = 2;
    final queued = draft.run();
    expect(requests, [1]);
    gates[0].complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, [1, 2]);
    gates[1].complete(true);
    expect(await first, isTrue);
    await queued;
    expect(await draft.flush(), isTrue);
  });
  test('conflict blocks scheduled writes until explicit retry', () async {
    int writes = 0;
    final draft = ClientCardDraftController(
      isDirty: () => true,
      isValid: () => true,
      onChanged: () {},
      persist: (_) async {
        writes++;
        return true;
      },
      delay: Duration.zero,
    );
    addTearDown(draft.dispose);
    draft.conflict = true;
    draft.schedule();
    expect(await draft.flush(), isFalse);
    expect(writes, 0);
    draft.conflict = false;
    expect(await draft.retry(), isTrue);
    expect(writes, 1);
  });
  test('closing draft owner cancels its timer', () async {
    int writes = 0;
    final draft = ClientCardDraftController(
      isDirty: () => true,
      isValid: () => true,
      onChanged: () {},
      persist: (_) async {
        writes++;
        return true;
      },
      delay: Duration.zero,
    );
    draft.schedule();
    draft.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(writes, 0);
  });
}
