import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

class _ListCall {
  const _ListCall({
    this.state,
    this.taskId,
    this.linkedEntityType,
    this.linkedEntityId,
    this.q,
    this.priority,
    this.scope,
    this.from,
    this.to,
  });

  final String? state;
  final String? taskId;
  final String? linkedEntityType;
  final String? linkedEntityId;
  final String? q;
  final String? priority;
  final String? scope;
  final String? from;
  final String? to;
}

class _CalendarCall {
  const _CalendarCall({required this.from, required this.to});

  final String from;
  final String to;
}

class _ControlledSharedTasksDataSource extends SharedTasksDataSource {
  final Queue<Future<Map<String, dynamic>>> listResults = Queue();
  final Queue<Future<Map<String, int>>> calendarResults = Queue();
  final Queue<Future<Map<String, dynamic>>> closeResults = Queue();
  final List<_ListCall> listCalls = [];
  final List<_CalendarCall> calendarCalls = [];
  final List<MagicMutationIdentity> closeIdentities = [];
  final List<String> closeTaskIds = [];
  final List<int> closeVersions = [];

  @override
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  }) => listFiltered(
    state: state,
    taskId: taskId,
    linkedEntityType: linkedEntityType,
    linkedEntityId: linkedEntityId,
  );

  @override
  Future<Map<String, dynamic>> listFiltered({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
    String? q,
    String? priority,
    String? scope,
    String? from,
    String? to,
  }) {
    listCalls.add(
      _ListCall(
        state: state,
        taskId: taskId,
        linkedEntityType: linkedEntityType,
        linkedEntityId: linkedEntityId,
        q: q,
        priority: priority,
        scope: scope,
        from: from,
        to: to,
      ),
    );
    return listResults.removeFirst();
  }

  @override
  Future<Map<String, int>> calendar({
    required String from,
    required String to,
    String? state,
    String? q,
    String? priority,
    String? scope,
    String? linkedEntityType,
    String? linkedEntityId,
  }) {
    calendarCalls.add(_CalendarCall(from: from, to: to));
    return calendarResults.removeFirst();
  }

  @override
  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  ) {
    closeTaskIds.add(taskId);
    closeVersions.add(expectedVersion);
    closeIdentities.add(identity);
    return closeResults.removeFirst();
  }

  @override
  Future<List<Map<String, dynamic>>> history(String taskId) async => [];

  @override
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  ) async => const {};

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async => data;

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async => data;

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async => [];
}

Map<String, dynamic> _response(
  String id, {
  String state = 'open',
  String startAt = '2026-08-22T10:00:00.000Z',
  Map<String, dynamic> counters = const {'open': 1, 'overdue': 0},
}) => {
  'items': [
    {'id': id, 'state': state, 'startAt': startAt},
  ],
  'counters': counters,
};

