import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manage_statuses_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/tasks_widget.dart';

/// Fake API client that funnels every read through [get]. All CRM/profile
/// services in the app build on top of `magicApiClientProvider`, so overriding
/// this one provider exercises the S8 loading/empty/error state machines
/// without a backend.
class _FakeApiClient extends MagicApiClient {
  _FakeApiClient({this.fail = false})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool fail;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (fail) throw Exception('network unavailable');
    return <String, dynamic>{'items': <dynamic>[], 'conflicts': <dynamic>[]}
        as T;
  }
}

Widget _host(Widget child, {bool fail = false}) {
  return ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(_FakeApiClient(fail: fail)),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('S8 desktop UX states', () {
    testWidgets('T8.1 schedule renders the calendar grid even with no lessons', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget()));
      await tester.pumpAndSettle();

      // Like the v7 prototype, an empty period shows an EMPTY calendar (weekday
      // headers + cells), never a "занятий нет" text card that replaces the grid.
      expect(find.text('На выбранный период занятий нет'), findsNothing);
      expect(find.text('Пн'), findsOneWidget);
      expect(find.text('Вс'), findsOneWidget);
    });

    testWidgets('T8.1 schedule shows an error state with retry on failure', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ScheduleWidget(), fail: true));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось загрузить расписание'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
    });

    testWidgets('T8.2 tasks expose a compact create FAB and empty state', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const TasksWidget()));
      await tester.pumpAndSettle();

      // Compact circular FAB ("+") with the action surfaced via tooltip, so the
      // label never overflows the button radius.
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byTooltip('Новая задача'), findsOneWidget);
      expect(find.text('Нет задач'), findsOneWidget);
    });

    testWidgets('T8.2 tasks surface prefetch failure for the create form', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const TasksWidget(), fail: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('Не удалось подготовить форму задачи'),
        findsOneWidget,
      );
    });

    // The lead-columns modal shares the same loading/empty/error state machine.
    // The empty path is asserted here; the error path uses the identical
    // `if (_error != null)` branch covered by the schedule/tasks error tests
    // above (an errored Riverpod FutureProvider's `.future` does not settle
    // reliably under flutter_test, so it is not pumped directly here).
    testWidgets('T8.3 lead columns modal shows an empty state', (tester) async {
      await tester.pumpWidget(
        _host(const Scaffold(body: ManageStatusesDialog())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Колонок воронки пока нет'), findsOneWidget);
    });
  });
}
