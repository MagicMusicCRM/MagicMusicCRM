import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/tasks_widget.dart';

/// The tasks calendar (год / месяц / день). Opens on «День» = today, a month
/// grid shows a per-day count from /crm/tasks/calendar, and tapping a day opens
/// that day's list.
class _FakeApiClient extends MagicApiClient {
  _FakeApiClient({this.tasks = const []})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<String> calendarCalls = [];
  final List<Map<String, dynamic>> tasks;
  String? taskEntityId;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/tasks/calendar') {
      calendarCalls.add(queryParameters?['from']?.toString() ?? '');
      // Day 01 sits in the top row of the grid whatever weekday the month
      // starts on, so the badge is always laid out (never below the fold).
      final now = DateTime.now();
      final key =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-01';
      // 99 can never collide with a day number (1–31), so the badge is a
      // stable, date-independent finder.
      return <String, dynamic>{
            'items': [
              {'day': key, 'count': 99},
            ],
          }
          as T;
    }
    if (path == '/crm/tasks') {
      taskEntityId = queryParameters?['entityId']?.toString();
      return <String, dynamic>{'items': tasks} as T;
    }
    // Every other GET (tasks list, branches, profiles) → empty.
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }
}

Widget _host(_FakeApiClient client, {EntityLink? initialLink}) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(client)],
    child: MaterialApp(home: TasksWidget(initialLink: initialLink)),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('opens on the day view, with Год/Месяц/День switch', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeApiClient()));
    await tester.pumpAndSettle();

    expect(find.text('Год'), findsOneWidget);
    expect(find.text('Месяц'), findsOneWidget);
    expect(find.text('День'), findsWidgets);
    // Day view by default → the empty day list, not a calendar grid.
    expect(find.text('Нет задач'), findsOneWidget);
  });

  testWidgets('month view fetches per-day counts and renders the badge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = _FakeApiClient();
    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();

    // Hit the calendar endpoint, and the weekday header proves the grid is up.
    expect(client.calendarCalls, isNotEmpty);
    expect(find.text('Пн'), findsOneWidget);
    expect(find.text('Вс'), findsOneWidget);
    // The count badge from the endpoint.
    expect(find.text('99'), findsOneWidget);
  });

  testWidgets('tapping a day in the month grid returns to the day list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = _FakeApiClient();
    await tester.pumpWidget(_host(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Месяц'));
    await tester.pumpAndSettle();

    // Tap the badged cell (the 15th, where the fake put the count).
    await tester.tap(find.text('99'));
    await tester.pumpAndSettle();

    // Back on the day list (empty in this fake), grid gone.
    expect(find.text('Пн'), findsNothing);
    expect(find.text('Нет задач'), findsOneWidget);
  });

  testWidgets('typed task link opens the exact task and scopes its request', (
    tester,
  ) async {
    final client = _FakeApiClient(
      tasks: const [
        {
          'id': 'task-42',
          'title': 'Позвонить ученику',
          'entityType': 'student',
          'entityId': 'student-7',
          'status': 'open',
        },
      ],
    );
    await tester.pumpWidget(
      _host(
        client,
        initialLink: EntityLink.typed(
          entityType: EntityLinkType.task,
          entityId: 'task-42',
          optionalFocus: EntityLinkFocus(
            filter: {
              'taskId': 'task-42',
              'entityType': 'student',
              'entityId': 'student-7',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(client.taskEntityId, 'student-7');
    expect(find.text('Позвонить ученику'), findsWidgets);
    expect(find.text('Задача'), findsOneWidget);
    expect(find.text('Объект'), findsWidgets);
  });
}
