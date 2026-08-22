import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/widgets/magic_shimmer.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_details.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_view.dart';

const _taskId = '11111111-1111-4111-8111-111111111111';
const _clientId = '44444444-4444-4444-8444-444444444444';

Map<String, dynamic> _task({String state = 'open'}) => {
  'id': _taskId,
  'title': 'Подготовить отчёт',
  'body': 'Сверить данные',
  'state': state,
  'priority': 'high',
  'startAt': '2026-08-22T09:00:00.000Z',
  'allDay': false,
  'hasReminder': true,
  'version': 3,
  'linkedEntity': {'type': 'student', 'id': _clientId},
};

SharedTasksState _state({
  SharedTasksQuery query = const SharedTasksQuery(),
  SharedTasksQuery? successfulQuery,
  List<Map<String, dynamic>>? items,
  bool loading = false,
  bool hasLoaded = true,
  Object? error,
  Set<String> closing = const {},
  Map<String, Object> closeErrors = const {},
  Map<String, int> calendar = const {},
}) => SharedTasksState(
  query: query,
  appliedQuery: query,
  successfulQuery: successfulQuery ?? query,
  items: items ?? [_task()],
  counters: const {'open': 1, 'overdue': 2},
  calendar: calendar,
  loading: loading,
  hasLoaded: hasLoaded,
  error: error,
  closing: closing,
  closeErrors: closeErrors,
);

Widget _detailsHost({
  required Future<List<Map<String, dynamic>>> history,
  ValueChanged<EntityLink>? onOpen,
}) => MaterialApp(
  home: Scaffold(
    body: SharedTaskDetails(
      task: _task(),
      history: history,
      onOpenEntity: onOpen ?? (_) {},
    ),
  ),
);

Widget _viewHost(
  SharedTasksState state, {
  Size size = const Size(1000, 900),
  ValueChanged<SharedTasksQuery>? onQuery,
  ValueChanged<SharedTasksQuery>? onDraft,
  SharedTaskCallback? onOpen,
  SharedTaskCallback? onClose,
  SharedTaskCallback? onEdit,
  VoidCallback? onCreate,
  VoidCallback? onAdvancedFilters,
  VoidCallback? onRetry,
  bool canCreate = true,
  bool canEdit = true,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: Scaffold(
      body: SharedTasksView(
        state: state,
        onQueryChanged: onQuery ?? (_) {},
        onSearchDraftChanged: onDraft ?? (_) {},
        onOpen: onOpen ?? (_) {},
        onClose: onClose ?? (_) {},
        onEdit: onEdit ?? (_) {},
        onCreate: onCreate ?? () {},
        onAdvancedFilters: onAdvancedFilters ?? () {},
        onRetry: onRetry ?? () {},
        onRefresh: () async {},
        canCreate: canCreate,
        canEdit: canEdit,
        embedded: true,
      ),
    ),
  ),
);

