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
  testWidgets('lesson tab shows the reconciled server balance and its links', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeCardApiClient(
      role: 'manager',
      student: _student,
      studentSubscriptions: const [
        {
          'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'status': 'active',
          'packageName': 'Абонемент на август',
          'packagePrice': 5000,
          'lessonsTotal': 10,
          'lessonsUsed': 2,
          'lessonsReserved': 1,
          'lessonsPaid': 5,
          'paidMinor': '250000',
          'debtMinor': '250000',
          'expiresAt': '2026-09-01T00:00:00.000Z',
        },
      ],
      studentAccounts: const [
        {
          'currencyCode': 'RUB',
          'actualPaymentsMinor': '250000',
          'adjustmentsMinor': '0',
          'obligationDebitsMinor': '500000',
          'obligationCreditsMinor': '0',
          'writeOffsMinor': '0',
          'balanceMinor': '-250000',
          'debtMinor': '250000',
        },
      ],
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: _student,
      entityType: 'student',
    );

    await tester.tap(find.text('Занятия'));
    await tester.pumpAndSettle();
    expect(find.text('Остаток занятий · 1 активный'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    await tester.tap(find.byKey(const Key('lesson-balance-subscriptions')));
    await tester.pumpAndSettle();
    expect(find.text('Выданные абонементы'), findsOneWidget);
  });

  testWidgets(
    'manager records a branch-scoped immutable payment from the tab',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeCardApiClient(
        role: 'manager',
        student: _student,
        studentSubscriptions: const [
          {
            'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            'status': 'active',
            'packageName': 'Абонемент на август',
            'packagePrice': 5000,
            'lessonsTotal': 10,
            'lessonsUsed': 0,
          },
        ],
        studentAccounts: const [
          {
            'currencyCode': 'RUB',
            'actualPaymentsMinor': '300000',
            'adjustmentsMinor': '0',
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
            'issuedSubscriptionId': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            'subscriptionName': 'Абонемент на август',
            'sourcePaymentId': null,
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
      expect(find.text('Оплата за август'), findsNothing);
      final paymentScroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('client-payments-tab')),
          matching: find.byType(Scrollable),
        ),
      );
      paymentScroll.position.jumpTo(paymentScroll.position.maxScrollExtent);
      await tester.pump();
      await tester.tap(find.text('Поступления и списания'));
      await tester.pumpAndSettle();
      expect(find.text('Оплата за август'), findsOneWidget);
      expect(find.textContaining('Мария Управляющая'), findsOneWidget);

      paymentScroll.position.jumpTo(0);
      await tester.pump();
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
        (item) => item.path.endsWith('/payment-records'),
      );
      expect(call.data, containsPair('amountMinor', '150050'));
      expect(
        call.data,
        containsPair(
          'issuedSubscriptionId',
          'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        ),
      );
      expect(call.data, containsPair('status', 'posted_pending'));
      expect(call.data, containsPair('verificationNote', 'Доплата за август'));
      expect(
        api.requests.where((item) => item == 'POST /crm/payments'),
        isEmpty,
      );

      final adjust = find.byKey(
        const ValueKey('adjust-payment-cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
      );
      if (adjust.evaluate().isEmpty) {
        await tester.ensureVisible(find.text('Поступления и списания'));
        await tester.tap(find.text('Поступления и списания'));
        await tester.pumpAndSettle();
      }
      tester.widget<IconButton>(adjust).onPressed!();
      await tester.pump();
      await tester.enterText(find.byKey(const Key('adjustment-amount')), '500');
      await tester.enterText(
        find.byKey(const Key('adjustment-reason')),
        'Частичный возврат',
      );
      tester
          .widget<FilledButton>(find.byKey(const Key('adjustment-submit')))
          .onPressed!();
      await tester.pumpAndSettle();
      final adjustment = api.idempotentRequests.singleWhere(
        (item) => item.path.endsWith('/adjustments'),
      );
      expect(adjustment.data, {
        'sourcePaymentId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'kind': 'refund',
        'amountMinor': '50000',
        'occurredAt': isA<String>(),
        'reason': 'Частичный возврат',
      });
    },
  );

  testWidgets(
    'three statuses, safe transition and technical reversal stay in card',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeCardApiClient(
        role: 'admin',
        student: _student,
        studentAccounts: const [
          {
            'currencyCode': 'RUB',
            'actualPaymentsMinor': '500000',
            'adjustmentsMinor': '0',
            'obligationDebitsMinor': '0',
            'obligationCreditsMinor': '0',
            'writeOffsMinor': '0',
            'balanceMinor': '500000',
            'debtMinor': '0',
            'pendingMinor': '150000',
            'remainingObligationMinor': '0',
          },
        ],
        studentMovements: const [
          {
            'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
            'kind': 'payment_record',
            'direction': 'credit',
            'amountMinor': '150000',
            'currencyCode': 'RUB',
            'occurredAt': '2026-08-07T09:00:00.000Z',
            'method': null,
            'factType': null,
            'chargeType': null,
            'comment': 'Проверить оплату за рассрочку',
            'status': 'posted_pending',
            'paymentRecordVersion': 1,
          },
        ],
        studentTechnicalHistory: const [
          {
            'id': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
            'eventType': 'technical_void',
            'paymentRecordId': '99999999-9999-4999-8999-999999999999',
            'previousStatus': 'unpaid',
            'amountMinor': '50000',
            'currencyCode': 'RUB',
            'reason': 'Ошибочная запись',
            'actorName': 'Анна Администратор',
            'occurredAt': '2026-08-06T10:00:00.000Z',
          },
        ],
        paymentReversalPreview: const {
          'paymentRecordId': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'status': 'posted_pending',
          'amountMinor': '150000',
          'currencyCode': 'RUB',
          'walletDeltaMinor': '0',
          'walletBalanceMinor': '500000',
          'resultingBalanceMinor': '500000',
          'negativeBalanceWarning': false,
          'operation': 'technical_void',
          'previewToken': 'reversal-preview',
        },
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: _student,
        entityType: 'student',
      );
      await tester.drag(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is SingleChildScrollView &&
                  widget.scrollDirection == Axis.horizontal,
            )
            .first,
        const Offset(-320, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Оплаты'));
      await tester.pumpAndSettle();
      final paymentScroll = find.descendant(
        of: find.byKey(const Key('client-payments-tab')),
        matching: find.byType(Scrollable),
      );
      final paymentScrollState = tester.state<ScrollableState>(paymentScroll);
      for (var i = 0; i < 3; i++) {
        paymentScrollState.position.jumpTo(
          paymentScrollState.position.maxScrollExtent,
        );
        await tester.pump();
      }
      await tester.tap(find.text('Поступления и списания'));
      await tester.pumpAndSettle();
      expect(find.text('Проведён, ожидает подтверждения'), findsWidgets);

      await tester.tap(
        find.byKey(
          const ValueKey('payment-status-eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отметить как долг'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('payment-transition-reason')),
        'Банк отклонил перевод',
      );
      await tester.tap(find.byKey(const Key('payment-transition-submit')));
      await tester.pumpAndSettle();
      final transition = api.idempotentRequests.singleWhere(
        (item) => item.path.endsWith('/transition'),
      );
      expect(transition.data, containsPair('targetStatus', 'unpaid'));
      expect(transition.data, containsPair('reason', 'Банк отклонил перевод'));

      await tester.tap(
        find.byKey(
          const ValueKey(
            'reverse-payment-eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('payment-reversal-reason')),
        'Создано по ошибке',
      );
      await tester.tap(find.byKey(const Key('payment-reversal-submit')));
      await tester.pumpAndSettle();
      final reversal = api.idempotentRequests.singleWhere(
        (item) => item.path.endsWith('/reversal'),
      );
      expect(reversal.data, containsPair('confirm', true));
      expect(reversal.data, containsPair('reason', 'Создано по ошибке'));

      for (var i = 0; i < 3; i++) {
        paymentScrollState.position.jumpTo(
          paymentScrollState.position.maxScrollExtent,
        );
        await tester.pump();
      }
      await tester.tap(find.text('Техническая история'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ошибочная запись'), findsOneWidget);
      expect(find.textContaining('Анна Администратор'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
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
