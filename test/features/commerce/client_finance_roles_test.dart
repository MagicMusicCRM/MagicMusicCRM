import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';

import '../crm/client_card/card_fake_api.dart';

const _studentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _subscriptionId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const _commerceStudent = <String, dynamic>{
  'studentId': _studentId,
  'accounts': [
    {
      'currencyCode': 'RUB',
      'actualPaymentsMinor': '500000',
      'adjustmentsMinor': '0',
      'obligationDebitsMinor': '640000',
      'obligationCreditsMinor': '0',
      'writeOffsMinor': '160000',
      'balanceMinor': '-140000',
      'debtMinor': '140000',
    },
  ],
  'subscriptions': [
    {
      'id': _subscriptionId,
      'status': 'active',
      'startsAt': '2026-07-01T00:00:00.000Z',
      'expiresAt': '2027-07-01T00:00:00.000Z',
      'units': {
        'total': '8',
        'used': '2',
        'reserved': '1',
        'paid': '6.25',
        'available': '3.25',
        'remaining': '6',
      },
      'financial': {
        'actualPaidMinor': '500000',
        'obligationMinor': '640000',
        'debtMinor': '140000',
        'overpaymentMinor': '0',
        'nextPaymentAt': null,
      },
      'terms': {
        'displayName': 'Вокал — 8 часов',
        'validityDays': 365,
        'basePriceMinor': '800000',
        'finalPriceMinor': '640000',
        'currencyCode': 'RUB',
        'discount': {'type': 'percent', 'percentBasisPoints': 2000},
      },
      'installments': [
        {
          'installmentNumber': 1,
          'dueAt': '2026-07-01T00:00:00.000Z',
          'amountMinor': '320000',
          'currencyCode': 'RUB',
          'status': 'paid',
        },
      ],
    },
  ],
  'movements': [
    {
      'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'kind': 'payment',
      'direction': 'credit',
      'amountMinor': '500000',
      'currencyCode': 'RUB',
      'occurredAt': '2026-07-02T10:00:00.000Z',
      'method': 'cash',
      'factType': null,
      'chargeType': null,
    },
    {
      'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'kind': 'lesson_charge',
      'direction': 'debit',
      'amountMinor': '160000',
      'currencyCode': 'RUB',
      'occurredAt': '2026-07-10T10:00:00.000Z',
      'method': null,
      'factType': null,
      'chargeType': 'subscription',
    },
  ],
  'lessonBalance': {
    'activeSubscriptionCount': 1,
    'total': '8',
    'used': '2',
    'reserved': '1',
    'paid': '6.25',
    'available': '3.25',
    'debts': [
      {'currencyCode': 'RUB', 'amountMinor': '140000'},
    ],
    'nextPaymentAt': null,
    'expiresAt': '2027-07-01T00:00:00.000Z',
  },
};

class _CommerceApiClient extends MagicApiClient {
  _CommerceApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<String> getRequests = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    getRequests.add(path);
    if (path == '/crm/me') {
      return <String, dynamic>{
            'students': [
              {
                'id': _studentId,
                'firstName': 'Анна',
                'lastName': 'Смирнова',
                'customData': <String, dynamic>{},
              },
            ],
          }
          as T;
    }
    if (path == '/crm/me/commerce') {
      return <String, dynamic>{
            'projection': 'client_self',
            'students': [_commerceStudent],
          }
          as T;
    }
    if (path == '/crm/students/$_studentId/commerce') {
      final staffStudent = Map<String, dynamic>.from(_commerceStudent);
      staffStudent['subscriptions'] = [
        {
          ...(_commerceStudent['subscriptions']! as List).single
              as Map<String, dynamic>,
          'terms': {
            ...(((_commerceStudent['subscriptions']! as List).single
                    as Map<String, dynamic>)['terms']
                as Map<String, dynamic>),
            'discount': {
              'type': 'fixed',
              'fixedMinor': '160000',
              'reason': 'retention.offer',
            },
          },
        },
      ];
      return <String, dynamic>{
            'projection': 'admin_scoped',
            'student': staffStudent,
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
    if (path == '/crm/expenses') {
      return <String, dynamic>{'items': <dynamic>[], 'total': 0} as T;
    }
    if (path == '/crm/reports/finance') {
      return <String, dynamic>{
            'summary': <String, dynamic>{},
            'monthly': <dynamic>[],
            'teachers': <dynamic>[],
            'rooms': <dynamic>[],
          }
          as T;
    }
    if (path == '/analytics/sources') {
      return <String, dynamic>{'sources': <dynamic>[]} as T;
    }
    if (path == '/analytics/data-quality') {
      return <String, dynamic>{} as T;
    }
    if (path == '/analytics/responsible' ||
        path == '/analytics/finance/monthly') {
      return <String, dynamic>{'items': <dynamic>[]} as T;
    }
    return <String, dynamic>{} as T;
  }
}

class _ExpenseApiClient extends _CommerceApiClient {
  _ExpenseApiClient({List<Map<String, dynamic>>? seed})
    : expenses = [...?seed?.map((item) => Map<String, dynamic>.from(item))];

