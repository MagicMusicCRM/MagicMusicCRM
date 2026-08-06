import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';

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
  // The tasks day pager formats its date in ru, like the app does after
  // main.dart initialises the locale.
  setUpAll(() => initializeDateFormatting('ru', null));

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
  });
}
