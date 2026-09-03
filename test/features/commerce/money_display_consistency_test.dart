import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_state.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget_widgets.dart';

import '../crm/client_card/card_fake_api.dart';

const _student = {
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'firstName': 'Анна',
  'lastName': 'Соколова',
  'status': 'active',
  'branchId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
};

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final negative in [false, true]) {
    testWidgets(
      'same fractional ${negative ? 'negative' : 'positive'} amount across finance views',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final minor = negative ? '-123456' : '123456';
        final major = negative ? '-1234.56' : '1234.56';
        final expected = '${negative ? '−' : ''}1\u00a0234,56 ₽';

        await tester.pumpWidget(
          MaterialApp(
            home: FinanceView(
              state: FinanceState(
                loading: false,
                expensesLoading: false,
                payments: [
                  Payment.fromMap({'amount': major, 'currency': 'RUB'}),
                ],
              ),
              onPickRange: () async {},
              onClearRange: () async {},
              onPeriodChanged: (_) async {},
              onExportCsv: () async {},
              onExportXlsx: () async {},
              onAddExpense: () async {},
              onEditExpense: (_) async {},
              onDeleteExpense: (_) async {},
              onRetryPayments: () async {},
              onRefreshPayments: () async {},
              onOpenStudent: (_, _) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              subscriptionProvider.overrideWith(
                (ref) async => {
                  'lessons_total': 4,
                  'lessons_used': 0,
                  'actual_paid_minor': minor,
                  'currency_code': 'RUB',
                },
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: SubscriptionStatusCard()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);

        final api = FakeCardApiClient(
          role: 'director',
          student: _student,
          studentAccounts: [
            {
              'currencyCode': 'RUB',
              'actualPaymentsMinor': minor,
              'adjustmentsMinor': '0',
              'obligationDebitsMinor': '0',
              'obligationCreditsMinor': '0',
              'writeOffsMinor': '0',
              'balanceMinor': minor,
              'debtMinor': '0',
            },
          ],
          studentMovements: [
            {
              'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'kind': negative ? 'refund' : 'payment',
              'direction': negative ? 'debit' : 'credit',
              'amountMinor': '123456',
              'currencyCode': 'RUB',
              'occurredAt': '2026-08-16T09:00:00.000Z',
            },
          ],
        );
        await pumpClientCard(
          tester,
          api: api,
          seed: _student,
          entityType: 'student',
        );
        final paymentsTab = find.byKey(
          const Key('client-section-tab-payments'),
        );
        await tester.ensureVisible(paymentsTab);
        await tester.tap(paymentsTab);
        await tester.pumpAndSettle();
        expect(find.text(expected), findsNWidgets(2));

        await tester.ensureVisible(find.text('Поступления и списания'));
        await tester.tap(find.text('Поступления и списания'));
        await tester.pumpAndSettle();
        final movement = find.byKey(
          const ValueKey(
            'commerce-movement-cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          ),
        );
        expect(
          find.descendant(
            of: movement,
            matching: find.text(negative ? expected : '+$expected'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
