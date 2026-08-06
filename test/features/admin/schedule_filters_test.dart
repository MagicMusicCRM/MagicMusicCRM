import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

/// Schedule lesson filters (пробные / конфликты / педагог) and the removal of
/// the duplicate «Сегодня» in the month view.

const _branchId = '11111111-1111-1111-1111-111111111111';
const _roomId = '22222222-2222-2222-2222-222222222222';

DateTime _today() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day, 10);
}

class _FakeScheduleApiClient extends MagicApiClient {
  _FakeScheduleApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

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
                'utcOffsetMinutes': 0,
              },
            ],
          }
          as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{
            'items': [
              {'id': _roomId, 'branchId': _branchId, 'name': 'Кабинет 1'},
            ],
          }
          as T;
    }
    if (path == '/crm/schedule/matrix') {
      return <String, dynamic>{
            'items': [
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
                'branchId': _branchId,
                'roomId': _roomId,
                'roomName': 'Кабинет 1',
                'scheduledAt': iso,
                'durationMinutes': 60,
                'status': 'scheduled',
                'isTrial': true,
              },
            ],
            'groups': const [],
            'conflicts': const [],
          }
          as T;
    }
    if (path == '/crm/schedule/month-summary') {
      return <String, dynamic>{'items': const []} as T;
    }
    if (path == '/crm/rooms/availability') {
      return <String, dynamic>{'items': const []} as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }
}

Widget _host(Widget child) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(_FakeScheduleApiClient()),
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
    (w) => w is Text && w.data == todayDay && w.style?.color == Colors.white,
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
    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    expect(find.text('Развернуть'), findsOneWidget);
    await tester.tap(find.text('Только пробные'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    // Only the trial survives; no refetch was needed.
    expect(find.text('Борис Пробный'), findsOneWidget);
    expect(find.text('Анна Обычная'), findsNothing);
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
}
