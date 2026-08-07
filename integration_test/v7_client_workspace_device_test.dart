import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/crm/client_card/card_fake_api.dart';

const _student = <String, dynamic>{
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'firstName': 'Анна',
  'lastName': 'Соколова',
  'status': 'active',
  'branchId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'branchName': 'Сокол',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop card owns actions and exact staff context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeCardApiClient(
      role: 'manager',
      student: _student,
      internalNote: const {
        'id': 'note-1',
        'body': 'Важен звонок перед занятием',
        'version': 4,
        'updatedByName': 'Мария Управляющая',
        'updatedAt': '2026-08-07T10:00:00.000Z',
      },
      operationalHistory: const [
        {
          'id': 'history-1',
          'actionKey': 'crm.payment_reversed',
          'action': 'Оплата удалена из статистики',
          'reason': 'Дубль банковской операции',
          'summary': 'Сумма: 3 000 ₽',
          'actorName': 'Анна Администратор',
          'occurredAt': '2026-08-07T11:00:00.000Z',
        },
      ],
    );

    await pumpClientCard(
      tester,
      api: api,
      seed: _student,
      entityType: 'student',
      routed: true,
    );

    expect(
      find.byKey(const Key('client-desktop-section-jumps')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('subscription-add'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assign-homework'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Действия'), findsNothing);
    expect(find.text('Важен звонок перед занятием'), findsOneWidget);
    expect(find.text('Причина: Дубль банковской операции'), findsOneWidget);
    expect(find.textContaining('Анна Администратор'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('client-internal-note-input')),
      'Позвонить за час',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('client-internal-note-save')),
    );
    tester
        .widget<FilledButton>(
          find.byKey(const Key('client-internal-note-save')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(api.updateInternalNoteBody, {
      'body': 'Позвонить за час',
      'expectedVersion': 4,
    });
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    for (final key in const [
      Key('payment-movements-expansion'),
      Key('payment-installments-expansion'),
    ]) {
      final tile = tester.widget<ExpansionTile>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(ExpansionTile),
        ),
      );
      expect(tile.initiallyExpanded, isFalse);
    }
    expect(tester.takeException(), isNull);
    debugPrint('V7_CLIENT_WORKSPACE_DESKTOP_PASS ${_trace(api)}');
  });

  testWidgets('compact card preserves payment status and reversal reasons', (
    tester,
  ) async {
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
    tester
        .widget<InkWell>(
          find.ancestor(
            of: find.text('Оплаты'),
            matching: find.byType(InkWell),
          ),
        )
        .onTap!();
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'после открытия оплат');
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('client-payments-tab')),
        matching: find.byType(Scrollable),
      ),
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.text('Поступления и списания'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'после раскрытия движений');
    expect(find.text('Проведён, ожидает подтверждения'), findsWidgets);

    await tester.tap(
      find.byKey(
        const ValueKey('payment-status-eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отметить как долг'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'после открытия смены статуса');
    await tester.enterText(
      find.byKey(const Key('payment-transition-reason')),
      'Банк отклонил перевод',
    );
    await tester.pump();
    _expectNoFlutterException(tester, 'при вводе причины смены статуса');
    await tester.tap(find.byKey(const Key('payment-transition-submit')));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'после смены статуса');
    final transition = api.idempotentRequests.singleWhere(
      (item) => item.path.endsWith('/transition'),
    );
    expect(transition.data, containsPair('targetStatus', 'unpaid'));
    expect(transition.data, containsPair('reason', 'Банк отклонил перевод'));

    await tester.tap(
      find.byKey(
        const ValueKey('reverse-payment-eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'после открытия удаления оплаты');
    await tester.enterText(
      find.byKey(const Key('payment-reversal-reason')),
      'Создано по ошибке',
    );
    await tester.pump();
    _expectNoFlutterException(tester, 'при вводе причины удаления оплаты');
    await tester.tap(find.byKey(const Key('payment-reversal-submit')));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'после удаления оплаты');
    final reversal = api.idempotentRequests.singleWhere(
      (item) => item.path.endsWith('/reversal'),
    );
    expect(reversal.data, containsPair('confirm', true));
    expect(reversal.data, containsPair('reason', 'Создано по ошибке'));

    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.text('Техническая история'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester, 'после раскрытия техистории');
    expect(find.textContaining('Ошибочная запись'), findsOneWidget);
    expect(find.textContaining('Анна Администратор'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugPrint('V7_CLIENT_WORKSPACE_COMPACT_PASS ${_trace(api)}');
  });

  testWidgets(
    'lead actions remain in sections and teacher reads no staff data',
    (tester) async {
      final leadApi = FakeCardApiClient(
        role: 'admin',
        lead: const {
          'id': 'lead-1',
          'firstName': 'Анна',
          'lastName': 'Смирнова',
          'statusId': null,
          'customData': <String, dynamic>{},
        },
      );
      await pumpClientCard(
        tester,
        api: leadApi,
        seed: const {'id': 'lead-1', 'name': 'Анна', 'custom_data': {}},
      );
      expect(
        find.byKey(const Key('subscription-add'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assign-homework'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Действия'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final teacherApi = FakeCardApiClient(role: 'teacher', student: _student);
      await pumpClientCard(
        tester,
        api: teacherApi,
        seed: _student,
        entityType: 'student',
      );
      expect(find.byKey(const Key('client-internal-note')), findsNothing);
      expect(find.text('Оплаты'), findsNothing);
      expect(
        teacherApi.getRequests.where(
          (path) =>
              path.endsWith('/commerce') ||
              path.endsWith('/internal-note') ||
              path.endsWith('/operational-history'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      debugPrint('V7_CLIENT_WORKSPACE_RBAC_PASS ${_trace(teacherApi)}');
    },
  );
}

String _trace(FakeCardApiClient api) =>
    ({...api.getRequests, ...api.requests}.toList()..sort()).join(',');

void _expectNoFlutterException(WidgetTester tester, String step) {
  expect(tester.takeException(), isNull, reason: step);
}
