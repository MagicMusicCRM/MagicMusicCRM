import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_controller.dart';

class _Request {
  const _Request(this.path, this.parameters);

  final String path;
  final Map<String, dynamic> parameters;
}

class _Mutation {
  const _Mutation(this.method, this.path, this.data);

  final String method;
  final String path;
  final Map<String, dynamic>? data;
}

class _FinanceApiClient extends MagicApiClient {
  _FinanceApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<_Request> gets = [];
  final List<_Mutation> mutations = [];
  final List<Completer<Map<String, dynamic>>> paymentRequests = [];
  final List<Completer<List<int>>> exportRequests = [];
  final List<Completer<Map<String, dynamic>>> expenseRequests = [];
  int expenseReads = 0;
  Object? exportError;
  Object? expenseLoadFailure;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    gets.add(_Request(path, {...?queryParameters}));
    if (path == '/crm/payments') {
      if (paymentRequests.isNotEmpty) {
        return await paymentRequests.removeAt(0).future as T;
      }
      return <String, dynamic>{
            'items': <dynamic>[],
            'totalAmount': 0,
            'totalCount': 0,
          }
          as T;
    }
    if (path == '/crm/expenses') {
      expenseReads += 1;
      if (expenseRequests.isNotEmpty) {
        return await expenseRequests.removeAt(0).future as T;
      }
      if (expenseLoadFailure != null) throw expenseLoadFailure!;
      return <String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{
                'id': 'expense-$expenseReads',
                'amount': expenseReads * 100,
                'category': 'other',
                'createdAt': '2026-08-27T09:00:00.000Z',
              },
            ],
            'total': expenseReads * 100,
          }
          as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutations.add(
      _Mutation('POST', path, Map<String, dynamic>.from(data! as Map)),
    );
    return <String, dynamic>{'id': 'created'} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutations.add(
      _Mutation('PATCH', path, Map<String, dynamic>.from(data! as Map)),
    );
    return <String, dynamic>{'id': path.split('/').last} as T;
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutations.add(_Mutation('DELETE', path, null));
    return <String, dynamic>{'success': true} as T;
  }

  @override
  Future<List<int>> downloadBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    gets.add(_Request(path, {...?queryParameters}));
    final error = exportError;
    if (error != null) throw error;
    if (exportRequests.isNotEmpty) {
      return exportRequests.removeAt(0).future;
    }
    return <int>[1, 2, 3];
  }
}

FinanceController _controller(
  _FinanceApiClient api, {
  DateTimeRange? range,
  String? branchId,
  ReportFileOpener? opener,
  Duration realtimeDebounce = const Duration(milliseconds: 5),
}) {
  return FinanceController(
    crm: MagicCrmService(api),
    reportFileOpener:
        opener ??
        (bytes, filename) async =>
            ReportFileOpenResult(path: 'C:/reports/$filename', opened: true),
    filterRange: range,
    branchId: branchId,
    clock: () => DateTime.utc(2026, 8, 27, 12),
    realtimeDebounce: realtimeDebounce,
  );
}

Map<String, dynamic> _payments(num amount) => <String, dynamic>{
  'items': <dynamic>[],
  'totalAmount': amount,
  'totalCount': amount.toInt(),
};

