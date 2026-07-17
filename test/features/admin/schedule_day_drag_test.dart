import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

/// Which lessons the day grid lets you move.
///
/// Regression: the grid froze every lesson whose status was `completed` or
/// `done`. That looked like a defensible «don't edit the past» rule, but the
/// HolliHop importer stamps `completed` on every lesson dated before the import
/// run (hollihop-import.ts — `attended || isPast`), so all ~33k historical
/// lessons carried it. The whole schedule up to today silently refused to drag
/// or resize while tomorrow behaved fine — which is exactly the «works on some
/// cards, not on others» the owner reported. Only `cancelled` freezes a card
/// now.

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
          {'id': _branchId, 'name': 'Главный филиал', 'utcOffsetMinutes': 0},
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
          // What the importer produces for every past lesson.
          {
            'id': 'lesson-completed',
            'studentId': 'student-a',
            'studentName': 'Анна Прошлова',
            'teacherId': 'teacher-a',
            'teacherName': 'Педагог А',
            'branchId': _branchId,
            'roomId': _roomId,
            'roomName': 'Кабинет 1',
            'scheduledAt': iso,
            'durationMinutes': 90,
            'status': 'completed',
          },
          // A cancelled lesson is the one thing that stays frozen.
          {
            'id': 'lesson-cancelled',
            'studentId': 'student-b',
            'studentName': 'Борис Отменов',
            'teacherId': 'teacher-b',
            'teacherName': 'Педагог Б',
            'branchId': _branchId,
            'roomId': _roomId,
            'roomName': 'Кабинет 1',
            'scheduledAt': _today()
                .add(const Duration(hours: 3))
                .toIso8601String(),
            'durationMinutes': 90,
            'status': 'cancelled',
          },
        ],
        'groups': const [],
        'conflicts': const [],
      } as T;
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

/// Hosts the grid on its DESKTOP branch — the platform the owner reported on,
/// and the one that uses a plain [Draggable] (a mouse drag is immediate). Touch
/// gets a LongPressDraggable instead so a drag never fights finger-scroll.
/// The grid reads the platform off the theme, so no global override is needed.
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

/// The day grid hands the lesson row itself to the Draggable, so a card is
/// movable exactly when a `Draggable<Map<String, dynamic>>` carries its row.
Finder _draggableFor(String lessonId) {
  return find.byWidgetPredicate(
    (w) => w is Draggable<Map<String, dynamic>> && w.data?['id'] == lessonId,
  );
}

void main() {
  group('schedule day grid — which cards move', () {
    testWidgets('a past («completed») lesson is still draggable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();
      await _enterTodayDayView(tester);

      expect(find.text('Анна Прошлова'), findsOneWidget);
      expect(
        _draggableFor('lesson-completed'),
        findsOneWidget,
        reason:
            'every imported past lesson is «completed»; freezing that status '
            'froze the entire historical schedule',
      );
    });

    testWidgets('a cancelled lesson stays frozen', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();
      await _enterTodayDayView(tester);

      expect(find.text('Борис Отменов'), findsOneWidget);
      expect(
        _draggableFor('lesson-cancelled'),
        findsNothing,
        reason: 'a cancelled lesson is not rescheduled, it is recreated',
      );
    });
  });
}
