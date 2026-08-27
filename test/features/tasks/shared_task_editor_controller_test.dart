import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

class _RecordingDataSource extends SharedTasksDataSource {
  int createCalls = 0;
  int updateCalls = 0;
  int failuresRemaining = 0;
  Completer<Map<String, dynamic>>? pendingMutation;
  final identities = <MagicMutationIdentity>[];
  final payloads = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    createCalls++;
    return _mutate(data, identity);
  }

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    updateCalls++;
    return _mutate(data, identity);
  }

  Future<Map<String, dynamic>> _mutate(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async {
    identities.add(identity);
    payloads.add(Map<String, dynamic>.from(data));
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('offline');
    }
    return pendingMutation?.future ??
        {
          ...data,
          'recipientSummary': {'totalRecipients': 4},
        };
  }

  @override
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  ) async => {
    'totalRecipients': audiences.length,
    'selectors': const <Map<String, dynamic>>[],
  };

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async => const [];

  @override
  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  ) async => const {};

  @override
  Future<List<Map<String, dynamic>>> history(String taskId) async => const [];

  @override
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  }) async => {'items': <Map<String, dynamic>>[]};
}

Map<String, dynamic> _task({List<Map<String, dynamic>> reminders = const []}) =>
    {
      'id': 'task-7',
      'version': 7,
      'title': 'Исходная задача',
      'body': 'Описание',
      'allDay': false,
      'startAt': '2026-08-28T10:00:00.000Z',
      'endAt': '2026-08-28T11:00:00.000Z',
      'priority': 'medium',
      'audiences': [
        {'type': 'allBranches'},
      ],
      'reminders': reminders,
    };

void main() {
  test('a stale audience preview cannot replace the newest preview', () async {
    final source = _RecordingDataSource();
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    var call = 0;
    final controller = SharedTaskEditorController(
      dataSource: source,
      previewLoader: (_) => call++ == 0 ? first.future : second.future,
    );

    final firstLoad = controller.refreshAudiencePreview();
    final secondLoad = controller.refreshAudiencePreview();
    second.complete({'totalRecipients': 2});
    await secondLoad;
    first.complete({'totalRecipients': 1});
    await firstLoad;

    expect(controller.preview, {'totalRecipients': 2});
    expect(controller.previewLoading, isFalse);
  });

  test('submit is ignored until audience preview succeeds', () async {
    final source = _RecordingDataSource();
    final controller = SharedTaskEditorController(dataSource: source)
      ..setTitle('Новая задача');

    final outcome = await controller.submit();

    expect(outcome, isA<SharedTaskSubmitIgnored>());
    expect(source.createCalls, 0);
  });

  test('same payload reuses identity and changed payload rotates it', () async {
    final source = _RecordingDataSource()..failuresRemaining = 2;
    final controller = SharedTaskEditorController(dataSource: source)
      ..setTitle('Версия 1');
    await controller.refreshAudiencePreview();

    expect(await controller.submit(), isA<SharedTaskSubmitFailure>());
    expect(await controller.submit(), isA<SharedTaskSubmitFailure>());
    expect(source.identities[1], same(source.identities[0]));

    controller.setTitle('Версия 2');
    expect(await controller.submit(), isA<SharedTaskSubmitSuccess>());
    expect(
      source.identities[2].idempotencyKey,
      isNot(source.identities[0].idempotencyKey),
    );
  });

  test('in-app reminder merge preserves email and push channels', () async {
    final reminders = <Map<String, dynamic>>[
      {'dueAt': '2026-08-28T07:00:00.000Z', 'channel': 'email'},
      {'dueAt': '2026-08-28T07:30:00.000Z', 'channel': 'push'},
    ];
    final source = _RecordingDataSource();
    final controller = SharedTaskEditorController(
      dataSource: source,
      task: _task(reminders: reminders),
    )..setReminder(true);
    await controller.refreshAudiencePreview();

    expect(await controller.submit(), isA<SharedTaskSubmitSuccess>());

    final payloadReminders = (source.payloads.single['reminders'] as List)
        .whereType<Map<String, dynamic>>()
        .toList();
    expect(payloadReminders.take(2), reminders);
    expect(
      payloadReminders.where((item) => item['channel'] == 'in_app'),
      hasLength(1),
    );
  });

  test('in-app reminder without dueAt follows a changed start time', () async {
    final source = _RecordingDataSource();
    final controller = SharedTaskEditorController(
      dataSource: source,
      task: _task(
        reminders: [
          {'dueAt': null, 'channel': 'in_app'},
        ],
      ),
    );
    final changedStart = DateTime(2026, 9, 3, 14);
    controller
      ..setStart(changedStart)
      ..setEnd(changedStart.add(const Duration(hours: 1)));
    await controller.refreshAudiencePreview();

    expect(await controller.submit(), isA<SharedTaskSubmitSuccess>());

    final reminders = source.payloads.single['reminders'] as List;
    expect(reminders.single, {
      'dueAt': changedStart
          .subtract(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
      'channel': 'in_app',
    });
  });

  test('late mutation after dispose emits no state notification', () async {
    final source = _RecordingDataSource();
    final pending = Completer<Map<String, dynamic>>();
    source.pendingMutation = pending;
    final controller = SharedTaskEditorController(dataSource: source)
      ..setTitle('Отложенная задача');
    await controller.refreshAudiencePreview();
    var notifications = 0;
    controller.addListener(() => notifications++);

    final submitted = controller.submit();
    final notificationsBeforeDispose = notifications;
    controller.dispose();
    pending.complete({
      'recipientSummary': {'totalRecipients': 4},
    });

    expect(await submitted, isA<SharedTaskSubmitSuccess>());
    expect(notifications, notificationsBeforeDispose);
  });

  test('success is terminal and cannot issue a follow-up mutation', () async {
    final source = _RecordingDataSource();
    final controller = SharedTaskEditorController(dataSource: source)
      ..setTitle('Успешная задача');
    await controller.refreshAudiencePreview();

    expect(await controller.submit(), isA<SharedTaskSubmitSuccess>());
    expect(controller.terminalSuccess, isTrue);
    expect(await controller.submit(), isA<SharedTaskSubmitIgnored>());
    expect(source.createCalls, 1);
  });
}
