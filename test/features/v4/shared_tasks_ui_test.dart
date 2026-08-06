import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/shared_tasks_v4_panel.dart';

class _FakeSharedTasks extends SharedTasksDataSource {
  bool closed = false;
  bool failNextClose = false;
  int createCalls = 0;
  int updateCalls = 0;
  Completer<Map<String, dynamic>>? closeCompleter;
  String? listedTaskId;
  String? listedEntityType;
  String? listedEntityId;
  String? listedQuery;
  String? listedPriority;
  String? listedScope;
  int calendarCalls = 0;
  Map<String, dynamic>? lastCreateData;
  bool failAudiencePreview = false;

  Map<String, dynamic> get task => {
    'id': '11111111-1111-4111-8111-111111111111',
    'title': 'Подготовить отчёт',
    'body': 'Общая задача филиала',
    'allDay': false,
    'startAt': '2020-01-01T10:00:00.000Z',
    'endAt': '2020-01-01T11:00:00.000Z',
    'state': closed ? 'closed' : 'open',
    'priority': 'medium',
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
    listedQuery = q;
    listedPriority = priority;
    listedScope = scope;
    return list(
      state: state,
      taskId: taskId,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
    );
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
  }) async {
    calendarCalls++;
    return const {};
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
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  ) async {
    if (failAudiencePreview) throw StateError('preview unavailable');
    final selectors = audiences.map((audience) {
      final type = audience['type'];
      final id = audience['targetId']?.toString();
      SharedTaskAudienceOption? option;
      for (final candidate in audienceOptionsSync) {
        if (candidate.id == id) option = candidate;
      }
      final count = switch (type) {
        'user' => 1,
        'branch' => 3,
        _ => 8,
      };
      return <String, dynamic>{
        'type': type,
        'targetId': ?id,
        'label': type == 'allBranches' ? 'Вся школа' : option?.label,
        'mode': type == 'user' ? 'fixed' : 'dynamic',
        'currentRecipientCount': count,
      };
    }).toList();
    return {
      'totalRecipients': selectors.fold<int>(
        0,
        (sum, item) => sum + (item['currentRecipientCount'] as int),
      ),
      'hasDynamicMembership': audiences.any((item) => item['type'] != 'user'),
      'selectors': selectors,
      'recipients': const <Map<String, dynamic>>[],
    };
  }

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
    lastCreateData = data;
    return {
      ...data,
      'recipientSummary': await previewAudience(
        (data['audiences'] as List).whereType<Map<String, dynamic>>().toList(),
      ),
    };
  }

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async {
    updateCalls++;
    return {
      ...data,
      'recipientSummary': await previewAudience(
        (data['audiences'] as List).whereType<Map<String, dynamic>>().toList(),
      ),
    };
  }

  List<SharedTaskAudienceOption> get audienceOptionsSync => const [
    SharedTaskAudienceOption(
      type: 'user',
      id: '22222222-2222-4222-8222-222222222222',
      label: 'Анна Петрова',
    ),
    SharedTaskAudienceOption(
      type: 'user',
      id: '55555555-5555-4555-8555-555555555555',
      label: 'Олег Сидоров',
    ),
    SharedTaskAudienceOption(
      type: 'branch',
      id: '33333333-3333-4333-8333-333333333333',
      label: 'Центральный',
    ),
  ];

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async =>
      audienceOptionsSync;
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
  testWidgets('section root is not treated as a missing linked task', (
    tester,
  ) async {
    final source = _FakeSharedTasks()..closed = true;
    await tester.pumpWidget(
      _host(
        source,
        initialLink: EntityLink.typed(
          entityType: EntityLinkType.task,
          entityId: '__section__',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(source.listedTaskId, isNull);
    expect(find.text('Связанная запись недоступна.'), findsNothing);
  });

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
    await tester.tap(find.byKey(const Key('shared-task-priority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Высокий').last);
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Создать'));
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();
    expect(source.createCalls, 1);
    expect(source.lastCreateData?['priority'], 'high');
    expect(find.text('Задача создана. Получателей сейчас: 8.'), findsOneWidget);

    await tester.tap(find.byTooltip('Изменить'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Изменённая задача',
    );
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(source.updateCalls, 1);
  });

  testWidgets('search, priority and calendar use the canonical query', (
    tester,
  ) async {
    final source = _FakeSharedTasks();
    await tester.pumpWidget(_host(source));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('shared-task-search')),
      'отчёт',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shared-task-priority-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Высокий').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shared-task-scope-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мой филиал').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('shared-task-calendar-toggle')),
    );
    await tester.tap(find.byKey(const Key('shared-task-calendar-toggle')));
    await tester.pumpAndSettle();

    expect(source.listedQuery, 'отчёт');
    expect(source.listedPriority, 'high');
    expect(source.listedScope, 'branch');
    expect(source.calendarCalls, 1);
    expect(find.byKey(const Key('shared-task-month-grid')), findsOneWidget);
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
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    expect(
      find.byKey(const Key('shared-task-advanced-filter-scroll')),
      findsOneWidget,
    );
  });

  testWidgets('mobile task editor opens as an expandable full-width sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(_FakeSharedTasks(), size: const Size(390, 844)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    expect(find.text('Развернуть'), findsOneWidget);
    expect(find.text('Сейчас получат: 8'), findsOneWidget);

    await tester.tap(find.text('Развернуть'));
    await tester.pumpAndSettle();
    expect(find.text('Свернуть'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.text('Один филиал'), findsOneWidget);
    expect(find.text('Вся школа'), findsWidgets);
    expect(find.text('На весь день'), findsOneWidget);

    await tester.tap(find.text('На весь день'));
    await tester.pumpAndSettle();
    expect(find.text('Окончание'), findsOneWidget);
    expect(find.text('Напомнить в приложении'), findsOneWidget);
  });

  testWidgets('recipient preview distinguishes people, branch and school', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = _FakeSharedTasks();
    await tester.pumpWidget(_host(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    expect(find.text('Сейчас получат: 8'), findsOneWidget);
    expect(
      find.textContaining('Вся школа — динамический состав'),
      findsOneWidget,
    );

    await tester.tap(find.text('Сотрудники'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shared-task-audience-target')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Анна Петрова').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить получателя'));
    await tester.pumpAndSettle();
    expect(find.text('Сейчас получат: 1'), findsOneWidget);
    expect(find.textContaining('Анна Петрова — лично'), findsOneWidget);
    expect(
      find.textContaining('Вся школа — динамический состав'),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('shared-task-audience-target')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Олег Сидоров').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить получателя'));
    await tester.pumpAndSettle();
    expect(find.text('Сейчас получат: 2'), findsOneWidget);

    await tester.tap(find.text('Один филиал'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shared-task-audience-target')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Центральный').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить получателя'));
    await tester.pumpAndSettle();
    expect(find.text('Сейчас получат: 5'), findsOneWidget);
    expect(
      find.textContaining('Центральный — динамический состав'),
      findsOneWidget,
    );

    await tester.tap(find.text('Вся школа').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить получателя'));
    await tester.pumpAndSettle();
    expect(find.text('Сейчас получат: 8'), findsOneWidget);
    expect(find.textContaining('Анна Петрова — лично'), findsNothing);
    expect(
      find.textContaining('Центральный — динамический состав'),
      findsNothing,
    );
  });

  testWidgets('failed recipient preview blocks submit until retry succeeds', (
    tester,
  ) async {
    final source = _FakeSharedTasks()..failAudiencePreview = true;
    await tester.pumpWidget(_host(source));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Проверить получателей',
    );
    await tester.pump();

    expect(find.text('Повторить расчёт'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать'))
          .onPressed,
      isNull,
    );

    source.failAudiencePreview = false;
    await tester.ensureVisible(find.text('Повторить расчёт'));
    await tester.tap(find.text('Повторить расчёт'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать'))
          .onPressed,
      isNotNull,
    );
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