void main() {
  test('latest query wins when responses complete out of order', () async {
    final source = _ControlledSharedTasksDataSource();
    final open = Completer<Map<String, dynamic>>();
    final closed = Completer<Map<String, dynamic>>();
    source.listResults.addAll([open.future, closed.future]);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    final first = controller.setQuery(const SharedTasksQuery(state: 'open'));
    final second = controller.setQuery(const SharedTasksQuery(state: 'closed'));
    closed.complete(_response('closed', state: 'closed'));
    await second;
    open.complete(_response('open'));
    await first;

    expect(controller.state.query.state, 'closed');
    expect(controller.state.items.single['id'], 'closed');
  });

  test('refresh error retains the last successful items', () async {
    final source = _ControlledSharedTasksDataSource();
    source.listResults.addAll([
      Future.value(_response('kept')),
      Future.error(StateError('offline')),
    ]);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    await controller.setQuery(const SharedTasksQuery(state: 'open'));
    await controller.refresh();

    expect(controller.state.items.single['id'], 'kept');
    expect(controller.state.error, isA<StateError>());
    expect(controller.state.loading, isFalse);
    expect(controller.state.hasLoaded, isTrue);
    expect(controller.state.successfulQuery, controller.state.appliedQuery);
    expect(controller.state.contentQueryChanged, isFalse);
  });

  test('calendar responses cannot overwrite a newer month', () async {
    final source = _ControlledSharedTasksDataSource();
    final august = Completer<Map<String, int>>();
    final september = Completer<Map<String, int>>();
    source.listResults.addAll([
      Future.value(_response('august')),
      Future.value(_response('september')),
    ]);
    source.calendarResults.addAll([august.future, september.future]);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    final first = controller.setQuery(
      SharedTasksQuery(calendarMode: true, calendarMonth: DateTime(2026, 8)),
    );
    await pumpEventQueue();
    final second = controller.setQuery(
      SharedTasksQuery(calendarMode: true, calendarMonth: DateTime(2026, 9)),
    );
    await pumpEventQueue();
    september.complete(const {'2026-09-02': 3});
    await second;
    august.complete(const {'2026-08-01': 9});
    await first;

    expect(controller.state.calendar, const {'2026-09-02': 3});
    expect(controller.state.query.calendarMonth, DateTime(2026, 9));
  });

  test('focused and day queries preserve live normalization', () async {
    final source = _ControlledSharedTasksDataSource();
    source.listResults.addAll([
      Future.value(_response('focused')),
      Future.value(_response('day')),
    ]);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    await controller.setQuery(
      SharedTasksQuery(
        state: 'overdue',
        taskId: 'task-1',
        linkedEntityType: 'student',
        linkedEntityId: 'student-1',
        search: '  отчёт  ',
        priority: 'all',
        scope: 'mine',
        day: DateTime(2026, 8, 22),
      ),
    );
    await controller.setQuery(
      SharedTasksQuery(
        state: 'all',
        priority: 'high',
        scope: 'branch',
        day: DateTime(2026, 8, 22),
      ),
    );

    final focused = source.listCalls.first;
    expect(focused.state, isNull);
    expect(focused.taskId, 'task-1');
    expect(focused.linkedEntityType, 'student');
    expect(focused.linkedEntityId, 'student-1');
    expect(focused.q, 'отчёт');
    expect(focused.priority, isNull);
    expect(focused.from, isNull);
    expect(focused.to, isNull);

    final day = source.listCalls.last;
    expect(day.state, isNull);
    expect(day.priority, 'high');
    expect(day.scope, 'branch');
    expect(day.from, '2026-08-21T21:00:00.000Z');
    expect(day.to, '2026-08-22T21:00:00.000Z');
  });

  test(
    'draft query changes feed refresh without loading immediately',
    () async {
      final source = _ControlledSharedTasksDataSource();
      source.listResults.add(Future.value(_response('searched')));
      final controller = SharedTasksController(dataSource: source);
      addTearDown(controller.dispose);

      controller.updateQuery(
        controller.state.query.copyWith(search: '  новый текст  '),
      );
      expect(source.listCalls, isEmpty);
      await controller.refresh();

      expect(source.listCalls.single.q, 'новый текст');
    },
  );

  test('draft search does not strand an active initial load', () async {
    final source = _ControlledSharedTasksDataSource();
    final pending = Completer<Map<String, dynamic>>();
    source.listResults.add(pending.future);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    final loading = controller.setQuery(const SharedTasksQuery());
    controller.updateQuery(controller.state.query.copyWith(search: 'черновик'));
    expect(controller.state.loading, isTrue);
    pending.complete(_response('loaded'));
    await loading;

    expect(controller.state.items.single['id'], 'loaded');
    expect(controller.state.query.search, 'черновик');
    expect(controller.state.successfulQuery?.search, isNull);
  });

  test('draft search does not strand a close-triggered refresh', () async {
    final source = _ControlledSharedTasksDataSource();
    final refreshed = Completer<Map<String, dynamic>>();
    source.listResults.addAll([
      Future.value(_response('task-1')),
      refreshed.future,
    ]);
    source.closeResults.add(Future.value(const {'id': 'task-1'}));
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);
    await controller.setQuery(const SharedTasksQuery());

    final closing = controller.close(const {'id': 'task-1', 'version': 3});
    await pumpEventQueue();
    controller.updateQuery(
      controller.state.query.copyWith(search: 'после закрытия'),
    );
    refreshed.complete({'items': <Map<String, dynamic>>[]});
    expect((await closing).succeeded, isTrue);

    expect(controller.state.items, isEmpty);
    expect(controller.state.query.search, 'после закрытия');
    expect(controller.state.successfulQuery?.search, isNull);
  });

  test('failed changed query retains explicitly associated content', () async {
    final source = _ControlledSharedTasksDataSource();
    source.listResults.addAll([
      Future.value(_response('open')),
      Future.error(StateError('closed offline')),
      Future.value(_response('closed', state: 'closed')),
      Future.value(_response('draft', state: 'closed')),
    ]);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);
    await controller.setQuery(const SharedTasksQuery(state: 'open'));

    await controller.setQuery(
      const SharedTasksQuery(state: 'closed', search: 'failed search'),
    );
    expect(controller.state.items.single['id'], 'open');
    expect(controller.state.appliedQuery.state, 'closed');
    expect(controller.state.successfulQuery?.state, 'open');
    expect(controller.state.contentQueryChanged, isTrue);

    controller.updateQuery(
      controller.state.query.copyWith(search: 'newer draft'),
    );
    await controller.retry();
    expect(controller.state.items.single['id'], 'closed');
    expect(controller.state.error, isNull);
    expect(controller.state.contentQueryChanged, isFalse);
    expect(controller.state.query.search, 'newer draft');
    expect(controller.state.appliedQuery.search, 'failed search');
    expect(controller.state.successfulQuery?.search, 'failed search');

    await controller.refresh();
    expect(source.listCalls.last.q, 'newer draft');
    expect(controller.state.items.single['id'], 'draft');
  });

  test('linked results own local counters and overdue filtering', () async {
    final source = _ControlledSharedTasksDataSource();
    source.listResults.add(
      Future.value({
        'items': [
          {
            'id': 'overdue',
            'state': 'open',
            'startAt': '2020-01-01T10:00:00.000Z',
          },
          {
            'id': 'future',
            'state': 'open',
            'startAt': '2999-01-01T10:00:00.000Z',
          },
          {
            'id': 'closed',
            'state': 'closed',
            'startAt': '2020-01-01T10:00:00.000Z',
          },
        ],
        'counters': {'open': 99, 'overdue': 99},
      }),
    );
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    await controller.setQuery(
      const SharedTasksQuery(
        state: 'overdue',
        linkedEntityType: 'student',
        linkedEntityId: 'student-1',
      ),
    );

    expect(controller.state.items.single['id'], 'overdue');
    expect(controller.state.counters, const {'open': 1, 'overdue': 1});
  });

  test(
    'close failure reuses identity and success clears command state',
    () async {
      final source = _ControlledSharedTasksDataSource();
      source.closeResults.addAll([
        Future.error(StateError('offline')),
        Future.value(const {'id': 'task-1'}),
        Future.value(const {'id': 'task-1'}),
      ]);
      source.listResults.addAll([
        Future.value(_response('task-1', state: 'closed')),
        Future.value(_response('task-1', state: 'closed')),
      ]);
      final controller = SharedTasksController(dataSource: source);
      addTearDown(controller.dispose);
      const task = {'id': 'task-1', 'version': 7};

      final failed = await controller.close(task);
      expect(failed.succeeded, isFalse);
      expect(controller.state.closeErrors['task-1'], isA<StateError>());

      final succeeded = await controller.close(task);
      expect(succeeded.succeeded, isTrue);
      expect(source.closeIdentities, hasLength(2));
      expect(source.closeIdentities.last, same(source.closeIdentities.first));
      expect(source.closeTaskIds, everyElement('task-1'));
      expect(source.closeVersions, everyElement(7));
      expect(controller.state.closing, isEmpty);
      expect(controller.state.closeErrors, isEmpty);

      expect((await controller.close(task)).succeeded, isTrue);
      expect(source.closeIdentities, hasLength(3));
      expect(
        source.closeIdentities.last,
        isNot(same(source.closeIdentities.first)),
      );
    },
  );

  test('stale list failure cannot replace a newer success', () async {
    final source = _ControlledSharedTasksDataSource();
    final stale = Completer<Map<String, dynamic>>();
    source.listResults.addAll([
      stale.future,
      Future.value(_response('closed', state: 'closed')),
    ]);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    final first = controller.setQuery(const SharedTasksQuery(state: 'open'));
    await controller.setQuery(const SharedTasksQuery(state: 'closed'));
    stale.completeError(StateError('stale offline'));
    await first;

    expect(controller.state.items.single['id'], 'closed');
    expect(controller.state.error, isNull);
  });

  test('stale calendar failure cannot replace a newer success', () async {
    final source = _ControlledSharedTasksDataSource();
    final stale = Completer<Map<String, int>>();
    source.listResults.addAll([
      Future.value(_response('august')),
      Future.value(_response('september')),
    ]);
    source.calendarResults.addAll([
      stale.future,
      Future.value(const {'2026-09-03': 2}),
    ]);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    final first = controller.setQuery(
      SharedTasksQuery(calendarMode: true, calendarMonth: DateTime(2026, 8)),
    );
    await pumpEventQueue();
    await controller.setQuery(
      SharedTasksQuery(calendarMode: true, calendarMonth: DateTime(2026, 9)),
    );
    stale.completeError(StateError('stale calendar'));
    await first;

    expect(controller.state.calendar, const {'2026-09-03': 2});
    expect(controller.state.error, isNull);
  });

  test('close refresh cannot overwrite a newer explicit query', () async {
    final source = _ControlledSharedTasksDataSource();
    final closeRefresh = Completer<Map<String, dynamic>>();
    source.listResults.addAll([
      Future.value(_response('open')),
      closeRefresh.future,
      Future.value(_response('closed', state: 'closed')),
    ]);
    source.closeResults.add(Future.value(const {'id': 'task-1'}));
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);
    await controller.setQuery(const SharedTasksQuery(state: 'open'));

    final closing = controller.close(const {'id': 'task-1', 'version': 4});
    await pumpEventQueue();
    await controller.setQuery(const SharedTasksQuery(state: 'closed'));
    closeRefresh.complete(_response('stale-open'));
    expect((await closing).succeeded, isTrue);

    expect(controller.state.query.state, 'closed');
    expect(controller.state.items.single['id'], 'closed');
  });

  test('duplicate pending close is ignored', () async {
    final source = _ControlledSharedTasksDataSource();
    final pending = Completer<Map<String, dynamic>>();
    source.closeResults.add(pending.future);
    source.listResults.add(Future.value({'items': <Map<String, dynamic>>[]}));
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);
    const task = {'id': 'task-1', 'version': 5};

    final first = controller.close(task);
    final duplicate = await controller.close(task);
    expect(duplicate.succeeded, isFalse);
    expect(source.closeTaskIds, ['task-1']);
    expect(controller.state.closing, {'task-1'});

    pending.complete(const {'id': 'task-1'});
    expect((await first).succeeded, isTrue);
    expect(controller.state.closing, isEmpty);
  });

  test('initial failure can recover and clears the error', () async {
    final source = _ControlledSharedTasksDataSource();
    source.listResults.addAll([
      Future.error(StateError('offline')),
      Future.value(_response('recovered')),
    ]);
    final controller = SharedTasksController(dataSource: source);
    addTearDown(controller.dispose);

    await controller.setQuery(const SharedTasksQuery());
    expect(controller.state.hasLoaded, isFalse);
    expect(controller.state.error, isA<StateError>());
    await controller.retry();

    expect(controller.state.items.single['id'], 'recovered');
    expect(controller.state.hasLoaded, isTrue);
    expect(controller.state.error, isNull);
  });

  test('pending completion does not notify after dispose', () async {
    final source = _ControlledSharedTasksDataSource();
    final pending = Completer<Map<String, dynamic>>();
    source.listResults.add(pending.future);
    final controller = SharedTasksController(dataSource: source);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final loading = controller.setQuery(const SharedTasksQuery());
    expect(notifications, 1);
    controller.dispose();
    pending.complete(_response('late'));
    await loading;

    expect(notifications, 1);
  });

  testWidgets('refresh stream is debounced and canceled on dispose', (
    tester,
  ) async {
    final source = _ControlledSharedTasksDataSource();
    source.listResults.addAll([
      Future.value(_response('initial')),
      Future.value(_response('refreshed')),
    ]);
    final refreshes = StreamController<void>.broadcast(sync: true);
    final controller = SharedTasksController(
      dataSource: source,
      refreshes: refreshes.stream,
    );
    await controller.setQuery(const SharedTasksQuery());
    expect(source.listCalls, hasLength(1));

    refreshes.add(null);
    refreshes.add(null);
    await tester.pump(const Duration(milliseconds: 199));
    expect(source.listCalls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(source.listCalls, hasLength(2));

    controller.dispose();
    refreshes.add(null);
    await tester.pump(const Duration(milliseconds: 200));
    expect(source.listCalls, hasLength(2));
    await refreshes.close();
  });
}
