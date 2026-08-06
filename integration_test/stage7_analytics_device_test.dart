import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('stage 7 analytics IA and capability projection work on device', (
    tester,
  ) async {
    final directorApi = _DeviceApi();
    await tester.pumpWidget(_app(directorApi, role: 'director'));
    await tester.pumpAndSettle();

    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Журналы'), findsOneWidget);
    expect(find.text('Каталог'), findsOneWidget);
    await tester.tap(find.text('Журналы'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('operational-journals')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final managerApi = _DeviceApi();
    await tester.pumpWidget(_app(managerApi, role: 'manager'));
    await tester.pumpAndSettle();
    expect(managerApi.queries, isNot(contains('/analytics/v4/school-finance')));
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_DeviceApi api, {required String role}) => ProviderScope(
  overrides: [magicApiClientProvider.overrideWithValue(api)],
  child: MaterialApp(
    home: Scaffold(body: ReportsWidget(role: role)),
  ),
);

class _DeviceApi extends MagicApiClient {
  _DeviceApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final Map<String, Map<String, dynamic>> queries = {};

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    queries[path] = Map<String, dynamic>.from(queryParameters ?? const {});
    return <String, dynamic>{
          'items': <dynamic>[],
          'rows': <dynamic>[],
          'monthly': <dynamic>[],
          'summary': <String, dynamic>{},
          'counters': <String, dynamic>{'open': 0, 'overdue': 0},
        }
        as T;
  }
}
