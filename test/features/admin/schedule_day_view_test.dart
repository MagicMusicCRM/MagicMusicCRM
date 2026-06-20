import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

/// KVA-166 regression coverage for the schedule day view.
///
/// Two historical bugs collapsed lessons out of the day grid:
///   1. `duration_minutes` arriving as a String or double threw on a bare
///      `as int?` cast, blanking the whole card (it rendered `SizedBox.shrink`).
///   2. A lesson with no `room_id` had no room column to live in and was
///      silently dropped.
///
/// These tests pump the real [ScheduleWidget] with a fake API client and assert
/// that both kinds of lesson still RENDER (their student names are painted on
/// the day grid) and that the no-room lesson surfaces in the «Без аудитории»
/// column.

const _branchId = '11111111-1111-1111-1111-111111111111';
const _roomId = '22222222-2222-2222-2222-222222222222';

/// Today at 10:00 UTC. The fake branch uses a 0-minute UTC offset so the lesson
/// renders on today's date with no timezone math to reason about.
DateTime _today() {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day, 10);
}

/// Fake client that routes every GET by path so the schedule widget receives a
/// realistic matrix payload. Field names mirror the server's camelCase shape
/// (the service layer maps them to snake_case).
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
      } as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{
        'items': [
          {'id': _roomId, 'branchId': _branchId, 'name': 'Кабинет 1'},
        ],
      } as T;
    }
    if (path == '/crm/schedule/matrix') {
      return <String, dynamic>{
        'items': [
          // Lesson A: duration_minutes as a STRING + an assigned room.
          {
            'id': 'lesson-string',
            'studentId': 'student-a',
            'studentName': 'Анна Стрингова',
            'teacherId': 'teacher-a',
            'teacherName': 'Педагог А',
            'branchId': _branchId,
            'roomId': _roomId,
            'roomName': 'Кабинет 1',
            'scheduledAt': iso,
            // String — must not collapse the card. Tall enough that all three
            // text rows fit without a 1px overflow in the narrow test viewport.
            'durationMinutes': '90',
            'status': 'scheduled',
          },
          // Lesson B: duration_minutes as a DOUBLE + NO room.
          {
            'id': 'lesson-double',
            'studentId': 'student-b',
            'studentName': 'Борис Даблов',
            'teacherId': 'teacher-b',
            'teacherName': 'Педагог Б',
            'branchId': _branchId,
            'roomId': null, // No room → «Без аудитории» column.
            'scheduledAt': iso,
            'durationMinutes': 90.0, // double — must not collapse the card.
            'status': 'scheduled',
          },
        ],
        'groups': const [],
        'conflicts': const [],
      } as T;
    }
    if (path == '/crm/schedule/month-summary') {
      // Empty so the month cells fall back to the detailed lesson list and the
      // day grid renders from the matrix lessons.
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
    child: MaterialApp(home: child),
  );
}

/// Taps today's month cell to switch the schedule into the day (by-room) view.
/// Today's day-number is the only cell rendered with white text, so we locate
/// that Text and tap it.
Future<void> _enterTodayDayView(WidgetTester tester) async {
  final todayDay = DateTime.now().day.toString();
  final todayText = find.byWidgetPredicate(
    (w) =>
        w is Text &&
        w.data == todayDay &&
        w.style?.color == Colors.white,
  );
  expect(
    todayText,
    findsOneWidget,
    reason: 'today cell should be uniquely highlighted in white',
  );
  await tester.tap(todayText);
  await tester.pumpAndSettle();
}

void main() {
  group('KVA-166 schedule day view rendering', () {
    testWidgets(
      'lesson with String or double duration_minutes still renders',
      (tester) async {
        await tester.pumpWidget(_host(const ScheduleWidget()));
        await tester.pumpAndSettle();

        await _enterTodayDayView(tester);

        // Both cards must be painted — if the cast bug regressed, the String /
        // double lesson would collapse to SizedBox.shrink and its student name
        // would be absent.
        expect(find.text('Анна Стрингова'), findsOneWidget);
        expect(find.text('Борис Даблов'), findsOneWidget);
      },
    );

    testWidgets(
      'lesson with no room_id appears in the «Без аудитории» column',
      (tester) async {
        await tester.pumpWidget(_host(const ScheduleWidget()));
        await tester.pumpAndSettle();

        await _enterTodayDayView(tester);

        // The no-room lesson must surface under its dedicated column header
        // instead of being silently dropped from the grid.
        expect(find.text('Без аудитории'), findsWidgets);
        expect(find.text('Борис Даблов'), findsOneWidget);
      },
    );
  });
}
