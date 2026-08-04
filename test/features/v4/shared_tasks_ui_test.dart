import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/shared_tasks_v4_panel.dart';

class _FakeSharedTasks implements SharedTasksDataSource {
  bool closed = false;
  bool failNextClose = false;
  int createCalls = 0;
  int updateCalls = 0;
  Completer<Map<String, dynamic>>? closeCompleter;
  String? listedTaskId;
  String? listedEntityType;
  String? listedEntityId;

  Map<String, dynamic> get task => {
    'id': '11111111-1111-4111-8111-111111111111',
    'title': 'Подготовить отчёт',
    'body': 'Общая задача филиала',
    'allDay': false,
    'startAt': '2020-01-01T10:00:00.000Z',
    'endAt': '2020-01-01T11:00:00.000Z',
    'state': closed ? 'closed' : 'open',
    'version': 1,
    'hasReminder': true,
    'audiences': [
      {'type': 'allBranches'},
    ],
  };

  @override
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  }) async {
    listedTaskId = taskId;
    listedEntityType = linkedEntityType;
    listedEntityId = linkedEntityId;
    final visible =
        state == null ||
        (state == 'open' && !closed) ||
        (state == 'closed' && closed);
    return {
      'items': visible ? [task] : <Map<String, dynamic>>[],
      'counters': {'open': closed ? 0 : 1, 'overdue': closed ? 0 : 1},
    };
  }

  @override
  Future<List<Map<String, dynamic>>> history(String taskId) async => [
    {
      'id': 'history-1',
      'action': 'workflow.shared_task_created',
      'actorName': 'Анна Петрова',
      'occurredAt': '2026-08-04T10:00:00.000Z',
    },
  ];

  @override
  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  ) async {
    if (failNextClose) {
      failNextClose = false;
      throw StateError('offline');
    }
    final pending = closeCompleter;
    if (pending != null) {
      final result = await pending.future;
      closed = true;
      return result;
    }
    closed = true;
    return {'taskId': taskId, 'taskVersion': 2};
  }

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async {
    createCalls++;
    return data;
  }

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async {
    updateCalls++;
    return data;
  }

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async => const [
    SharedTaskAudienceOption(
      type: 'user',
      id: '22222222-2222-4222-8222-222222222222',
      label: 'Анна Петрова',
    ),
    SharedTaskAudienceOption(
      type: 'branch',
      id: '33333333-3333-4333-8333-333333333333',
      label: 'Центральный',
    ),
  ];
}

Widget _host(
  _FakeSharedTasks source, {
  Size size = const Size(900, 900),
  EntityLink? initialLink,
  EntityLink? linkedEntity,
  bool canWrite = true,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: SharedTasksV4Panel(
          dataSource: source,
          initialLink: initialLink,
          linkedEntity: linkedEntity,
          canWrite: canWrite,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows exactly one create action per viewport', (tester) async {
    final source = _FakeSharedTasks();
    await tester.pumpWidget(_host(source, size: const Size(900, 900)));
    await tester.pumpAndSettle();
    expect(find.text('Новая задача'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.pumpWidget(_host(source, size: const Size(390, 800)));
    await tester.pumpAndSettle();
    expect(find.text('Новая задача'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('one editor creates and updates through the canonical source', (
    tester,
  ) async {
    final source = _FakeSharedTasks();
    await tester.pumpWidget(_host(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Новая задача',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();
    expect(source.createCalls, 1);

    await tester.tap(find.byTooltip('Изменить'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Изменённая задача',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(source.updateCalls, 1);
  });

  testWidgets('read-only role has no task mutation controls', (tester) async {
    await tester.pumpWidget(_host(_FakeSharedTasks(), canWrite: false));
    await tester.pumpAndSettle();

    expect(find.text('Новая задача'), findsNothing);
    expect(find.byTooltip('Изменить'), findsNothing);
  });

  testWidgets('shows non-modal reminder and explicit close action', (
    tester,
  ) async {
    final source = _FakeSharedTasks();
    await tester.pumpWidget(_host(source));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shared-task-reminder-panel')), findsOneWidget);
    expect(find.byKey(const Key('shared-task-reminder-badge')), findsOneWidget);
    expect(find.text('Закрыть задачу'), findsOneWidget);

    await tester.tap(find.text('Закрыть задачу'));
    await tester.pumpAndSettle();
    expect(find.text('Нет задач'), findsOneWidget);
  });

  testWidgets('close failure keeps task open and retries explicitly', (
    tester,
  ) async {
    final source = _FakeSharedTasks()..failNextClose = true;
    await tester.pumpWidget(_host(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Закрыть задачу'));
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось закрыть. Задача осталась открытой.'),
      findsOneWidget,
    );
    expect(find.text('Повторить закрытие'), findsOneWidget);

    await tester.tap(find.text('Повторить закрытие'));
    await tester.pumpAndSettle();
    expect(find.text('Нет задач'), findsOneWidget);
  });

  testWidgets('mobile collapsed filter is 56px and advanced filters scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(_FakeSharedTasks(), size: const Size(390, 844)),
    );
    await tester.pumpAndSettle();

    final filter = find.byKey(const Key('shared-task-mobile-filter'));
    expect(tester.getSize(filter).height, 56);
    await tester.tap(find.byTooltip('Расширенные фильтры'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('shared-task-advanced-filter-scroll')),
      findsOneWidget,
    );
  });

  testWidgets('editor exposes every audience and time mode', (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SharedTaskEditor(
            audienceOptions: [
              SharedTaskAudienceOption(
                type: 'user',
                id: '22222222-2222-4222-8222-222222222222',
                label: 'Анна Петрова',
              ),
              SharedTaskAudienceOption(
                type: 'branch',
                id: '33333333-3333-4333-8333-333333333333',
                label: 'Центральный',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Сотрудники'), findsOneWidget);
    expect(find.text('Филиал'), findsOneWidget);
    expect(find.text('Все филиалы'), findsWidgets);
    expect(find.text('На весь день'), findsOneWidget);

    await tester.tap(find.text('На весь день'));
    await tester.pumpAndSettle();
    expect(find.text('Окончание'), findsOneWidget);
    expect(find.text('Напомнить в приложении'), findsOneWidget);
  });

  testWidgets('direct task link uses canonical filters and opens history', (
    tester,
  ) async {
    final source = _FakeSharedTasks();
    await tester.pumpWidget(
      _host(
        source,
        initialLink: EntityLink.typed(
          entityType: EntityLinkType.task,
          entityId: source.task['id'].toString(),
        ),
        linkedEntity: EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: '44444444-4444-4444-8444-444444444444',
          variant: 'student',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(source.listedTaskId, source.task['id']);
    expect(source.listedEntityType, 'student');
    expect(source.listedEntityId, '44444444-4444-4444-8444-444444444444');
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Задача создана'), findsOneWidget);
  });
}
