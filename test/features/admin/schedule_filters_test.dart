import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

/// Schedule lesson filters (пробные / конфликты / педагог) and the removal of
/// the duplicate «Сегодня» in the month view.

const _branchId = '11111111-1111-1111-1111-111111111111';
const _roomId = '22222222-2222-2222-2222-222222222222';
const _secondBranchId = '33333333-3333-3333-3333-333333333333';
const _secondRoomId = '44444444-4444-4444-4444-444444444444';

DateTime _today() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day, 10);
}

class _FakeScheduleApiClient extends MagicApiClient {
  _FakeScheduleApiClient({this.multipleBranches = false})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool multipleBranches;
  final List<Map<String, dynamic>> matrixQueries = [];
  final List<Map<String, dynamic>> availabilityQueries = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final iso = _today().toIso8601String();
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {
                'id': _branchId,
                'name': 'Главный филиал',
                'utcOffsetMinutes': 180,
              },
              if (multipleBranches)
                {
                  'id': _secondBranchId,
                  'name': 'Второй филиал',
                  'utcOffsetMinutes': -300,
                },
            ],
          }
          as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{
            'items': [
              {'id': _roomId, 'branchId': _branchId, 'name': 'Кабинет 1'},
              if (multipleBranches)
                {
                  'id': _secondRoomId,
                  'branchId': _secondBranchId,
                  'name': 'Кабинет 2',
                },
            ],
          }
          as T;
    }
    if (path == '/crm/schedule/matrix') {
      final query = Map<String, dynamic>.from(queryParameters ?? const {});
      matrixQueries.add(query);
      final requestedBranchId = query['branchId']?.toString();
      final lessons =
          [
            {
              'id': 'lesson-normal',
              'studentId': 'student-a',
              'studentName': 'Анна Обычная',
              'teacherId': 'teacher-a',
              'teacherName': 'Педагог А',
              'branchId': _branchId,
              'roomId': _roomId,
              'roomName': 'Кабинет 1',
              'scheduledAt': iso,
              'durationMinutes': 60,
              'status': 'scheduled',
              'isTrial': false,
            },
            {
              'id': 'lesson-trial',
              'studentId': 'student-b',
              'studentName': 'Борис Пробный',
              'teacherId': 'teacher-b',
              'teacherName': 'Педагог Б',
              'branchId': multipleBranches ? _secondBranchId : _branchId,
              'roomId': multipleBranches ? _secondRoomId : _roomId,
              'roomName': multipleBranches ? 'Кабинет 2' : 'Кабинет 1',
              'scheduledAt': iso,
              'durationMinutes': 60,
              'status': 'scheduled',
              'isTrial': true,
            },
          ].where((lesson) {
            return requestedBranchId == null ||
                lesson['branchId'] == requestedBranchId;
          }).toList();
      return <String, dynamic>{
            'items': lessons,
            'groups': const [],
            'conflicts': const [],
          }
          as T;
    }
    if (path == '/crm/schedule/month-summary') {
      return <String, dynamic>{'items': const []} as T;
    }
    if (path == '/crm/rooms/availability') {
      availabilityQueries.add(
        Map<String, dynamic>.from(queryParameters ?? const {}),
      );
      return <String, dynamic>{'items': const []} as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }
}

Widget _host(Widget child, {_FakeScheduleApiClient? api}) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(api ?? _FakeScheduleApiClient()),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: child,
    ),
  );
}

