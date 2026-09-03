import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';

class FakeSharedTasksDataSource extends SharedTasksDataSource {
  bool closed = false;
  bool failNextList = false;
  Completer<Map<String, dynamic>>? nextListCompleter;
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
  String? listedFrom;
  String? listedTo;
  int calendarCalls = 0;
  int listCalls = 0;
  Map<String, dynamic>? lastCreateData;
  bool failAudiencePreview = false;
  bool taskAllDay = false;
  DateTime? taskStartAt;

  Map<String, dynamic> get task => {
    'id': '11111111-1111-4111-8111-111111111111',
    'title': 'Подготовить отчёт',
    'body': 'Общая задача филиала',
    'allDay': taskAllDay,
    'startAt': taskStartAt?.toIso8601String() ?? '2020-01-01T10:00:00.000Z',
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
    listCalls++;
    if (failNextList) {
      failNextList = false;
      throw StateError('list unavailable');
    }
    final pending = nextListCompleter;
    if (pending != null) {
      nextListCompleter = null;
      return pending.future;
    }
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
    listedFrom = from;
    listedTo = to;
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

class SwitchingSharedTasksDataSource extends FakeSharedTasksDataSource {
  final responses = <Completer<Map<String, dynamic>>>[];
  final taskIds = <String?>[];
  final linkedIds = <String?>[];

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
    taskIds.add(taskId);
    linkedIds.add(linkedEntityId);
    final response = Completer<Map<String, dynamic>>();
    responses.add(response);
    return response.future;
  }
}

Widget _host(
  FakeSharedTasksDataSource source, {
  Size size = const Size(900, 900),
  EntityLink? initialLink,
  EntityLink? linkedEntity,
  bool canWrite = true,
  bool defaultToMineToday = false,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(
        platform: size.width >= 840
            ? TargetPlatform.windows
            : TargetPlatform.android,
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: SharedTasksPanel(
          dataSource: source,
          initialLink: initialLink,
          linkedEntity: linkedEntity,
          canWrite: canWrite,
          defaultToMineToday: defaultToMineToday,
        ),
      ),
    ),
  );
}

