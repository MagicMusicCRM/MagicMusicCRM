import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/finance_debt_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/finance_debt_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

void main() {
  final filter = DashboardFilter(
    from: DateTime(2026, 9, 1),
    to: DateTime(2026, 9, 30),
  );

  testWidgets(
    'finance registry separates debt and forecast and opens records',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = _FakeFinanceDebtDataSource();
      EntityLink? opened;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [financeDebtDataSourceProvider.overrideWithValue(source)],
          child: MaterialApp(
            home: Scaffold(
              body: FinanceDebtPanel(
                filter: filter,
                onOpenEntity: (link) => opened = link,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Реальная просрочка'), findsOneWidget);
      expect(find.text('Прогноз следующего взноса'), findsOneWidget);
      expect(find.text('Оплачено, не использовано'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finance-metric-overdue')));
      await tester.pumpAndSettle();
      expect(source.lastSegment, 'overdue');
      expect(find.text('Анна Иванова'), findsOneWidget);
      expect(find.textContaining('фактический срок'), findsOneWidget);

      await tester.tap(find.byKey(const Key('finance-client-subscription-1')));
      expect(opened?.rawEntityType, 'student');
      await tester.tap(
        find.byKey(const Key('finance-subscription-subscription-1')),
      );
      expect(opened?.rawEntityType, 'subscription');
    },
  );
}

class _FakeFinanceDebtDataSource implements FinanceDebtDataSource {
  String? lastSegment;

  @override
  Future<Map<String, dynamic>> loadSummary(DashboardFilter filter) async => {
    'currencyCode': 'RUB',
    'receiptsMinor': '1440000',
    'remainingMinor': '720000',
    'overdueMinor': '720000',
    'forecastMinor': '720000',
    'paidUnusedUnits': '6',
    'overdueClients': 1,
  };

  @override
  Future<Map<String, dynamic>> loadItems(
    DashboardFilter filter, {
    required String segment,
    int limit = 50,
    int offset = 0,
  }) async {
    lastSegment = segment;
    return {
      'total': 1,
      'items': [
        {
          'subscriptionId': 'subscription-1',
          'studentId': 'student-1',
          'displayName': 'Анна Иванова',
          'packageName': 'Вокал 8',
          'remainingMinor': '720000',
          'overdueMinor': '720000',
          'forecastMinor': '0',
          'paidUnusedUnits': '0',
          'nextDueAt': '2026-09-10T00:00:00.000Z',
          'nextDueIsForecast': false,
          'clientLink': {'entityType': 'student', 'entityId': 'student-1'},
          'subscriptionLink': {
            'entityType': 'subscription',
            'entityId': 'subscription-1',
          },
          'paymentLink': null,
          'owner': null,
          'nextTask': null,
        },
      ],
    };
  }
}
