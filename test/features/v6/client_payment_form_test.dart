import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_payment_form.dart';

Future<void> _pumpForm(
  WidgetTester tester, {
  required ClientPaymentSubmit onSubmit,
  String? branchId = '11111111-1111-4111-8111-111111111111',
}) async {
  tester.view.physicalSize = const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClientPaymentForm(
            branchId: branchId,
            branchName: branchId == null ? 'Филиал не указан' : 'Сокол',
            subscriptions: [
              CommerceSubscription.fromJson({
                'id': '22222222-2222-4222-8222-222222222222',
                'status': 'active',
                'startsAt': '2026-08-01T00:00:00.000Z',
                'expiresAt': null,
                'units': {
                  'total': '10',
                  'used': '0',
                  'reserved': '0',
                  'paid': '5',
                  'available': '5',
                  'remaining': '10',
                },
                'financial': {
                  'actualPaidMinor': '250000',
                  'obligationMinor': '500000',
                  'debtMinor': '250000',
                  'overpaymentMinor': '0',
                  'nextPaymentAt': null,
                },
                'terms': {
                  'displayName': '10 занятий',
                  'validityDays': 90,
                  'basePriceMinor': '500000',
                  'finalPriceMinor': '500000',
                  'currencyCode': 'RUB',
                  'discount': {'type': 'none'},
                },
                'installments': <dynamic>[],
              }),
            ],
            balanceMinor: BigInt.from(-125050),
            now: DateTime(2026, 8, 4),
            onSubmit: onSubmit,
            onCancel: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'money parser preserves kopecks and rejects negative/ambiguous input',
    () {
      expect(parsePaymentMinor('1 250,50'), BigInt.from(125050));
      expect(parsePaymentMinor('0.01'), BigInt.one);
      expect(parsePaymentMinor('-10'), isNull);
      expect(parsePaymentMinor('10.999'), isNull);
      expect(
        formatPaymentMinor(BigInt.from(-125050)).replaceAll('\u00a0', ' '),
        '−1 250,50 ₽',
      );
    },
  );

  testWidgets('network error preserves draft and stable retry identity', (
    tester,
  ) async {
    final submissions = <ClientPaymentSubmission>[];
    await _pumpForm(
      tester,
      onSubmit: (submission) async {
        submissions.add(submission);
        if (submissions.length == 1) {
          throw const MagicApiException(
            message: 'Соединение прервано после отправки.',
          );
        }
      },
    );

    await tester.enterText(find.byKey(const Key('payment-amount')), '2500,75');
    await tester.enterText(
      find.byKey(const Key('payment-invoice')),
      'ЧЕК-3905',
    );
    await tester.enterText(
      find.byKey(const Key('payment-comment')),
      'Оплата за август',
    );
    await tester.tap(find.byKey(const Key('payment-submit')));
    await tester.pumpAndSettle();

    expect(submissions, hasLength(1));
    expect(find.byKey(const Key('payment-error')), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('payment-amount')))
          .controller!
          .text,
      '2500,75',
    );

    await tester.tap(find.byKey(const Key('payment-submit')));
    await tester.pump();
    expect(submissions, hasLength(2));
    expect(
      submissions.last.identity.idempotencyKey,
      submissions.first.identity.idempotencyKey,
    );
    expect(
      submissions.last.identity.requestId,
      submissions.first.identity.requestId,
    );
    expect(submissions.last.input.toJson(), {
      'issuedSubscriptionId': '22222222-2222-4222-8222-222222222222',
      'amountMinor': '250075',
      'currencyCode': 'RUB',
      'status': 'posted_pending',
      'dueAt': '2026-08-04T09:00:00.000Z',
      'verificationNote': 'Оплата за август',
      'reason': 'Оплата по абонементу',
    });
  });

  testWidgets('missing branch and non-positive amount never submit', (
    tester,
  ) async {
    var calls = 0;
    await _pumpForm(tester, branchId: null, onSubmit: (_) async => calls++);

    await tester.enterText(find.byKey(const Key('payment-amount')), '0');
    await tester.tap(find.byKey(const Key('payment-submit')));
    await tester.pump();
    expect(find.text('Введите положительную сумму'), findsOneWidget);
    expect(calls, 0);

    await tester.enterText(find.byKey(const Key('payment-amount')), '100');
    await tester.tap(find.byKey(const Key('payment-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Оплачен').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('payment-invoice')), 'ЧЕК-1');
    await tester.tap(find.byKey(const Key('payment-submit')));
    await tester.pump();
    expect(
      find.text('Сначала укажите филиал в карточке ученика.'),
      findsOneWidget,
    );
    expect(calls, 0);
  });
}