void main() {
  for (final expenses in [false, true]) {
    test(
      'pagination preserves the query, retries and ignores stale pages: expenses=$expenses',
      () async {
        final api = _FinanceApiClient();
        final controller = _controller(api, branchId: 'first');
        addTearDown(controller.dispose);
        final requests = expenses ? api.expenseRequests : api.paymentRequests;
        Map<String, dynamic> page(String id, String? cursor) => {
          'items': [
            {'id': id, 'amount': 100, 'category': 'other'},
          ],
          'total': 300,
          'totalAmount': 300,
          'totalCount': 3,
          'nextCursor': cursor,
        };
        final initial = Completer<Map<String, dynamic>>();
        requests.add(initial);
        final load = expenses
            ? controller.loadExpenses()
            : controller.loadPayments();
        initial.complete(page('a', 'cursor-a'));
        await load;
        final failed = Completer<Map<String, dynamic>>();
        requests.add(failed);
        final more = expenses
            ? controller.loadMoreExpenses()
            : controller.loadMorePayments();
        failed.completeError(StateError('offline'));
        await more;
        expect(
          expenses
              ? controller.state.expensesPageError
              : controller.state.paymentsPageError,
          isNotNull,
        );
        final retry = Completer<Map<String, dynamic>>();
        requests.add(retry);
        final retryLoad = expenses
            ? controller.loadMoreExpenses()
            : controller.loadMorePayments();
        retry.complete({
          'items': [
            {'id': 'a', 'amount': 100},
            {'id': 'b', 'amount': 100},
          ],
          'nextCursor': 'cursor-b',
        });
        await retryLoad;
        expect(
          expenses
              ? controller.state.expenses.length
              : controller.state.payments.length,
          2,
        );
        final pageRequests = api.gets
            .where((r) => r.parameters['cursor'] == 'cursor-a')
            .toList();
        expect(pageRequests.length, 2);
        expect(pageRequests[0].parameters, pageRequests[1].parameters);
        final late = Completer<Map<String, dynamic>>();
        requests.add(late);
        final lateLoad = expenses
            ? controller.loadMoreExpenses()
            : controller.loadMorePayments();
        final fresh = Completer<Map<String, dynamic>>();
        requests.add(fresh);
        final changed = controller.updateExternalQuery(null, 'second');
        fresh.complete(page('new', null));
        await changed;
        late.complete(page('old', null));
        await lateLoad;
        expect(
          expenses
              ? controller.state.expenses.single['id']
              : controller.state.payments.single.id,
          'new',
        );
      },
    );
  }

  test(
    'expense refresh failure preserves data and is not a mutation failure',
    () async {
      final api = _FinanceApiClient();
      final controller = _controller(api);
      await controller.loadExpenses();
      final previous = controller.state.expenses;
      api.expenseLoadFailure = StateError('offline');
      await controller.createExpense(amount: 250, category: 'other');
      expect(api.mutations.length, 1);
      expect(controller.state.expenses, previous);
      expect(controller.state.expensesTotal, 100);
      expect(controller.state.expenseError, isNull);
      expect(controller.state.expensesLoadError, isNotNull);
      api.expenseLoadFailure = null;
      await controller.loadExpenses();
      expect(controller.state.expensesLoadError, isNull);
      controller.dispose();
    },
  );

  test('latest range and branch win over an older payment response', () async {
    final api = _FinanceApiClient();
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    api.paymentRequests.addAll([first, second]);
    final controller = _controller(
      api,
      range: DateTimeRange(
        start: DateTime.utc(2026, 8, 1),
        end: DateTime.utc(2026, 8, 7),
      ),
      branchId: 'branch-old',
    );

    final oldLoad = controller.loadPayments();
    final newLoad = controller.updateExternalQuery(
      DateTimeRange(
        start: DateTime.utc(2026, 8, 10),
        end: DateTime.utc(2026, 8, 12),
      ),
      'branch-new',
    );
    await Future<void>.delayed(Duration.zero);
    second.complete(_payments(200));
    await Future<void>.delayed(Duration.zero);
    first.complete(_payments(100));
    await Future.wait([oldLoad, newLoad]);

    expect(controller.state.total, 200);
    expect(controller.state.totalCount, 200);
    final paymentGets = api.gets
        .where((request) => request.path == '/crm/payments')
        .toList();
    expect(paymentGets.last.parameters, <String, dynamic>{
      'limit': 100,
      'from': '2026-08-10T00:00:00.000Z',
      'to': '2026-08-13T00:00:00.000Z',
      'branchId': 'branch-new',
    });
    final expenseGet = api.gets.lastWhere(
      (request) => request.path == '/crm/expenses',
    );
    expect(expenseGet.parameters, <String, dynamic>{
      'branchId': 'branch-new',
      'from': '2026-08-10T00:00:00.000Z',
      'to': '2026-08-13T00:00:00.000Z',
      'limit': 50,
    });
  });

  test('dispose ignores late load and prevents a late export open', () async {
    final loadApi = _FinanceApiClient();
    final payment = Completer<Map<String, dynamic>>();
    loadApi.paymentRequests.add(payment);
    final loadController = _controller(loadApi);
    final load = loadController.loadPayments();
    loadController.dispose();
    payment.complete(_payments(900));
    await load;
    expect(loadController.state.total, 0);

    final exportApi = _FinanceApiClient();
    final bytes = Completer<List<int>>();
    exportApi.exportRequests.add(bytes);
    var openCalls = 0;
    final exportController = _controller(
      exportApi,
      opener: (data, filename) async {
        openCalls += 1;
        return ReportFileOpenResult(path: 'C:/reports/$filename', opened: true);
      },
    );
    final export = exportController.export('csv');
    exportController.dispose();
    bytes.complete(<int>[1, 2, 3]);

    expect(await export, isNull);
    expect(openCalls, 0);
  });

  test(
    'every successful expense mutation refreshes the expense readback',
    () async {
      final api = _FinanceApiClient();
      final controller = _controller(api, branchId: 'branch-a');

      await controller.createExpense(
        amount: 900,
        category: 'rent',
        description: 'Аренда',
      );
      await controller.updateExpense(
        expenseId: 'expense-a',
        expectedVersion: 1,
        amount: 1000,
        category: 'rent',
        description: '',
        branchId: 'branch-expense',
      );
      await controller.deleteExpense('expense-a', expectedVersion: 1);

      expect(api.expenseReads, 3);
      expect(api.mutations.map((item) => item.method), [
        'POST',
        'PATCH',
        'DELETE',
      ]);
      expect(api.mutations[0].data, containsPair('branchId', 'branch-a'));
      expect(api.mutations[1].data, containsPair('branchId', 'branch-expense'));
      expect(controller.state.expensesTotal, 300);
      expect(controller.state.expenses.single['id'], 'expense-3');
    },
  );

  test('export maps filename, query and safe error text', () async {
    final api = _FinanceApiClient();
    late List<int> openedBytes;
    late String openedFilename;
    final controller = _controller(
      api,
      range: DateTimeRange(
        start: DateTime.utc(2026, 3, 2),
        end: DateTime.utc(2026, 3, 8),
      ),
      branchId: 'branch-a',
      opener: (bytes, filename) async {
        openedBytes = bytes;
        openedFilename = filename;
        return ReportFileOpenResult(
          path: 'C:/reports/$filename',
          opened: false,
        );
      },
    );

    final result = await controller.export('xlsx');

    expect(openedBytes, <int>[1, 2, 3]);
    expect(openedFilename, 'finance-202603.xlsx');
    expect(result?.filename, 'finance-202603.xlsx');
    expect(api.gets.last.parameters, <String, dynamic>{
      'from': '2026-03-02T00:00:00.000Z',
      'to': '2026-03-09T00:00:00.000Z',
      'branchId': 'branch-a',
    });
    expect(
      FinanceController.exportErrorMessage(
        const MagicApiException(statusCode: 403, message: 'Forbidden'),
      ),
      'Недостаточно прав для этого действия.',
    );
    expect(
      FinanceController.exportErrorMessage(StateError('disk full')),
      'Не удалось сохранить файл',
    );
  });

  test(
    'realtime bursts debounce to one payments and expenses refresh',
    () async {
      final api = _FinanceApiClient();
      final controller = _controller(api);
      await controller.load();
      final paymentsBefore = api.gets
          .where((request) => request.path == '/crm/payments')
          .length;
      final expensesBefore = api.expenseReads;

      controller.queueRealtimeRefresh();
      controller.queueRealtimeRefresh();
      controller.queueRealtimeRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        api.gets.where((request) => request.path == '/crm/payments').length,
        paymentsBefore + 1,
      );
      expect(api.expenseReads, expensesBefore + 1);
    },
  );
}
