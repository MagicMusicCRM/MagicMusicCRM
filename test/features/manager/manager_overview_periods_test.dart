import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';

class _OverviewApi extends MagicApiClient {
  _OverviewApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final dashboardQueries = <Map<String, dynamic>>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/branches') {
      return <String, dynamic>{'items': <dynamic>[]} as T;
    }
    if (path == '/crm/dashboard/manager') {
      dashboardQueries.add(Map<String, dynamic>.from(queryParameters ?? {}));
      final comparison = dashboardQueries.length.isEven;
      return <String, dynamic>{
            'kpis': <String, dynamic>{
              'activeStudents': comparison ? 8 : 10,
              'newLeads': comparison ? 2 : 4,
              'openTasks': 3,
              'overdueTasks': 1,
              'trialLessons': 2,
              'scheduleIssues': 0,
              'roomLoadLessons': 6,
              'staffActivity': 9,
            },
            'sources': <String, dynamic>{},
          }
          as T;
    }
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
    'overview exposes agreed periods, comparable values and refresh time',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _OverviewApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(body: ManagerOverviewWidget(role: 'manager')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('overview-period-week')), findsOneWidget);
      expect(find.byKey(const Key('overview-period-month')), findsOneWidget);
      expect(find.byKey(const Key('overview-period-year')), findsOneWidget);
      expect(find.byKey(const Key('overview-period-custom')), findsOneWidget);
      expect(find.textContaining('Обновлено'), findsOneWidget);
      expect(find.textContaining('к прошлому периоду'), findsWidgets);
      expect(find.byIcon(Icons.info_outline_rounded), findsWidgets);
      expect(api.dashboardQueries, hasLength(2));

      await tester.tap(find.byKey(const Key('overview-period-year')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.dashboardQueries, hasLength(4));
      final current = api.dashboardQueries[2];
      final previous = api.dashboardQueries[3];
      expect(current['from'], isNot(previous['from']));
      expect(previous['to'], current['from']);

      await tester.tap(find.byKey(const Key('overview-period-custom')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
    },
  );
}
