import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('client schedule navigation carries a month-scoped client filter', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final date = DateTime(2026, 8, 12);

    container
        .read(scheduleNavigationProvider.notifier)
        .focusClientMonth(
          date,
          clientType: 'student',
          clientId: 'student-1',
          clientName: 'Анна Тестова',
          branchId: 'branch-1',
        );

    final focus = container.read(scheduleNavigationProvider);
    expect(focus?.focusDate, date);
    expect(focus?.openMonth, isTrue);
    expect(focus?.clientType, 'student');
    expect(focus?.clientId, 'student-1');
    expect(focus?.clientName, 'Анна Тестова');
    expect(focus?.branchId, 'branch-1');
  });

  testWidgets(
    'schedule opens client branch and shows other clients in context',
    (tester) async {
      final api = _ScheduleApi();
      final container = ProviderContainer(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          crmRealtimeProvider.overrideWith(
            (ref) => const Stream<CrmChangedEvent>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final now = DateTime.now();
      container
          .read(scheduleNavigationProvider.notifier)
          .focusClientMonth(
            now,
            clientType: 'student',
            clientId: 'student-1',
            clientName: 'Анна Тестова',
            branchId: 'branch-1',
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ScheduleWidget()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Клиент: Анна Тестова'), findsOneWidget);
      expect(find.textContaining('Анна Тестова'), findsWidgets);
      expect(find.textContaining('Борис Другой'), findsWidgets);
      final hideOthers = tester.widget<FilterChip>(
        find.byKey(const ValueKey('client-calendar-hide-others')),
      );
      expect(hideOthers.selected, isFalse);
      expect(find.text('Год'), findsNothing);
      expect(api.matrixQuery?.containsKey('studentId'), isFalse);

      await tester.tap(find.text('Создать занятие'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('lesson-client-field')),
          matching: find.text('Анна Тестова · Ученик'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lesson-branch-field:branch-1')),
        findsOneWidget,
      );
    },
  );
}

class _ScheduleApi extends MagicApiClient {
  _ScheduleApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? matrixQuery;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final now = DateTime.now();
    final at = DateTime.utc(now.year, now.month, now.day, 10).toIso8601String();
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {'id': 'branch-1', 'name': 'Главный', 'utcOffsetMinutes': 0},
            ],
          }
          as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{
            'items': [
              {'id': 'room-1', 'branchId': 'branch-1', 'name': 'Класс'},
            ],
          }
          as T;
    }
    if (path == '/crm/clients/resolve') {
      return <String, dynamic>{
            'ref': {'type': 'student', 'id': 'student-1'},
            'label': 'Анна Тестова',
            'branchId': 'branch-1',
          }
          as T;
    }
    if (path == '/crm/schedule/matrix') {
      matrixQuery = Map<String, dynamic>.of(queryParameters ?? const {});
      return <String, dynamic>{
            'items': [
              {
                'id': 'lesson-1',
                'studentId': 'student-1',
                'studentName': 'Анна Тестова',
                'branchId': 'branch-1',
                'roomId': 'room-1',
                'scheduledAt': at,
                'durationMinutes': 60,
                'status': 'scheduled',
              },
              {
                'id': 'lesson-2',
                'studentId': 'student-2',
                'studentName': 'Борис Другой',
                'branchId': 'branch-1',
                'roomId': 'room-1',
                'scheduledAt': at,
                'durationMinutes': 60,
                'status': 'scheduled',
              },
            ],
            'conflicts': const [],
          }
          as T;
    }
    return <String, dynamic>{'items': const []} as T;
  }
}
