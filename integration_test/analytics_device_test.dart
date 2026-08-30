import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/workspace/entity_navigation_scope.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';

import '../test/support/minimal_xlsx_fixture.dart';
import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('analytics IA and capability projection work on device', (
    tester,
  ) async {
    final directorApi = _DeviceApi();
    await tester.pumpWidget(
      _app(directorApi, role: 'director', initialViewState: _fixedFilter),
    );
    await tester.pumpAndSettle();

    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Журналы'), findsOneWidget);
    expect(find.text('XLSX'), findsOneWidget);
    expect(find.text('Финансы XLSX'), findsOneWidget);
    _expectSharedFilter(directorApi, _branchA);

    await tester.tap(find.byKey(const ValueKey('dashboard-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Второй филиал').last);
    await tester.pumpAndSettle();
    _expectSharedFilter(directorApi, _branchB);

    final xlsxButton = find.widgetWithText(OutlinedButton, 'XLSX');
    await tester.ensureVisible(xlsxButton);
    tester.widget<OutlinedButton>(xlsxButton).onPressed!();
    await tester.pumpAndSettle();
    expect(directorApi.exports, hasLength(1));
    expect(directorApi.openedReports, hasLength(1));
    final xlsx = directorApi.openedReports[0];
    expect(xlsx.filename, startsWith('client-status-'));
    expect(xlsx.filename, endsWith('.xlsx'));
    expect(xlsx.bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    await tester.drag(
      find.byKey(const ValueKey('reporting-content')).first,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Файл открыт:'), findsOneWidget);
    await captureEvidence(tester, 'director-dashboard-xlsx-export');

    await tester.drag(
      find.byKey(const ValueKey('reporting-content')).first,
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    final csvButton = find.widgetWithText(OutlinedButton, 'CSV');
    await tester.ensureVisible(csvButton);
    tester.widget<OutlinedButton>(csvButton).onPressed!();
    await tester.pumpAndSettle();
    expect(directorApi.openedReports, hasLength(2));
    final csv = directorApi.openedReports[1];
    expect(csv.filename, endsWith('.csv'));
    expect(csv.bytes.take(3), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(csv.bytes), contains('Алёна Смирнова'));
    expect(utf8.decode(csv.bytes), contains('Тип;Клиент;Статус;Филиал'));
    expect(directorApi.exports, hasLength(2));
    final expectedFilter = _fixedApiFilter;
    for (final export in directorApi.exports) {
      expect(export['from'], expectedFilter['from']);
      expect(export['to'], expectedFilter['to']);
      expect(export['branchId'], _branchB);
    }
    await captureEvidence(tester, 'director-dashboard-csv-export');

    await tester.tap(find.text('Журналы'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('operational-journals')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final managerApi = _DeviceApi();
    await tester.pumpWidget(
      _app(managerApi, role: 'manager', initialViewState: _fixedFilter),
    );
    await tester.pumpAndSettle();
    expect(managerApi.queries, isNot(contains('/analytics/v4/school-finance')));
    expect(find.text('Финансы XLSX'), findsNothing);
    await tester.tap(find.text('Журналы'));
    await tester.pumpAndSettle();
    expect(find.text('Финансовые операции'), findsNothing);
    await captureEvidence(tester, 'manager-dashboard-without-school-finance');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'audit journal keeps filters while expanding and opens its target',
    (tester) async {
      final api = _DeviceApi();
      final navigation = _NavigationProbe();
      await tester.pumpWidget(
        _app(
          api,
          role: 'director',
          initialViewState: _fixedFilter,
          navigation: navigation,
          accessSnapshot: _navigationSnapshot,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Журналы'));
      await tester.pumpAndSettle();
      expect(find.text('Электронная почта изменена'), findsOneWidget);
      expect(find.text('Мария Баранова'), findsOneWidget);
      expect(find.text('Наталия Назарова'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Поиск действий'),
        'мария',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Все объекты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ученики').last);
      await tester.pumpAndSettle();
      expect(api.queries['/crm/activity'], containsPair('q', 'мария'));
      expect(
        api.queries['/crm/activity'],
        containsPair('entityType', 'student'),
      );
      final activityLoadsBeforeExpansion = api.activityRequests;

      await tester.tap(find.byKey(const Key('audit-event-expand')));
      await tester.pumpAndSettle();

      expect(find.text('Было: old@example.com'), findsOneWidget);
      expect(find.text('Стало: new@example.com'), findsOneWidget);
      expect(find.textContaining('Версия'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Поиск действий'))
            .controller
            ?.text,
        'мария',
      );
      expect(find.text('Ученики'), findsOneWidget);
      expect(api.activityRequests, activityLoadsBeforeExpansion);

      await tester.tap(find.text('Открыть ученика'));
      await tester.pumpAndSettle();
      expect(navigation.openedLink?.entityType, EntityLinkType.client);
      expect(navigation.openedLink?.entityId, _studentId);
      expect(navigation.openedLink?.rawEntityType, 'student');
      expect(navigation.preservedView?.filters['entityType'], 'student');
      expect(navigation.preservedView?.filters['query'], 'мария');
      expect(tester.takeException(), isNull);
    },
  );
}

final _fixedFilter = ContextViewState(
  filters: const {
    'dashboardFrom': '2026-07-01T00:00:00.000',
    'dashboardTo': '2026-07-31T00:00:00.000',
    'branchId': _branchA,
  },
);

const _branchA = '11111111-1111-4111-8111-111111111111';
const _branchB = '22222222-2222-4222-8222-222222222222';
const _studentId = '33333333-3333-4333-8333-333333333333';
const _navigationSnapshot = CapabilitySnapshot(
  accountId: 'account-director',
  role: 'director',
  accessVersion: 1,
  capabilities: {
    'crm.client.read.basic',
    'report.status.read',
    'commerce.school_finance.read',
  },
  scopes: {},
);

Map<String, dynamic> get _fixedApiFilter => DashboardFilter(
  from: DateTime(2026, 7, 1),
  to: DateTime(2026, 7, 31),
  branchId: _branchB,
).apiFilter;

void _expectSharedFilter(_DeviceApi api, String branchId) {
  final expected = DashboardFilter(
    from: DateTime(2026, 7, 1),
    to: DateTime(2026, 7, 31),
    branchId: branchId,
  ).apiFilter;
  for (final path in const [
    '/analytics/v4/client-status/summary',
    '/analytics/v4/lesson-success',
    '/analytics/v4/school-finance',
  ]) {
    expect(api.queries[path], containsPair('branchId', branchId), reason: path);
    expect(
      api.queries[path],
      containsPair('from', expected['from']),
      reason: path,
    );
    expect(api.queries[path], containsPair('to', expected['to']), reason: path);
  }
}

Widget _app(
  _DeviceApi api, {
  required String role,
  ContextViewState? initialViewState,
  _NavigationProbe? navigation,
  CapabilitySnapshot? accessSnapshot,
}) => ProviderScope(
  overrides: [
    magicApiClientProvider.overrideWithValue(api),
    if (accessSnapshot != null)
      capabilitySnapshotProvider.overrideWith((ref) async => accessSnapshot),
    reportFileOpenerProvider.overrideWithValue((bytes, filename) async {
      api.openedReports.add((bytes: List<int>.from(bytes), filename: filename));
      return ReportFileOpenResult(path: 'C:/Reports/$filename', opened: true);
    }),
  ],
  child: RepaintBoundary(
    key: evidenceRootKey,
    child: MaterialApp(
      home: Scaffold(
        body: navigation == null
            ? ReportsWidget(
                role: role,
                initialViewState: initialViewState,
                accessSnapshot: accessSnapshot,
              )
            : EntityNavigationScope(
                isDesktop: true,
                preserveCurrentView: (state) =>
                    navigation.preservedView = state,
                open: (link, {titleHint}) {
                  navigation.openedLink = link;
                  return EntityNavigationOpenResult.opened;
                },
                child: ReportsWidget(
                  role: role,
                  initialViewState: initialViewState,
                  accessSnapshot: accessSnapshot,
                ),
              ),
      ),
    ),
  ),
);

class _NavigationProbe {
  EntityLink? openedLink;
  ContextViewState? preservedView;
}

class _DeviceApi extends MagicApiClient {
  _DeviceApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final Map<String, Map<String, dynamic>> queries = {};
  final List<Map<String, dynamic>> exports = [];
  final List<({List<int> bytes, String filename})> openedReports = [];
  int activityRequests = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    queries[path] = Map<String, dynamic>.from(queryParameters ?? const {});
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {'id': _branchA, 'name': 'Первый филиал'},
              {'id': _branchB, 'name': 'Второй филиал'},
            ],
          }
          as T;
    }
    if (path == '/crm/activity') {
      activityRequests++;
      return <String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'audit-email-change',
                'actionKey': 'crm.student_updated',
                'title': 'Электронная почта изменена',
                'summary': 'Контактные данные обновлены',
                'reason': 'Уточнение данных',
                'actor': <String, dynamic>{
                  'id': 'user-director',
                  'name': 'Наталия Назарова',
                  'role': 'director',
                },
                'target': <String, dynamic>{
                  'type': 'student',
                  'id': _studentId,
                  'label': 'Ученик',
                  'displayName': 'Мария Баранова',
                  'routeType': 'student',
                },
                'changes': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'key': 'email',
                    'label': 'Электронная почта',
                    'before': 'old@example.com',
                    'after': 'new@example.com',
                  },
                ],
                'occurredAt': '2026-08-30T17:21:00.000Z',
              },
            ],
          }
          as T;
    }
    return <String, dynamic>{
          'items': <dynamic>[],
          'rows': <dynamic>[],
          'monthly': <dynamic>[],
          'summary': <String, dynamic>{},
          'counters': <String, dynamic>{'open': 0, 'overdue': 0},
        }
        as T;
  }

  @override
  Future<List<int>> postBytes(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    expect(path, '/analytics/v4/exports');
    final payload = Map<String, dynamic>.from(data! as Map);
    exports.add(payload);
    if (payload['format'] == 'csv') {
      return utf8.encode(
        '\uFEFFТип;Клиент;Статус;Филиал ID;Создан\r\n'
        'student;Алёна Смирнова;Занимается;$_branchB;2026-07-10\r\n',
      );
    }
    return minimalXlsxBytes();
  }
}