Future<void> _scrollTaskFormTo(WidgetTester tester, Finder target) async {
  for (
    var drag = 0;
    drag < 5 && target.hitTestable().evaluate().isEmpty;
    drag++
  ) {
    await tester.drag(
      find.byKey(const ValueKey('magic-sheet-body-scroll')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('section root is not treated as a missing linked task', (
    tester,
  ) async {
    final source = FakeSharedTasksDataSource()..closed = true;
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
    final source = FakeSharedTasksDataSource();
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
    final source = FakeSharedTasksDataSource();
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
    final source = FakeSharedTasksDataSource();
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

  testWidgets('failed filter keeps content visible with retry notice', (
    tester,
  ) async {
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(_host(source));
    await tester.pumpAndSettle();
    expect(find.text('Подготовить отчёт'), findsOneWidget);

    source.failNextList = true;
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Закрытые').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shared-tasks-stale-notice')), findsOneWidget);
    expect(find.textContaining('предыдущего запроса'), findsOneWidget);
    expect(find.text('Подготовить отчёт'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Повторить'), findsOneWidget);

    final retry = Completer<Map<String, dynamic>>();
    source.nextListCompleter = retry;
    await tester.tap(find.widgetWithText(TextButton, 'Повторить'));
    await tester.pump();
    expect(find.byKey(const Key('shared-tasks-stale-notice')), findsOneWidget);
    expect(find.textContaining('Загружаем выбранный'), findsOneWidget);
    expect(find.text('Подготовить отчёт'), findsOneWidget);

    source.closed = true;
    retry.complete({
      'items': [source.task],
      'counters': {'open': 0, 'overdue': 0},
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-tasks-stale-notice')), findsNothing);
  });

  testWidgets('read-only role has no task mutation controls', (tester) async {
    await tester.pumpWidget(
      _host(FakeSharedTasksDataSource(), canWrite: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Новая задача'), findsNothing);
    expect(find.byTooltip('Изменить'), findsNothing);
  });

  testWidgets('admin board starts with my tasks and today, both removable', (
    tester,
  ) async {
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(
      _host(source, canWrite: false, defaultToMineToday: true),
    );
    await tester.pumpAndSettle();

    expect(source.listedScope, 'mine');
    expect(source.listedFrom, isNotNull);
    expect(source.listedTo, isNotNull);
    expect(find.text('Мои задачи'), findsOneWidget);
    final today = tester.widget<ChoiceChip>(
      find.byKey(const Key('shared-task-today-filter')),
    );
    expect(today.selected, isTrue);
    expect(find.text('Новая задача'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('shared-task-today-filter')),
    );
    await tester.tap(find.byKey(const Key('shared-task-today-filter')));
    await tester.pumpAndSettle();
    expect(source.listedFrom, isNull);
    expect(source.listedTo, isNull);

    await tester.ensureVisible(
      find.byKey(const Key('shared-task-scope-filter')),
    );
    await tester.tap(find.byKey(const Key('shared-task-scope-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мой филиал').last);
    await tester.pumpAndSettle();
    expect(source.listedScope, 'branch');
  });

  testWidgets('all-day task due today is not overdue', (tester) async {
    final moscowNow = DateTime.now().toUtc().add(const Duration(hours: 3));
    final source = FakeSharedTasksDataSource()
      ..taskAllDay = true
      ..taskStartAt = DateTime.utc(
        moscowNow.year,
        moscowNow.month,
        moscowNow.day,
      ).subtract(const Duration(hours: 3));
    await tester.pumpWidget(
      _host(
        source,
        linkedEntity: EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: '44444444-4444-4444-8444-444444444444',
          variant: 'student',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Просроченных задач:'), findsNothing);
  });

  testWidgets('shows non-modal reminder and explicit close action', (
    tester,
  ) async {
    final source = FakeSharedTasksDataSource();
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
    final source = FakeSharedTasksDataSource()..failNextClose = true;
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
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(_host(source, size: const Size(390, 844)));
    await tester.pumpAndSettle();

    final filter = find.byKey(const Key('shared-task-mobile-filter'));
    expect(tester.getSize(filter).height, 56);
    final callsBeforeSelection = source.listCalls;
    await tester.tap(find.byTooltip('Расширенные фильтры'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    expect(find.byKey(const ValueKey('magic-sheet-frame')), findsOneWidget);
    expect(find.text('Фильтры задач'), findsOneWidget);
    expect(find.byTooltip('Развернуть'), findsOneWidget);
    expect(
      find.byKey(const Key('shared-task-advanced-filter-scroll')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Развернуть'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Свернуть'), findsOneWidget);

    await tester.tap(find.text('Закрытые').last);
    await tester.pumpAndSettle();
    expect(source.listCalls, callsBeforeSelection + 1);
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsNothing);
  });

  testWidgets('wide host opens centered advanced filters for narrow panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1000, 900)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 390,
                  height: 700,
                  child: SharedTasksPanel(
                    dataSource: source,
                    embedded: true,
                    canWrite: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-task-mobile-filter')), findsOneWidget);
    final callsBeforeSelection = source.listCalls;

    await tester.tap(find.byTooltip('Расширенные фильтры'));
    await tester.pumpAndSettle();
    expect(find.text('Фильтры задач'), findsOneWidget);
    expect(find.byTooltip('Закрыть'), findsOneWidget);
    expect(find.byKey(const ValueKey('magic-dialog-desktop')), findsOneWidget);
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsNothing);

    await tester.tap(find.text('Закрытые').last);
    await tester.pumpAndSettle();
    expect(source.listCalls, callsBeforeSelection + 1);
    expect(find.text('Фильтры задач'), findsNothing);
  });

  testWidgets(
    'mobile task editor reaches dates, audience and save by scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeSharedTasksDataSource();
      final previousHitTestPolicy =
          WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(
        () => WidgetController.hitTestWarningShouldBeFatal =
            previousHitTestPolicy,
      );
      await tester.pumpWidget(_host(source, size: const Size(390, 844)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Новая задача'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
      expect(find.byTooltip('Развернуть'), findsOneWidget);
      expect(find.text('Сейчас получат: 8'), findsOneWidget);

      await tester.tap(find.byTooltip('Развернуть'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Свернуть'), findsOneWidget);
      expect(find.byKey(const ValueKey('magic-dialog-desktop')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('shared-task-title')),
        'Задача с телефона',
      );
      await tester.tap(find.text('На весь день').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Начало').hitTestable());
      await tester.pumpAndSettle();
      final dateContext = tester.element(find.byType(DatePickerDialog));
      await tester.tap(
        find
            .text(MaterialLocalizations.of(dateContext).okButtonLabel)
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      final timeContext = tester.element(find.byType(TimePickerDialog));
      await tester.tap(
        find
            .text(MaterialLocalizations.of(timeContext).okButtonLabel)
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);

      await _scrollTaskFormTo(tester, find.text('Сотрудники'));
      await tester.tap(find.text('Сотрудники').hitTestable());
      await tester.pumpAndSettle();
      final audience = find.byKey(const Key('shared-task-audience-target'));
      await _scrollTaskFormTo(tester, audience);
      await tester.tap(audience.hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Анна Петрова').last.hitTestable());
      await tester.pumpAndSettle();
      await _scrollTaskFormTo(tester, find.text('Добавить получателя'));
      await tester.tap(find.text('Добавить получателя').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Сейчас получат: 1'), findsOneWidget);

      await _scrollTaskFormTo(tester, find.text('Напомнить в приложении'));
      await tester.tap(find.text('Напомнить в приложении').hitTestable());
      await tester.pumpAndSettle();
      final reminder = find.byKey(const Key('shared-task-reminder-at'));
      await _scrollTaskFormTo(tester, reminder);
      expect(reminder.hitTestable(), findsOneWidget);
      final create = find.widgetWithText(FilledButton, 'Создать');
      await _scrollTaskFormTo(tester, create);
      await tester.tap(create.hitTestable());
      await tester.pumpAndSettle();
      expect(source.createCalls, 1);
      expect(source.lastCreateData?['allDay'], isFalse);
      expect(source.lastCreateData?['reminders'], hasLength(1));
      expect(source.lastCreateData?['audiences'], [
        {'type': 'user', 'targetId': '22222222-2222-4222-8222-222222222222'},
      ]);
      expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor exposes every audience and time mode', (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: SharedTaskEditor(
            dataSource: source,
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

  testWidgets('creates explicit all-day and interval reminder payloads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(_host(source, size: const Size(1100, 1100)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Задача на весь день',
    );
    await tester.tap(find.text('Напомнить в приложении'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-task-reminder-at')), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Создать'));
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    final allDay = Map<String, dynamic>.from(source.lastCreateData!);
    final allDayStart = DateTime.parse(allDay['startAt'].toString()).toLocal();
    final allDayReminder = DateTime.parse(
      ((allDay['reminders'] as List).single as Map)['dueAt'].toString(),
    ).toLocal();
    expect(allDay['allDay'], isTrue);
    expect(allDay.containsKey('endAt'), isFalse);
    expect(allDayStart.hour, 0);
    expect(allDayReminder.hour, 9);
    expect(
      (allDayReminder.year, allDayReminder.month, allDayReminder.day),
      (allDayStart.year, allDayStart.month, allDayStart.day),
    );

    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Задача с интервалом',
    );
    await tester.tap(find.text('На весь день'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Напомнить в приложении'));
    await tester.pumpAndSettle();
    expect(find.text('Окончание'), findsOneWidget);
    expect(find.byKey(const Key('shared-task-reminder-at')), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Создать'));
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    final interval = Map<String, dynamic>.from(source.lastCreateData!);
    final intervalStart = DateTime.parse(
      interval['startAt'].toString(),
    ).toLocal();
    final intervalEnd = DateTime.parse(interval['endAt'].toString()).toLocal();
    final intervalReminder = DateTime.parse(
      ((interval['reminders'] as List).single as Map)['dueAt'].toString(),
    ).toLocal();
    expect(interval['allDay'], isFalse);
    expect(intervalEnd.difference(intervalStart), const Duration(hours: 1));
    expect(
      intervalStart.difference(intervalReminder),
      const Duration(hours: 1),
    );
  });

  testWidgets('invalid interval is visible and cannot be submitted', (
    tester,
  ) async {
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: SharedTaskEditor(
            dataSource: source,
            task: {
              'id': '11111111-1111-4111-8111-111111111111',
              'title': 'Некорректный интервал',
              'allDay': false,
              'startAt': '2026-08-14T11:00:00.000Z',
              'endAt': '2026-08-14T10:00:00.000Z',
              'priority': 'medium',
              'version': 1,
              'audiences': [
                {'type': 'allBranches'},
              ],
            },
            audienceOptions: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shared-task-interval-error')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('recipient preview distinguishes people, branch and school', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = FakeSharedTasksDataSource();
    await tester.pumpWidget(_host(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Новая задача'));
    await tester.pumpAndSettle();
    expect(find.text('Сейчас получат: 8'), findsOneWidget);
    expect(
      find.textContaining('Вся школа: динамический состав'),
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
    expect(find.textContaining('Анна Петрова: лично'), findsOneWidget);
    expect(find.textContaining('Вся школа: динамический состав'), findsNothing);

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
      find.textContaining('Центральный: динамический состав'),
      findsOneWidget,
    );

    await tester.tap(find.text('Вся школа').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить получателя'));
    await tester.pumpAndSettle();
    expect(find.text('Сейчас получат: 8'), findsOneWidget);
    expect(find.textContaining('Анна Петрова: лично'), findsNothing);
    expect(
      find.textContaining('Центральный: динамический состав'),
      findsNothing,
    );
  });

  testWidgets('failed recipient preview blocks submit until retry succeeds', (
    tester,
  ) async {
    final source = FakeSharedTasksDataSource()..failAudiencePreview = true;
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
    final source = FakeSharedTasksDataSource();
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

  testWidgets('repump synchronizes focused and linked task scope', (
    tester,
  ) async {
    final source = SwitchingSharedTasksDataSource();
    EntityLink taskLink(String id) =>
        EntityLink.typed(entityType: EntityLinkType.task, entityId: id);
    EntityLink studentLink(String id) => EntityLink.typed(
      entityType: EntityLinkType.client,
      entityId: id,
      variant: 'student',
    );

    await tester.pumpWidget(
      _host(
        source,
        initialLink: taskLink('task-old'),
        linkedEntity: studentLink('student-old'),
      ),
    );
    await tester.pump();
    expect(source.taskIds, ['task-old']);

    await tester.pumpWidget(
      _host(
        source,
        initialLink: taskLink('task-new'),
        linkedEntity: studentLink('student-new'),
      ),
    );
    await tester.pump();
    expect(source.taskIds, ['task-old', 'task-new']);
    expect(source.linkedIds, ['student-old', 'student-new']);

    source.responses.first.complete({
      'items': [
        {...source.task, 'id': 'task-old', 'title': 'Старая задача'},
      ],
    });
    await tester.pump();
    expect(find.text('Старая задача'), findsNothing);

    source.responses.last.complete({
      'items': [
        {...source.task, 'id': 'task-new', 'title': 'Новая связанная задача'},
      ],
    });
    await tester.pumpAndSettle();

    expect(find.text('Старая задача'), findsNothing);
    expect(find.text('Новая связанная задача'), findsWidgets);
    expect(find.text('История'), findsOneWidget);
  });
}
