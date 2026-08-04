import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../crm/client_card/card_fake_api.dart';

const _student = <String, dynamic>{
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'firstName': 'Анна',
  'lastName': 'Соколова',
  'status': 'active',
  'branchId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'branchName': 'Сокол',
};

void main() {
  testWidgets(
    'manager records a branch-scoped immutable payment from the tab',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeCardApiClient(
        role: 'manager',
        student: _student,
        studentAccounts: const [
          {
            'currencyCode': 'RUB',
            'actualPaymentsMinor': '300000',
            'obligationDebitsMinor': '500000',
            'obligationCreditsMinor': '0',
            'writeOffsMinor': '0',
            'balanceMinor': '-200000',
            'debtMinor': '200000',
          },
        ],
        studentMovements: const [
          {
            'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            'kind': 'payment',
            'direction': 'credit',
            'amountMinor': '300000',
            'currencyCode': 'RUB',
            'occurredAt': '2026-08-01T09:00:00.000Z',
            'method': 'cashless',
            'factType': null,
            'chargeType': null,
            'branchId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            'branchName': 'Сокол',
            'comment': 'Оплата за август',
            'invoiceIdentifier': 'ЧЕК-1',
            'status': 'paid',
            'acceptedByName': 'Мария Управляющая',
          },
        ],
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: _student,
        entityType: 'student',
      );

      await tester.tap(find.text('Оплаты'));
      await tester.pumpAndSettle();
      expect(find.text('Оплаты и личный счёт'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Оплата за август'),
        160,
        scrollable: find.descendant(
          of: find.byKey(const Key('client-payments-tab')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Оплата за август'), findsOneWidget);
      expect(find.textContaining('Мария Управляющая'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('open-payment-form')),
        -160,
        scrollable: find.descendant(
          of: find.byKey(const Key('client-payments-tab')),
          matching: find.byType(Scrollable),
        ),
      );
      tester
          .widget<FilledButton>(find.byKey(const Key('open-payment-form')))
          .onPressed!();
      await tester.pump();
      expect(find.text('Новая оплата'), findsOneWidget);
      expect(find.text('Сокол'), findsWidgets);
      await tester.enterText(
        find.byKey(const Key('payment-amount')),
        '1500,50',
      );
      await tester.enterText(
        find.byKey(const Key('payment-comment')),
        'Доплата за август',
      );
      tester
          .widget<FilledButton>(find.byKey(const Key('payment-submit')))
          .onPressed!();
      await tester.pumpAndSettle();

      final call = api.idempotentRequests.singleWhere(
        (item) => item.path.endsWith('/subscription-payments'),
      );
      expect(call.data, containsPair('amountMinor', '150050'));
      expect(
        call.data,
        containsPair('branchId', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
      );
      expect(call.data, containsPair('comment', 'Доплата за август'));
      expect(
        api.requests.where((item) => item == 'POST /crm/payments'),
        isEmpty,
      );
    },
  );

  testWidgets('teacher receives no payments tab and performs no finance read', (
    tester,
  ) async {
    final api = FakeCardApiClient(role: 'teacher', student: _student);
    await pumpClientCard(
      tester,
      api: api,
      seed: _student,
      entityType: 'student',
    );

    expect(find.text('Оплаты'), findsNothing);
    expect(
      api.getRequests.where((path) => path.endsWith('/commerce')),
      isEmpty,
    );
  });
}
