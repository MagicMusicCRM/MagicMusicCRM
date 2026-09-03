import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

class RecordingSharedTasksDataSource extends SharedTasksDataSource {
  int createCalls = 0;
  int updateCalls = 0;
  int failuresRemaining = 0;
  bool failPreview = false;
  Map<String, dynamic>? lastPayload;
  String? updatedTaskId;
  Completer<Map<String, dynamic>>? pendingMutation;
  final List<MagicMutationIdentity> identities = [];
  final List<Map<String, dynamic>> payloads = [];

  @override
  Future<List<SharedTaskAudienceOption>> audienceOptions() async => const [
    SharedTaskAudienceOption(type: 'user', id: 'user-1', label: 'Анна'),
  ];

  @override
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  ) async {
    if (failPreview) throw StateError('preview unavailable');
    return {
      'totalRecipients': audiences.single['type'] == 'user' ? 1 : 4,
      'hasDynamicMembership': audiences.single['type'] != 'user',
      'selectors': audiences
          .map(
            (audience) => {
              ...audience,
              'label': audience['type'] == 'user' ? 'Анна' : 'Вся школа',
              'mode': audience['type'] == 'user' ? 'fixed' : 'dynamic',
              'currentRecipientCount': audience['type'] == 'user' ? 1 : 4,
            },
          )
          .toList(),
      'recipients': const <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _record(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) async {
    identities.add(identity);
    lastPayload = Map<String, dynamic>.from(data);
    payloads.add(Map<String, dynamic>.from(data));
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('offline');
    }
    final pending = pendingMutation;
    if (pending != null) return pending.future;
    return {
      ...data,
      'recipientSummary': {'totalRecipients': 4},
    };
  }

  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    createCalls++;
    return _record(data, identity);
  }

  @override
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  ) {
    updateCalls++;
    updatedTaskId = taskId;
    return _record(data, identity);
  }

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

class _WrapperApiClient extends MagicApiClient {
  _WrapperApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  int createCalls = 0;
  Map<String, dynamic>? createPayload;
  MagicMutationIdentity? createIdentity;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/admin/profiles' || path == '/crm/branches') {
      return {'items': <Map<String, dynamic>>[]} as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/shared-tasks/audience-preview') {
      return {
            'totalRecipients': 4,
            'hasDynamicMembership': true,
            'selectors': const [
              {
                'type': 'allBranches',
                'label': 'Вся школа',
                'mode': 'dynamic',
                'currentRecipientCount': 4,
              },
            ],
            'recipients': const <Map<String, dynamic>>[],
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<T> postIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path != '/crm/shared-tasks') {
      throw StateError('Unexpected idempotent POST $path');
    }
    createCalls++;
    createPayload = Map<String, dynamic>.from(data! as Map);
    createIdentity = identity;
    return {
          'recipientSummary': {'totalRecipients': 4},
        }
        as T;
  }
}

class _ShowCreateSharedTaskLauncher extends ConsumerWidget {
  const _ShowCreateSharedTaskLauncher({required this.onSaved});

  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: FilledButton(
        onPressed: () => showCreateSharedTask(context, ref, onSaved: onSaved),
        child: const Text('Открыть через WidgetRef'),
      ),
    );
  }
}

class EditorLifecycleProbe {
  int completions = 0;
  bool? result;
}

Widget _launcher({
  required RecordingSharedTasksDataSource source,
  Map<String, dynamic>? task,
  EntityLink? linkedEntity,
  VoidCallback? onSaved,
  EditorLifecycleProbe? lifecycle,
}) {
  return MaterialApp(
    theme: ThemeData(platform: TargetPlatform.windows),
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            final result = await showSharedTaskEditor(
              context,
              dataSource: source,
              task: task,
              linkedEntity: linkedEntity,
              onSaved: onSaved,
            );
            if (lifecycle != null) {
              lifecycle.result = result;
              lifecycle.completions++;
            }
          },
          child: const Text('Открыть редактор'),
        ),
      ),
    ),
  );
}

Future<void> _openEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pump();
  await tester.tap(find.text('Открыть редактор'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('magic-dialog-desktop')), findsOneWidget);
  expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsNothing);
}

