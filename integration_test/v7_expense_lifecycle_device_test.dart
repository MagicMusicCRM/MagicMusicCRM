import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';

import 'evidence_screenshot.dart';

const _branchId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('Director manages expenses while Manager has no school finance', (
    tester,
  ) async {
    final directorApi = _ExpenseDeviceApi(seedExpense: true);
    await tester.pumpWidget(_app(directorApi, role: 'director'));
    await tester.pumpAndSettle();

    expect(find.text('Журналы'), findsOneWidget);
    expect(find.text('Финансовые операции'), findsOneWidget);
    expect(find.text('Аренда'), findsOneWidget);
    expect(directorApi.lastExpenseQuery?['branchId'], _branchId);

    await tester.tap(find.byKey(const ValueKey('expense-actions-expense-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить').last);
    await tester.pumpAndSettle();
    final editFields = find.byType(TextField);
    await tester.enterText(editFields.at(0), '1750');
    await tester.enterText(editFields.at(1), 'Аренда исправлена директором');
    final saveEdit = find.text('Сохранить изменения');
    await tester.ensureVisible(saveEdit);
    await tester.pumpAndSettle();
    await tester.tap(saveEdit);
    await tester.pumpAndSettle();
    expect(
      directorApi.mutations.where((item) => item.method == 'PATCH'),
      hasLength(1),
    );
    expect(find.textContaining('Аренда исправлена директором'), findsOneWidget);
    await captureEvidence(tester, 'director-expense-edited-readback');
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.byKey(const ValueKey('expense-actions-expense-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();
    expect(find.text('Удалить расход?'), findsOneWidget);
    expect(find.textContaining('аудит операции сохранится'), findsOneWidget);
    await captureEvidence(tester, 'director-expense-delete-confirmation');
    await tester.tap(find.byKey(const ValueKey('confirm-delete-expense')));
    await tester.pumpAndSettle();
    expect(
      directorApi.mutations.where((item) => item.method == 'DELETE'),
      hasLength(1),
    );
    expect(find.text('Нет расходов за период'), findsOneWidget);
    await captureEvidence(tester, 'director-expense-deleted-readback');
    await tester.pump(const Duration(seconds: 4));

    final managerApi = _ExpenseDeviceApi();
    await tester.pumpWidget(_app(managerApi, role: 'manager'));
    await tester.pumpAndSettle();
    expect(managerApi.getRequests, isNot(contains('/crm/expenses')));
    expect(find.text('Финансовые операции'), findsNothing);
    expect(find.text('Расходы за период'), findsNothing);
    await captureEvidence(tester, 'manager-without-expense-journal');
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_ExpenseDeviceApi api, {required String role}) => ProviderScope(
  overrides: [magicApiClientProvider.overrideWithValue(api)],
  child: RepaintBoundary(
    key: evidenceRootKey,
    child: MaterialApp(
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: Scaffold(
        body: ReportsWidget(
          role: role,
          initialTab: 1,
          initialViewState: ContextViewState(
            filters: const {
              'dashboardFrom': '2026-08-01T00:00:00.000',
              'dashboardTo': '2026-08-31T00:00:00.000',
              'branchId': _branchId,
            },
          ),
        ),
      ),
    ),
  ),
);

class _ExpenseDeviceApi extends MagicApiClient {
  _ExpenseDeviceApi({bool seedExpense = false})
    : expenses = seedExpense
          ? [
              <String, dynamic>{
                'id': 'expense-a',
                'amount': 1200,
                'category': 'rent',
                'description': 'Аренда до исправления',
                'branchId': _branchId,
                'branchName': 'Основной филиал',
                'createdAt': '2026-08-12T08:00:00.000Z',
              },
            ]
          : [],
      super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Map<String, dynamic>> expenses;
  final List<String> getRequests = [];
  final List<({String method, String path, Map<String, dynamic>? data})>
  mutations = [];
  Map<String, dynamic>? lastExpenseQuery;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    getRequests.add(path);
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {'id': _branchId, 'name': 'Основной филиал'},
            ],
          }
          as T;
    }
    if (path == '/crm/expenses') {
      lastExpenseQuery = Map<String, dynamic>.from(queryParameters ?? const {});
      return <String, dynamic>{
            'items': expenses.map(Map<String, dynamic>.from).toList(),
            'total': expenses.fold<num>(
              0,
              (sum, item) => sum + (item['amount'] as num? ?? 0),
            ),
          }
          as T;
    }
    if (path == '/crm/payments') {
      return <String, dynamic>{
            'items': <dynamic>[],
            'totalAmount': 0,
            'totalCount': 0,
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
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data! as Map);
    mutations.add((method: 'PATCH', path: path, data: body));
    final id = path.split('/').last;
    final index = expenses.indexWhere((item) => item['id'] == id);
    expenses[index] = {...expenses[index], ...body};
    return expenses[index] as T;
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutations.add((method: 'DELETE', path: path, data: null));
    final id = path.split('/').last;
    expenses.removeWhere((item) => item['id'] == id);
    return <String, dynamic>{'success': true} as T;
  }
}
