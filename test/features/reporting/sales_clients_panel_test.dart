import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/sales_clients_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/sales_clients_panel.dart';

void main() {
  final filter = DashboardFilter(
    from: DateTime(2026, 1, 1),
    to: DateTime(2026, 1, 31),
  );

  testWidgets(
    'cohort funnel opens a fixed client list and then the client card',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = _FakeSalesClientsDataSource();
      EntityLink? opened;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [salesClientsDataSourceProvider.overrideWithValue(source)],
          child: MaterialApp(
            home: Scaffold(
              body: SalesClientsPanel(
                filter: filter,
                canReadSchoolFinance: false,
                onOpenEntity: (link) => opened = link,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Когорта обращений'), findsOneWidget);
      expect(find.textContaining('90 дней'), findsWidgets);
      expect(
        find.byKey(const ValueKey('sales-stage-first-paid')),
        findsOneWidget,
      );
      expect(find.textContaining('Сумма первых оплат'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('sales-stage-stalled')));
      await tester.pumpAndSettle();
      expect(source.lastSegment, 'stalled');
      expect(find.text('Анна Иванова'), findsOneWidget);
      expect(find.text('Связаться после пробного'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sales-client-client-1')));
      await tester.pump();
      expect(opened?.rawEntityType, 'student');
      expect(opened?.entityId, 'client-1');
    },
  );

  testWidgets('source amounts are visible only with school-finance access', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          salesClientsDataSourceProvider.overrideWithValue(
            _FakeSalesClientsDataSource(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SalesClientsPanel(
              filter: filter,
              canReadSchoolFinance: true,
              onOpenEntity: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.textContaining('Сумма первых оплат'), findsOneWidget);
  });

  testWidgets('sales analytics adapts to supported widths at 200% text', (
    tester,
  ) async {
    for (final width in const [360.0, 600.0, 1000.0]) {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            salesClientsDataSourceProvider.overrideWithValue(
              _FakeSalesClientsDataSource(),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SalesClientsPanel(
                filter: filter,
                canReadSchoolFinance: false,
                onOpenEntity: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'sales analytics overflowed at width ${width.toInt()}',
      );
    }
    addTearDown(tester.view.reset);
  });
}

class _FakeSalesClientsDataSource implements SalesClientsDataSource {
  String? lastSegment;

  @override
  Future<Map<String, dynamic>> loadSummary(DashboardFilter filter) async => {
    'observationDays': 90,
    'generatedAt': '2026-02-01T10:00:00.000Z',
    'funnel': {
      'inquiries': 4,
      'trialBooked': 3,
      'trialAttended': 2,
      'purchases': 2,
      'firstPaidSales': 2,
      'withoutTrialSales': 1,
      'stalled': 2,
      'conversionToTrial': 0.5,
      'conversionToFirstPayment': 0.5,
      'trialToFirstPayment': 1.0,
    },
    'speed': {'averageDaysToTrial': 4.5, 'averageDaysToFirstPayment': 8.25},
    'sources': [
      {
        'sourceId': 'source-1',
        'label': 'Сайт',
        'inquiries': 4,
        'trialAttended': 2,
        'firstPaidSales': 2,
        'conversionToFirstPayment': 0.5,
        'firstPaymentAmountMinor': '900000',
        'currencyCode': 'RUB',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> loadClients(
    DashboardFilter filter, {
    required String segment,
    String? sourceId,
    int limit = 50,
    int offset = 0,
  }) async {
    lastSegment = segment;
    return {
      'total': 1,
      'items': [
        {
          'id': 'client-1',
          'type': 'student',
          'displayName': 'Анна Иванова',
          'sourceLabel': 'Сайт',
          'stageLabel': 'Пробное посещено',
          'inquiryAt': '2026-01-02T10:00:00.000Z',
          'lastActivityAt': '2026-01-10T10:00:00.000Z',
          'waitingDays': 5,
          'entityLink': {'entityType': 'student', 'entityId': 'client-1'},
          'nextTask': {
            'id': 'task-1',
            'title': 'Связаться после пробного',
            'dueAt': '2026-01-12T10:00:00.000Z',
            'entityLink': {'entityType': 'task', 'entityId': 'task-1'},
          },
        },
      ],
    };
  }
}