typedef _DraftCallbacks = ({
  VoidCallback cancel,
  ValueChanged<String?> priority,
  ValueChanged<Set<String>> audienceType,
  ValueChanged<String?> audienceTarget,
});

DropdownButtonFormField<String> _dropdown(WidgetTester tester, Key key) =>
    tester.widget<DropdownButtonFormField<String>>(find.byKey(key));

SegmentedButton<String> _audienceTypeControl(WidgetTester tester) => tester
    .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));

_DraftCallbacks _draftCallbacks(WidgetTester tester) => (
  cancel: tester
      .widget<TextButton>(find.widgetWithText(TextButton, 'Отмена'))
      .onPressed!,
  priority: _dropdown(tester, const Key('shared-task-priority')).onChanged!,
  audienceType: _audienceTypeControl(tester).onSelectionChanged!,
  audienceTarget: _dropdown(
    tester,
    const Key('shared-task-audience-target'),
  ).onChanged!,
);

Future<void> _selectUserAudience(WidgetTester tester) async {
  await tester.tap(find.text('Сотрудники'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('shared-task-audience-target')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Анна').last);
  await tester.pumpAndSettle();
}

Map<String, dynamic> _updateTask() => {
  'id': 'task-7',
  'title': 'Исходный заголовок',
  'body': 'Исходное описание',
  'allDay': false,
  'startAt': '2026-08-25T10:00:00.000Z',
  'endAt': '2026-08-25T12:00:00.000Z',
  'priority': 'high',
  'version': 7,
  'hasReminder': true,
  'reminders': [
    {'dueAt': '2026-08-25T08:30:00.000Z', 'channel': 'in_app'},
  ],
  'audiences': [
    {'type': 'allBranches'},
  ],
};

Map<String, dynamic> _taskWithReminders(List<Map<String, dynamic>> reminders) =>
    {
      ..._updateTask(),
      'hasReminder': reminders.isNotEmpty,
      'reminders': reminders,
    };

void main() {
  testWidgets('failed update keeps draft and reuses mutation identity', (
    tester,
  ) async {
    final source = RecordingSharedTasksDataSource()..failuresRemaining = 1;
    var saved = 0;
    await tester.pumpWidget(
      _launcher(source: source, task: _updateTask(), onSaved: () => saved++),
    );
    await _openEditor(tester);
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Изменённый заголовок',
    );
    await tester.enterText(find.byType(TextField).at(1), 'Изменённое описание');

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Изменённый заголовок'), findsOneWidget);
    expect(find.text('Изменённое описание'), findsOneWidget);
    expect(find.textContaining('Не удалось сохранить задачу'), findsOneWidget);
    expect(source.lastPayload?['expectedVersion'], 7);
    expect(source.updatedTaskId, 'task-7');
    expect(source.identities.single.idempotencyKey, isNotEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(source.updateCalls, 2);
    expect(source.identities[1], same(source.identities[0]));
    expect(saved, 1);
    expect(find.text('Открыть редактор'), findsOneWidget);
    final payload = source.lastPayload!;
    expect(payload['allDay'], isFalse);
    expect(payload['endAt'], isNotNull);
    expect((payload['reminders'] as List).single, {
      'dueAt': '2026-08-25T08:30:00.000Z',
      'channel': 'in_app',
    });
  });

  testWidgets(
    'create sends audience reminder and linked entity then closes once',
    (tester) async {
      final source = RecordingSharedTasksDataSource();
      var saved = 0;
      await tester.pumpWidget(
        _launcher(
          source: source,
          linkedEntity: EntityLink.typed(
            entityType: EntityLinkType.client,
            entityId: 'student-1',
            variant: 'student',
          ),
          onSaved: () => saved++,
        ),
      );
      await _openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('shared-task-title')),
        'Позвонить ученику',
      );
      await tester.tap(find.text('Сотрудники'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shared-task-audience-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Анна').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить получателя'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Напомнить в приложении'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
      await tester.pumpAndSettle();

      expect(source.createCalls, 1);
      expect(saved, 1);
      expect(
        source.identities.single.idempotencyKey,
        contains('shared-task-create'),
      );
      final payload = source.lastPayload!;
      expect(payload['allDay'], isTrue);
      expect(payload.containsKey('endAt'), isFalse);
      expect(payload['audiences'], [
        {'type': 'user', 'targetId': 'user-1'},
      ]);
      expect(payload['linkedEntity'], {'type': 'student', 'id': 'student-1'});
      final start = DateTime.parse(payload['startAt'].toString()).toLocal();
      final reminder = DateTime.parse(
        ((payload['reminders'] as List).single as Map)['dueAt'].toString(),
      ).toLocal();
      expect(reminder.hour, 9);
      expect(
        (reminder.year, reminder.month, reminder.day),
        (start.year, start.month, start.day),
      );
      expect(find.text('Открыть редактор'), findsOneWidget);
    },
  );

  testWidgets('validation and preview failure block mutation until retry', (
    tester,
  ) async {
    final source = RecordingSharedTasksDataSource()..failPreview = true;
    await tester.pumpWidget(_launcher(source: source));
    await _openEditor(tester);

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать'))
          .onPressed,
      isNull,
    );
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
    expect(source.createCalls, 0);

    source.failPreview = false;
    await tester.tap(find.text('Повторить расчёт'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('cancel performs no mutation', (tester) async {
    final source = RecordingSharedTasksDataSource();
    await tester.pumpWidget(_launcher(source: source));
    await _openEditor(tester);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(source.createCalls, 0);
    expect(source.updateCalls, 0);
    expect(source.identities, isEmpty);
  });

  testWidgets('editing draft after failure rotates mutation identity', (
    tester,
  ) async {
    final source = RecordingSharedTasksDataSource()..failuresRemaining = 1;
    await tester.pumpWidget(_launcher(source: source, task: _updateTask()));
    await _openEditor(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Новый payload после ошибки',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(source.updateCalls, 2);
    expect(source.payloads[0]['title'], 'Исходный заголовок');
    expect(source.payloads[1]['title'], 'Новый payload после ошибки');
    expect(
      source.identities[1].idempotencyKey,
      isNot(source.identities[0].idempotencyKey),
    );
  });

  testWidgets('throwing onSaved cannot make successful mutation retryable', (
    tester,
  ) async {
    final source = RecordingSharedTasksDataSource();
    final lifecycle = EditorLifecycleProbe();
    var callbackAttempts = 0;
    await tester.pumpWidget(
      _launcher(
        source: source,
        lifecycle: lifecycle,
        onSaved: () {
          callbackAttempts++;
          throw StateError('consumer failed');
        },
      ),
    );
    await _openEditor(tester);
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Успешная команда',
    );
    await tester.pump();

    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать'))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(source.createCalls, 1);
    expect(callbackAttempts, 1);
    expect(lifecycle.completions, 1);
    expect(lifecycle.result, isTrue);
    expect(find.byKey(const Key('shared-task-save-error')), findsNothing);
    expect(find.text('Открыть редактор'), findsOneWidget);
  });

  testWidgets('pending double submit runs one mutation and one completion', (
    tester,
  ) async {
    final source = RecordingSharedTasksDataSource();
    final pending = Completer<Map<String, dynamic>>();
    source.pendingMutation = pending;
    final lifecycle = EditorLifecycleProbe();
    var saved = 0;
    await tester.pumpWidget(
      _launcher(source: source, lifecycle: lifecycle, onSaved: () => saved++),
    );
    await _openEditor(tester);
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Один запрос',
    );
    await tester.pump();

    final submit = find.widgetWithText(FilledButton, 'Создать');
    final onPressed = tester.widget<FilledButton>(submit).onPressed!;
    onPressed();
    onPressed();
    expect(source.createCalls, 1);
    pending.complete({
      'recipientSummary': {'totalRecipients': 4},
    });
    await tester.pumpAndSettle();

    expect(source.createCalls, 1);
    expect(saved, 1);
    expect(lifecycle.completions, 1);
    expect(lifecycle.result, isTrue);
  });

  testWidgets('email and push reminders survive an untouched title edit', (
    tester,
  ) async {
    final reminders = <Map<String, dynamic>>[
      {'dueAt': '2026-08-25T07:00:00.000Z', 'channel': 'email'},
      {'dueAt': '2026-08-25T07:30:00.000Z', 'channel': 'push'},
    ];
    final source = RecordingSharedTasksDataSource();
    await tester.pumpWidget(
      _launcher(source: source, task: _taskWithReminders(reminders)),
    );
    await _openEditor(tester);

    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Напомнить в приложении'),
          )
          .value,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Только заголовок',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(source.lastPayload?['reminders'], reminders);
  });

  testWidgets('enabling in-app preserves email and push reminders', (
    tester,
  ) async {
    final reminders = <Map<String, dynamic>>[
      {'dueAt': '2026-08-25T07:00:00.000Z', 'channel': 'email'},
      {'dueAt': '2026-08-25T07:30:00.000Z', 'channel': 'push'},
    ];
    final source = RecordingSharedTasksDataSource();
    await tester.pumpWidget(
      _launcher(source: source, task: _taskWithReminders(reminders)),
    );
    await _openEditor(tester);

    await tester.tap(find.text('Напомнить в приложении'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    final payload = (source.lastPayload?['reminders'] as List)
        .whereType<Map<String, dynamic>>()
        .toList();
    expect(
      payload.where((item) => item['channel'] == 'email'),
      reminders.take(1),
    );
    expect(payload.where((item) => item['channel'] == 'push'), [reminders[1]]);
    expect(payload.where((item) => item['channel'] == 'in_app'), hasLength(1));
  });

  testWidgets('disabling in-app removes only that reminder channel', (
    tester,
  ) async {
    final reminders = <Map<String, dynamic>>[
      {'dueAt': '2026-08-25T07:00:00.000Z', 'channel': 'email'},
      {'dueAt': '2026-08-25T07:30:00.000Z', 'channel': 'push'},
      {'dueAt': '2026-08-25T08:30:00.000Z', 'channel': 'in_app'},
    ];
    final source = RecordingSharedTasksDataSource();
    await tester.pumpWidget(
      _launcher(source: source, task: _taskWithReminders(reminders)),
    );
    await _openEditor(tester);

    await tester.tap(find.text('Напомнить в приложении'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(source.lastPayload?['reminders'], reminders.take(2).toList());
  });

  testWidgets('pending mutation freezes draft and failure restores editing', (
    tester,
  ) async {
    final source = RecordingSharedTasksDataSource();
    final firstPending = Completer<Map<String, dynamic>>();
    source.pendingMutation = firstPending;
    await tester.pumpWidget(_launcher(source: source, task: _updateTask()));
    await _openEditor(tester);
    final title = find.byKey(const Key('shared-task-title'));
    await tester.enterText(title, 'Черновик до запроса');
    await tester.pump();

    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
        .onPressed!();
    await tester.pump();
    expect(source.updateCalls, 1);
    expect(tester.widget<TextField>(title).readOnly, isTrue);

    await tester.tap(title, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.tap(find.text('Напомнить в приложении'), warnIfMissed: false);
    await tester.tap(find.text('Сотрудники'), warnIfMissed: false);
    await tester.pump();

    expect(
      tester.widget<TextField>(title).controller?.text,
      'Черновик до запроса',
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Напомнить в приложении'),
          )
          .value,
      isTrue,
    );
    expect(source.payloads.single['title'], 'Черновик до запроса');

    source.pendingMutation = null;
    firstPending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-task-save-error')), findsOneWidget);
    expect(tester.widget<TextField>(title).readOnly, isFalse);

    await tester.enterText(title, 'Разрешено после ошибки');
    await tester.tap(find.text('Напомнить в приложении'));
    await tester.pump();
    expect(
      tester.widget<TextField>(title).controller?.text,
      'Разрешено после ошибки',
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Напомнить в приложении'),
          )
          .value,
      isFalse,
    );

    final secondPending = Completer<Map<String, dynamic>>();
    source.pendingMutation = secondPending;
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
        .onPressed!();
    await tester.pump();
    await tester.tap(title, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.tap(find.text('Напомнить в приложении'), warnIfMissed: false);
    await tester.pump();

    expect(
      tester.widget<TextField>(title).controller?.text,
      'Разрешено после ошибки',
    );
    expect(source.payloads.last['title'], 'Разрешено после ошибки');
    expect(source.payloads.last['reminders'], isEmpty);

    secondPending.complete({
      'recipientSummary': {'totalRecipients': 4},
    });
    await tester.pumpAndSettle();
    expect(source.updateCalls, 2);
    expect(find.text('Открыть редактор'), findsOneWidget);
  });

  testWidgets('stale callbacks stay frozen and fresh callbacks recover', (
    tester,
  ) async {
    final source = RecordingSharedTasksDataSource();
    final pending = Completer<Map<String, dynamic>>();
    source.pendingMutation = pending;
    var saved = 0;
    await tester.pumpWidget(
      _launcher(source: source, task: _updateTask(), onSaved: () => saved++),
    );
    await _openEditor(tester);
    await _selectUserAudience(tester);
    final stale = _draftCallbacks(tester);

    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
        .onPressed!();
    stale.priority('low');
    stale.audienceType({'allBranches'});
    stale.audienceTarget(null);
    stale.cancel();
    await tester.pump();

    expect(find.byType(SharedTaskEditor), findsOneWidget);
    expect(source.updateCalls, 1);
    expect(saved, 0);
    expect(source.payloads.single['priority'], 'high');
    expect(source.payloads.single['audiences'], [
      {'type': 'allBranches'},
    ]);
    expect(
      _dropdown(tester, const Key('shared-task-priority')).initialValue,
      'high',
    );
    expect(_audienceTypeControl(tester).selected, {'user'});
    expect(
      _dropdown(tester, const Key('shared-task-audience-target')).initialValue,
      'user-1',
    );

    pending.complete({
      'recipientSummary': {'totalRecipients': 4},
    });
    await tester.pumpAndSettle();
    expect(source.updateCalls, 1);
    expect(saved, 1);
    expect(find.text('Открыть редактор'), findsOneWidget);

    final failingSource = RecordingSharedTasksDataSource();
    final failingPending = Completer<Map<String, dynamic>>();
    failingSource.pendingMutation = failingPending;
    var failedSaved = 0;
    await tester.pumpWidget(
      _launcher(
        source: failingSource,
        task: _updateTask(),
        onSaved: () => failedSaved++,
      ),
    );
    await _openEditor(tester);
    await _selectUserAudience(tester);
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'))
        .onPressed!();
    await tester.pump();

    failingPending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-task-save-error')), findsOneWidget);

    final current = _draftCallbacks(tester);
    current.priority('low');
    current.audienceTarget(null);
    current.audienceType({'allBranches'});
    await tester.pump();

    expect(
      _dropdown(tester, const Key('shared-task-priority')).initialValue,
      'low',
    );
    expect(_audienceTypeControl(tester).selected, {'allBranches'});
    expect(find.byKey(const Key('shared-task-audience-target')), findsNothing);

    current.cancel();
    await tester.pumpAndSettle();
    expect(failingSource.updateCalls, 1);
    expect(failedSaved, 0);
    expect(find.text('Открыть редактор'), findsOneWidget);
  });

  testWidgets('showCreateSharedTask uses providers and canonical mutation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _WrapperApiClient();
    var saved = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: _ShowCreateSharedTaskLauncher(onSaved: () => saved++),
        ),
      ),
    );

    await tester.tap(find.text('Открыть через WidgetRef'));
    await tester.pumpAndSettle();
    expect(find.byType(SharedTaskEditor), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('shared-task-title')),
      'Через provider seam',
    );
    await tester.pump();
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать'))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.createPayload?['title'], 'Через provider seam');
    expect(api.createIdentity?.idempotencyKey, contains('shared-task-create'));
    expect(saved, 1);
    expect(find.text('Открыть через WidgetRef'), findsOneWidget);
  });
}