void main() {
  group('SharedTaskDetails', () {
    testWidgets('returns the canonical typed linked entity', (tester) async {
      EntityLink? opened;
      await tester.pumpWidget(
        _detailsHost(
          history: Future.value(const []),
          onOpen: (link) => opened = link,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shared-task-linked-entity')));
      expect(opened?.rawEntityType, 'student');
      expect(opened?.entityId, _clientId);
    });

    testWidgets('renders history loading, error and empty states', (
      tester,
    ) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      await tester.pumpWidget(_detailsHost(history: pending.future));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      final failed = Completer<List<Map<String, dynamic>>>();
      await tester.pumpWidget(_detailsHost(history: failed.future));
      failed.completeError('offline');
      await tester.pump();
      expect(find.text('Не удалось загрузить историю задачи.'), findsOneWidget);

      await tester.pumpWidget(_detailsHost(history: Future.value(const [])));
      await tester.pumpAndSettle();
      expect(find.text('Изменений пока нет.'), findsOneWidget);
    });

    testWidgets('maps created, updated, closed and legacy actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _detailsHost(
          history: Future.value([
            {'action': 'workflow.shared_task_created'},
            {'action': 'workflow.shared_task_updated'},
            {'action': 'workflow.shared_task_closed'},
            {'action': 'workflow.shared_task_legacy_imported'},
          ]),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in [
        'Задача создана',
        'Задача изменена',
        'Задача закрыта',
        'Историческое изменение',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('SharedTasksView', () {
    testWidgets('renders initial loading and retryable initial error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _viewHost(
          const SharedTasksState(loading: true),
          canCreate: false,
          canEdit: false,
        ),
      );
      expect(find.byType(SkeletonBox), findsNWidgets(3));

      var retried = false;
      await tester.pumpWidget(
        _viewHost(
          SharedTasksState(error: StateError('offline')),
          onRetry: () => retried = true,
          canCreate: false,
          canEdit: false,
        ),
      );
      await tester.pump();
      expect(find.text('Не удалось загрузить задачи'), findsOneWidget);
      await tester.tap(find.text('Повторить'));
      expect(retried, isTrue);
    });

    testWidgets('keeps retained content during changed-query error and retry', (
      tester,
    ) async {
      const previous = SharedTasksQuery(state: 'open');
      const next = SharedTasksQuery(state: 'closed');
      var retried = false;
      await tester.pumpWidget(
        _viewHost(
          SharedTasksState(
            query: next,
            appliedQuery: next,
            successfulQuery: previous,
            items: [_task()],
            counters: const {'open': 1, 'overdue': 0},
            hasLoaded: true,
            error: StateError('offline'),
          ),
          onRetry: () => retried = true,
        ),
      );

      expect(find.text('Подготовить отчёт'), findsOneWidget);
      expect(find.textContaining('предыдущего запроса'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Повторить'));
      expect(retried, isTrue);

      await tester.pumpWidget(
        _viewHost(
          SharedTasksState(
            query: next,
            appliedQuery: next,
            successfulQuery: previous,
            items: [_task()],
            counters: const {'open': 1, 'overdue': 0},
            loading: true,
            hasLoaded: true,
          ),
        ),
      );
      expect(find.textContaining('Загружаем выбранный'), findsOneWidget);
    });

    testWidgets('renders empty, list, calendar and overdue banner', (
      tester,
    ) async {
      await tester.pumpWidget(_viewHost(_state(items: const [])));
      expect(find.text('Нет задач'), findsOneWidget);

      await tester.pumpWidget(_viewHost(_state()));
      expect(find.text('Подготовить отчёт'), findsOneWidget);
      expect(
        find.byKey(const Key('shared-task-reminder-panel')),
        findsOneWidget,
      );

      final month = DateTime(2026, 8);
      await tester.pumpWidget(
        _viewHost(
          _state(
            query: SharedTasksQuery(calendarMode: true, calendarMonth: month),
            calendar: const {'2026-08-22': 3},
          ),
        ),
      );
      expect(find.byKey(const Key('shared-task-month-grid')), findsOneWidget);
      expect(
        find.byKey(const Key('shared-task-count-2026-08-22')),
        findsOneWidget,
      );
    });

    testWidgets('renders closing, close error, closed and capabilities', (
      tester,
    ) async {
      var creates = 0;
      await tester.pumpWidget(
        _viewHost(_state(closing: const {_taskId}), onCreate: () => creates++),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Изменить'), findsOneWidget);
      await tester.tap(find.byTooltip('Новая задача'));
      expect(creates, 1);

      await tester.pumpWidget(
        _viewHost(
          _state(closeErrors: {_taskId: StateError('failed')}),
          canCreate: false,
          canEdit: false,
        ),
      );
      expect(find.text('Повторить закрытие'), findsOneWidget);
      expect(find.byTooltip('Изменить'), findsNothing);
      expect(find.byTooltip('Новая задача'), findsNothing);

      await tester.pumpWidget(
        _viewHost(_state(items: [_task(state: 'closed')])),
      );
      expect(find.text('Закрыта'), findsOneWidget);
      expect(find.text('Закрыть задачу'), findsNothing);
    });

    testWidgets(
      'emits filter, search, priority, scope, day and calendar queries',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final queries = <SharedTasksQuery>[];
        final drafts = <SharedTasksQuery>[];
        await tester.pumpWidget(
          _viewHost(_state(), onQuery: queries.add, onDraft: drafts.add),
        );

        await tester.enterText(
          find.byKey(const Key('shared-task-search')),
          'сводка',
        );
        expect(drafts.last.search, 'сводка');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        expect(queries.last.search, 'сводка');

        tester
            .widget<DropdownButton<String>>(
              find.byKey(const Key('shared-task-priority-filter')),
            )
            .onChanged!('high');
        expect(queries.last.priority, 'high');

        tester
            .widget<DropdownButton<String>>(
              find.byKey(const Key('shared-task-scope-filter')),
            )
            .onChanged!('branch');
        expect(queries.last.scope, 'branch');

        tester
            .widget<ChoiceChip>(
              find.byKey(const Key('shared-task-today-filter')),
            )
            .onSelected!(true);
        expect(queries.last.day, isNotNull);

        tester
            .widget<IconButton>(
              find.byKey(const Key('shared-task-calendar-toggle')),
            )
            .onPressed!();
        expect(queries.last.calendarMode, isTrue);

        final closedChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Закрытые'),
        );
        closedChip.onSelected!(true);
        expect(queries.last.state, 'closed');
      },
    );

    testWidgets(
      'calendar emits month and day and mobile/desktop keys are stable',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final queries = <SharedTasksQuery>[];
        final month = DateTime(2026, 8);
        await tester.pumpWidget(
          _viewHost(
            _state(
              query: SharedTasksQuery(calendarMode: true, calendarMonth: month),
            ),
            onQuery: queries.add,
          ),
        );
        expect(
          find.byKey(const Key('shared-task-desktop-filter')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Следующий месяц'));
        expect(queries.last.calendarMonth, DateTime(2026, 9));
        await tester.tap(find.byKey(const Key('shared-task-day-2026-08-22')));
        expect(queries.last.day, DateTime(2026, 8, 22));

        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpWidget(
          _viewHost(_state(), size: const Size(390, 800)),
        );
        expect(
          find.byKey(const Key('shared-task-mobile-filter')),
          findsOneWidget,
        );
      },
    );
  });
}