Future<void> _enterTodayDayView(WidgetTester tester) async {
  final todayDay = DateTime.now().day.toString();
  final todayText = find.byWidgetPredicate(
    (w) => w is Text && w.data == todayDay && w.style?.color == AppColor.onGold,
  );
  expect(todayText, findsOneWidget);
  await tester.tap(todayText);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('«Только пробные» hides the non-trial lesson', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const ScheduleWidget()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'month view at 360px');
    await _enterTodayDayView(tester);
    expect(tester.takeException(), isNull, reason: 'day view at 360px');

    // Both lessons visible before filtering.
    expect(find.text('Анна Обычная'), findsOneWidget);
    expect(find.text('Борис Пробный'), findsOneWidget);

    // Open the filters sheet, turn on «Только пробные», apply.
    await tester.tap(find.byTooltip('Фильтры расписания'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'filter sheet at 360px');
    expect(find.byKey(const ValueKey('magic-sheet-desktop')), findsOneWidget);
    expect(find.byKey(const ValueKey('magic-sheet-handle')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('schedule-filter-lesson-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Только пробные').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-filter-apply')));
    await tester.pumpAndSettle();

    // Only the trial survives; no refetch was needed.
    expect(find.text('Борис Пробный'), findsOneWidget);
    expect(find.text('Анна Обычная'), findsNothing);
  });

  testWidgets('desktop exposes the filters as an inline dropdown panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const ScheduleWidget()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('schedule-filter-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('schedule-filter-branch')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('schedule-filter-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('schedule-filter-branch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-filter-teacher')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-filter-lesson-type')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-filter-conflicts')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the month view shows a single «today» button (dupe removed)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const ScheduleWidget()));
    await tester.pumpAndSettle();

    // Month view is the default. The gold legend duplicate is gone; the
    // toolbar exposes one clearly labelled date action.
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('сегодня'), findsNothing);
  });

  testWidgets('«Все филиалы» keeps the unscoped schedule query', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _FakeScheduleApiClient(multipleBranches: true);
    ContextViewState? savedState;

    await tester.pumpWidget(
      _host(
        ScheduleWidget(onViewStateChanged: (value) => savedState = value),
        api: api,
      ),
    );
    await tester.pumpAndSettle();
    expect(api.matrixQueries.last['branchId'], _branchId);

    await tester.tap(find.byKey(const ValueKey('schedule-filter-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-filter-branch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Все филиалы').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-filter-apply')));
    await tester.pumpAndSettle();

    expect(api.matrixQueries.last.containsKey('branchId'), isFalse);
    await tester.tap(find.byKey(const ValueKey('schedule-filter-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('schedule-filter-branch')),
        matching: find.text('Все филиалы'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('schedule-filter-toggle')));
    await tester.pumpAndSettle();
    await _enterTodayDayView(tester);
    expect(find.text('Анна Обычная'), findsOneWidget);
    expect(find.text('Борис Пробный'), findsOneWidget);
    expect(api.matrixQueries.last.containsKey('branchId'), isFalse);
    expect(savedState?.filters['branchScope'], 'all');
    final availabilityByBranch = {
      for (final query in api.availabilityQueries)
        query['branchId']?.toString(): query,
    };
    expect(
      availabilityByBranch.keys,
      containsAll([_branchId, _secondBranchId]),
    );
    expect(
      availabilityByBranch[_branchId],
      containsPair('slotFromMinutes', 360),
    );
    expect(
      availabilityByBranch[_secondBranchId],
      containsPair('slotToMinutes', 1380),
    );
    expect(
      availabilityByBranch.values.every(
        (query) => query['date'] != null && !query.containsKey('dayFrom'),
      ),
      isTrue,
    );
    expect(
      api.matrixQueries.last['localDate'],
      availabilityByBranch[_branchId]!['date'],
    );

    final restoredApi = _FakeScheduleApiClient(multipleBranches: true);
    await tester.pumpWidget(
      _host(
        ScheduleWidget(key: UniqueKey(), initialViewState: savedState),
        api: restoredApi,
      ),
    );
    await tester.pumpAndSettle();
    expect(restoredApi.matrixQueries.last.containsKey('branchId'), isFalse);
  });

  testWidgets(
    'compact branch selector renders the restored all-branches scope',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = _FakeScheduleApiClient(multipleBranches: true);

      await tester.pumpWidget(
        _host(
          ScheduleWidget(
            initialViewState: ContextViewState(
              filters: const {'branchScope': 'all'},
            ),
          ),
          api: api,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('schedule-branch-selector-__all_branches_scope__'),
        ),
        findsOneWidget,
      );
      expect(find.text('Все филиалы'), findsOneWidget);
      expect(api.matrixQueries.last.containsKey('branchId'), isFalse);
    },
  );

  testWidgets(
    'a concrete deep-link branch overrides a saved all-branches scope',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = _FakeScheduleApiClient(multipleBranches: true);

      await tester.pumpWidget(
        _host(
          ScheduleWidget(
            initialViewState: ContextViewState(
              filters: const {'branchScope': 'all'},
            ),
            initialLink: EntityLink.typed(
              entityType: EntityLinkType.branch,
              entityId: _secondBranchId,
              optionalFocus: EntityLinkFocus(
                focus: 'schedule',
                filter: const {'branchId': _secondBranchId},
              ),
            ),
          ),
          api: api,
        ),
      );
      await tester.pumpAndSettle();

      expect(api.matrixQueries.last['branchId'], _secondBranchId);
    },
  );
}
