import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

/// KVA-195 redesign coverage: Месяц/Неделя/День navigation, the day-grid canvas,
/// the interaction legend (no per-cell instructions), and the quick-create
/// popover wired to the existing `POST /crm/lessons` contract.

const _branchId = '11111111-1111-1111-1111-111111111111';
const _roomId = '22222222-2222-2222-2222-222222222222';

DateTime _today() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day, 10);
}

class _FakeClient extends MagicApiClient {
  _FakeClient()
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
              {'id': _branchId, 'name': 'Сокол', 'utcOffsetMinutes': 0},
            ],
          }
          as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{
            'items': [
              {'id': _roomId, 'branchId': _branchId, 'name': 'Аудитория 1'},
            ],
          }
          as T;
    }
    if (path == '/crm/schedule/matrix') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'lesson-1',
                'studentId': 'student-a',
                'studentName': 'Ольга Ученик',
                'teacherId': 'teacher-a',
                'teacherName': 'Анна Сусарина',
                'branchId': _branchId,
                'roomId': _roomId,
                'roomName': 'Аудитория 1',
                'scheduledAt': iso,
                'durationMinutes': 120,
                'status': 'scheduled',
              },
            ],
            'groups': const [],
            'conflicts': const [],
          }
          as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }
}

Widget _host(Widget child) {
  return ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(_FakeClient())],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  group('KVA-195 schedule redesign', () {
    testWidgets('responsive toolbar has one labelled create action', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();

      expect(find.text('Расписание'), findsOneWidget);
      expect(find.text('Создать занятие'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('schedule-create-lesson')),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.byKey(const ValueKey('schedule-view-switcher')),
        findsOneWidget,
      );
      expect(find.text('Филиал'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Месяц / Неделя / День switcher changes the view', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();

      // Default = month: weekday headers visible.
      expect(find.text('Пн'), findsOneWidget);
      expect(find.text('Год'), findsNothing);

      await tester.tap(find.text('Неделя'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-week-view')), findsOneWidget);
      expect(find.byType(ScheduleDayCanvas), findsOneWidget);
      expect(find.text('Ольга Ученик'), findsOneWidget);
      expect(find.text('Перетащить — время / день'), findsOneWidget);

      // Switch to День → the time grid (wide «Время» gutter header) is shown.
      await tester.tap(find.text('День'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleDayCanvas), findsOneWidget);
      expect(find.text('Время'), findsOneWidget);
    });

    testWidgets('day grid shows the interaction legend, not per-cell hints', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('День'));
      await tester.pumpAndSettle();

      // The legend carries the rules…
      expect(find.text('Конфликт'), findsOneWidget);
      // …and the old per-cell instruction is gone (owner rule #10).
      expect(find.text('Нажмите,\nчтобы назначить'), findsNothing);
      expect(find.textContaining('Нажмите'), findsNothing);
    });

    testWidgets('tapping an empty hour opens the (single) create dialog', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('День'));
      await tester.pumpAndSettle();

      // Tap an empty slot near the top of the first room column (the lesson is
      // at 10:00, well below the 08:00 fold we tap into).
      final canvas = tester.getRect(find.byType(ScheduleDayCanvas));
      final tapAt = Offset(
        canvas.left + kTimeColWidth + 40, // inside room column 1
        canvas.top + kHeaderHeight + 14, // ≈ 08:10
      );
      await tester.tapAt(tapAt);
      await tester.pumpAndSettle();

      // Consolidated to the single full create window (no separate compact sheet).
      expect(find.text('Новое занятие'), findsOneWidget);
    });

    testWidgets('week canvas maps each column to its own calendar date', (
      tester,
    ) async {
      final monday = DateTime(2026, 8, 3);
      final tuesday = monday.add(const Duration(days: 1));
      DateTime? createdAt;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleDayCanvas(
              date: monday,
              columns: [
                ScheduleColumn(
                  id: 'tuesday',
                  name: 'Вт',
                  color: Colors.blue,
                  date: tuesday,
                ),
              ],
              entries: const [],
              onCreateSlot: (_, start, _) => createdAt = start,
              onMove: (_, _, _) {},
              onResize: (_, _, _) {},
              onOpenLesson: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final canvas = tester.getRect(find.byType(ScheduleDayCanvas));
      await tester.tapAt(
        Offset(
          canvas.left + kTimeColWidth + 40,
          canvas.top + kHeaderHeight + 14,
        ),
      );
      await tester.pump();

      expect(createdAt, isNotNull);
      expect(DateUtils.isSameDay(createdAt, tuesday), isTrue);
    });
  });
}