  int? pageSize;
  final List<Map<String, dynamic>> expenses;
  final List<({String method, String path, Map<String, dynamic>? data})>
  mutations = [];

  @override
  Future<T> postIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) => post<T>(
    path,
    data: data,
    queryParameters: queryParameters,
    authenticated: authenticated,
  );

  @override
  Future<T> patchIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) => patch<T>(
    path,
    data: data,
    queryParameters: queryParameters,
    authenticated: authenticated,
  );

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/expenses') {
      getRequests.add(path);
      final start =
          int.tryParse(queryParameters?['cursor']?.toString() ?? '') ?? 0;
      final end = pageSize == null
          ? expenses.length
          : (start + pageSize!).clamp(0, expenses.length);
      return <String, dynamic>{
            'nextCursor': end < expenses.length ? end.toString() : null,
            'items': expenses
                .sublist(start, end)
                .map(Map<String, dynamic>.from)
                .toList(),
            'total': expenses.fold<num>(
              0,
              (sum, item) => sum + (item['amount'] as num? ?? 0),
            ),
          }
          as T;
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/expenses') {
      final body = Map<String, dynamic>.from(data! as Map);
      mutations.add((method: 'POST', path: path, data: body));
      final created = <String, dynamic>{
        'id': 'expense-created',
        'version': 1,
        ...body,
        'createdAt': DateTime(2026, 8, 12).toIso8601String(),
      };
      expenses.insert(0, created);
      return created as T;
    }
    return super.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/crm/expenses/')) {
      final body = Map<String, dynamic>.from(data! as Map);
      mutations.add((method: 'PATCH', path: path, data: body));
      final id = path.split('/').last;
      final index = expenses.indexWhere((item) => item['id'] == id);
      expect(body['expectedVersion'], expenses[index]['version']);
      expenses[index] = {
        ...expenses[index],
        ...body,
        'version': (expenses[index]['version'] as int) + 1,
      };
      return expenses[index] as T;
    }
    return super.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/crm/expenses/')) {
      expect(queryParameters?['expectedVersion'], 2);
      mutations.add((method: 'DELETE', path: path, data: null));
      final id = path.split('/').last;
      expenses.removeWhere((item) => item['id'] == id);
      return <String, dynamic>{'success': true} as T;
    }
    return super.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test(
    'typed commerce parser preserves scoped contracts and compatibility',
    () async {
      final api = _CommerceApiClient();
      final service = MagicCrmService(api);

      final own = await service.getMyCommerceProjection();
      final staff = await service.getStudentCommerceProjection(_studentId);
      final compatibility = await service.listSubscriptions(
        studentId: _studentId,
        limit: 1,
      );

      expect(own.projection, CommerceProjectionProfile.clientSelf);
      expect(
        own.studentById(_studentId)!.accounts.single.balanceMinor,
        -BigInt.from(140000),
      );
      expect(
        own.studentById(_studentId)!.subscriptions.single.terms.discount.reason,
        isNull,
      );
      expect(own.studentById(_studentId)!.paymentModels, hasLength(1));
      expect(staff.projection, CommerceProjectionProfile.adminScoped);
      expect(
        staff.student.subscriptions.single.terms.discount.reason,
        'retention.offer',
      );
      expect(
        compatibility.single,
        containsPair('package_name', 'Вокал — 8 часов'),
      );
      expect(compatibility.single, containsPair('lessons_total', 8));
      expect(compatibility.single, containsPair('lessons_used', 2));
      expect(compatibility.single, containsPair('lessons_remaining', 6));
      expect(api.getRequests, [
        '/crm/me/commerce',
        '/crm/students/$_studentId/commerce',
        '/crm/students/$_studentId/commerce',
      ]);

      final portalApi = _CommerceApiClient();
      final container = ProviderContainer(
        overrides: [magicApiClientProvider.overrideWithValue(portalApi)],
      );
      addTearDown(container.dispose);
      await container.read(magicCurrentStudentIdProvider.future);
      final payments = await container.read(clientPaymentsProvider.future);
      expect(payments, hasLength(1));
      expect(portalApi.getRequests, contains('/crm/me/commerce'));
      expect(portalApi.getRequests, isNot(contains('/crm/payments')));

      final financeEvent = CrmChangedEvent.fromFinanceMap(const {
        'scope': 'client-finance',
      });
      expect(financeEvent?.entity, 'finance');
      expect(
        CrmChangedEvent.fromFinanceMap(const {'scope': 'school-finance'}),
        isNull,
      );
    },
  );

  testWidgets('six roles receive only their approved finance surface', (
    tester,
  ) async {
    // Client: own multi-student envelope only; no staff-card endpoint.
    final clientApi = _CommerceApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(clientApi)],
        child: const MaterialApp(
          home: Scaffold(body: SubscriptionStatusCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Осталось: 6 ч'), findsOneWidget);
    expect(
      clientApi.getRequests.where((path) => path == '/crm/me/commerce'),
      hasLength(1),
    );
    expect(
      clientApi.getRequests.where((path) => path.contains('/students/')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    const legacyFinanceSubscription = <String, dynamic>{
      'id': _subscriptionId,
      'studentId': _studentId,
      'lessonsTotal': 8,
      'lessonsUsed': 2,
      'status': 'active',
      'packageName': 'Вокал — 8 часов',
      'packagePrice': 6400,
    };

    // Teacher: even a deliberately finance-rich base card cannot produce
    // commerce requests, keys, tabs or widgets.
    final teacherApi = FakeCardApiClient(
      role: 'teacher',
      student: const {
        'id': _studentId,
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'customData': <String, dynamic>{},
      },
      studentSubscriptions: const [legacyFinanceSubscription],
      studentAccounts: const [
        {
          'currencyCode': 'RUB',
          'actualPaymentsMinor': '500000',
          'obligationDebitsMinor': '640000',
          'obligationCreditsMinor': '0',
          'writeOffsMinor': '160000',
          'balanceMinor': '-140000',
          'debtMinor': '140000',
        },
      ],
      studentMovements: const [
        {
          'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'kind': 'payment',
          'direction': 'credit',
          'amountMinor': '500000',
          'currencyCode': 'RUB',
          'occurredAt': '2026-07-02T10:00:00.000Z',
          'method': 'cash',
          'factType': null,
          'chargeType': null,
        },
      ],
    );
    await pumpClientCard(
      tester,
      api: teacherApi,
      seed: const {'id': _studentId, 'custom_data': <String, dynamic>{}},
      entityType: 'student',
      statuses: const [],
    );
    expect(
      teacherApi.getRequests.where((path) => path.endsWith('/commerce')),
      isEmpty,
    );
    expect(find.text('Финансы'), findsNothing);
    expect(find.text('Абонементы'), findsNothing);
    expect(find.text('Оплаты'), findsNothing);
    expect(find.textContaining('6 400'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // Admin, Manager, Director and system_admin all use the scoped client-card
    // projection. Only Director/root may additionally open school finance.
    for (final role in const ['admin', 'manager', 'director', 'system_admin']) {
      final staffApi = FakeCardApiClient(
        role: role,
        student: const {
          'id': _studentId,
          'firstName': 'Анна',
          'lastName': 'Смирнова',
          'customData': <String, dynamic>{},
        },
        studentSubscriptions: const [legacyFinanceSubscription],
        studentAccounts: const [
          {
            'currencyCode': 'RUB',
            'actualPaymentsMinor': '500000',
            'obligationDebitsMinor': '640000',
            'obligationCreditsMinor': '0',
            'writeOffsMinor': '160000',
            'balanceMinor': '-140000',
            'debtMinor': '140000',
          },
        ],
        studentMovements: const [
          {
            'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            'kind': 'payment',
            'direction': 'credit',
            'amountMinor': '500000',
            'currencyCode': 'RUB',
            'occurredAt': '2026-07-02T10:00:00.000Z',
            'method': 'cash',
            'factType': null,
            'chargeType': null,
          },
        ],
      );
      await pumpClientCard(
        tester,
        api: staffApi,
        seed: const {'id': _studentId, 'custom_data': <String, dynamic>{}},
        entityType: 'student',
        statuses: const [],
      );
      expect(
        staffApi.getRequests.where(
          (path) => path == '/crm/students/$_studentId/commerce',
        ),
        hasLength(1),
        reason: role,
      );
      expect(find.text('Финансы'), findsOneWidget, reason: role);
      expect(find.text('Абонементы'), findsOneWidget, reason: role);
      expect(find.text('Оплаты'), findsOneWidget, reason: role);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    expect(crmHasClientCardFinanceAccess('client'), isFalse);
    expect(crmHasClientCardFinanceAccess('teacher'), isFalse);
    expect(crmHasClientCardFinanceAccess('admin'), isTrue);
    expect(crmHasClientCardFinanceAccess('manager'), isTrue);
    expect(crmHasClientCardFinanceAccess('director'), isTrue);
    expect(crmHasClientCardFinanceAccess('system_admin'), isTrue);

    expect(crmCanReceiveClientFinanceEvents('client'), isTrue);
    expect(crmCanReceiveClientFinanceEvents('teacher'), isFalse);
    expect(crmCanReceiveClientFinanceEvents('admin'), isTrue);
    expect(crmCanReceiveClientFinanceEvents('manager'), isTrue);
    expect(crmCanReceiveClientFinanceEvents('director'), isTrue);
    expect(crmCanReceiveClientFinanceEvents('system_admin'), isTrue);

    expect(crmVisibleTabs('admin', isDesktop: true), isNot(contains(5)));
    expect(crmVisibleTabs('manager', isDesktop: true), isNot(contains(5)));
    expect(crmVisibleTabs('director', isDesktop: true), isNot(contains(5)));
    expect(crmVisibleTabs('system_admin', isDesktop: true), isNot(contains(5)));
    expect(crmVisibleTabs('director', isDesktop: true), contains(7));
    expect(crmVisibleTabs('system_admin', isDesktop: true), contains(7));
  });

  testWidgets(
    'finance.changed refreshes only allowed global finance surfaces',
    (tester) async {
      int count(_CommerceApiClient api, String path) =>
          api.getRequests.where((request) => request == path).length;

      final financeApi = _CommerceApiClient();
      final financeEvents = StreamController<CrmChangedEvent>.broadcast();
      addTearDown(financeEvents.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(financeApi),
            crmRealtimeProvider.overrideWith((ref) => financeEvents.stream),
          ],
          child: const MaterialApp(home: Scaffold(body: FinanceWidget())),
        ),
      );
      await tester.pumpAndSettle();
      final initialPayments = count(financeApi, '/crm/payments');
      final initialExpenses = count(financeApi, '/crm/expenses');

      financeEvents.add(
        const CrmChangedEvent(entity: 'finance', action: 'updated'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(count(financeApi, '/crm/payments'), initialPayments + 1);
      expect(count(financeApi, '/crm/expenses'), initialExpenses + 1);

      financeEvents.add(
        const CrmChangedEvent(entity: 'expense', action: 'created'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(count(financeApi, '/crm/payments'), initialPayments + 2);
      expect(count(financeApi, '/crm/expenses'), initialExpenses + 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final reportsApi = _CommerceApiClient();
      final reportEvents = StreamController<CrmChangedEvent>.broadcast();
      addTearDown(reportEvents.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(reportsApi),
            crmRealtimeProvider.overrideWith((ref) => reportEvents.stream),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ReportsWidget(role: 'director')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialReports = count(reportsApi, '/analytics/v4/school-finance');

      reportEvents.add(
        const CrmChangedEvent(entity: 'finance', action: 'updated'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 850));
      await tester.pumpAndSettle();
      expect(
        count(reportsApi, '/analytics/v4/school-finance'),
        initialReports + 1,
      );
    },
  );

  testWidgets('director loads the next expense page from the visible control', (
    tester,
  ) async {
    final api = _ExpenseApiClient(
      seed: List.generate(
        3,
        (i) => {
          'id': 'page-expense-$i',
          'version': 1,
          'amount': 100,
          'category': 'other',
          'description': 'Расход страницы $i',
          'createdAt': '2026-08-12T08:00:00Z',
        },
      ),
    )..pageSize = 2;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: Scaffold(body: FinanceWidget())),
      ),
    );
    await tester.pumpAndSettle();
    final more = find.text('Загрузить ещё');
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('expense-history-list')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Расход страницы 2'), findsOneWidget);
    expect(find.text('Загрузить ещё'), findsNothing);
  });

  testWidgets('director completes expense create edit delete with readback', (
    tester,
  ) async {
    const branchId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final api = _ExpenseApiClient(
      seed: const [
        {
          'id': 'expense-a',
          'version': 1,
          'amount': 1200,
          'category': 'rent',
          'description': 'Старая аренда',
          'branchId': branchId,
          'createdAt': '2026-08-12T08:00:00.000Z',
        },
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(body: FinanceWidget(branchId: branchId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Аренда'), findsOneWidget);
    expect(find.textContaining('Старая аренда'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expense-actions-expense-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить').last);
    await tester.pumpAndSettle();
    expect(find.text('Изменить расход'), findsOneWidget);
    final editFields = find.byType(TextField);
    await tester.enterText(editFields.at(0), '1750');
    await tester.enterText(editFields.at(1), 'Аренда исправлена');
    final saveEdit = find.text('Сохранить изменения');
    await tester.ensureVisible(saveEdit);
    await tester.pumpAndSettle();
    await tester.tap(saveEdit);
    await tester.pumpAndSettle();
    final patch = api.mutations.singleWhere((item) => item.method == 'PATCH');
    expect(patch.path, '/crm/expenses/expense-a');
    expect(patch.data, containsPair('amount', 1750.0));
    expect(patch.data, containsPair('description', 'Аренда исправлена'));
    expect(patch.data, containsPair('branchId', branchId));
    expect(find.textContaining('Аренда исправлена'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expense-actions-expense-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();
    expect(find.text('Удалить расход?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-delete-expense')));
    await tester.pumpAndSettle();
    expect(
      api.mutations.where((item) => item.method == 'DELETE').single.path,
      '/crm/expenses/expense-a',
    );
    expect(find.text('Нет расходов за период'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Расход'));
    await tester.pumpAndSettle();
    final createFields = find.byType(TextField);
    await tester.enterText(createFields.at(0), '900');
    await tester.enterText(createFields.at(1), 'Новый расход');
    final saveCreate = find.text('Сохранить');
    await tester.ensureVisible(saveCreate);
    await tester.pumpAndSettle();
    await tester.tap(saveCreate);
    await tester.pumpAndSettle();
    final post = api.mutations.singleWhere((item) => item.method == 'POST');
    expect(post.path, '/crm/expenses');
    expect(post.data, containsPair('branchId', branchId));
    expect(find.textContaining('Новый расход'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  for (final testCase in <({String label, Object? id, String actionKey})>[
    (label: 'null', id: null, actionKey: 'expense-actions-null'),
    (label: 'empty', id: '', actionKey: 'expense-actions-'),
    (label: 'blank', id: '   ', actionKey: 'expense-actions-   '),
  ]) {
    testWidgets(
      'invalid ${testCase.label} edit expense id skips mutation and success toast',
      (tester) async {
        MagicToast.dismiss();
        addTearDown(MagicToast.dismiss);
        final api = _ExpenseApiClient(
          seed: [
            {
              'id': testCase.id,
              'amount': 1200,
              'category': 'rent',
              'description': 'Некорректный расход',
              'createdAt': '2026-08-12T08:00:00.000Z',
            },
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [magicApiClientProvider.overrideWithValue(api)],
            child: const MaterialApp(home: Scaffold(body: FinanceWidget())),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ValueKey(testCase.actionKey)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Изменить').last);
        await tester.pumpAndSettle();
        final save = find.text('Сохранить изменения');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();

        expect(api.mutations, isEmpty);
        expect(find.text('Расход изменён'), findsNothing);
      },
    );
  }

  testWidgets('director can reach the full loaded expense history', (
    tester,
  ) async {
    final expenses = List.generate(
      10,
      (index) => <String, dynamic>{
        'id': 'expense-$index',
        'amount': 100 + index,
        'category': 'other',
        'description': 'Расход $index',
        'createdAt': '2026-08-${12 - index}T08:00:00.000Z',
      },
    );
    final api = _ExpenseApiClient(seed: expenses);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: Scaffold(body: FinanceWidget())),
      ),
    );
    await tester.pumpAndSettle();

    final history = find.byKey(const ValueKey('expense-history-list'));
    expect(history, findsOneWidget);
    await tester.drag(history, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('expense-actions-expense-9')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('expense-actions-expense-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить').last);
    await tester.pumpAndSettle();
    expect(find.text('Изменить расход'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Расход 9'), findsOneWidget);
  });

  testWidgets('manager never requests or renders school expenses', (
    tester,
  ) async {
    final api = _ExpenseApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(body: ReportsWidget(role: 'manager')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.getRequests, isNot(contains('/crm/expenses')));
    expect(find.text('Расходы за период'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Расход'), findsNothing);
  });
}
