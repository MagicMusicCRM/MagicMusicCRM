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
}
