import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_controller.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_models.dart';

const _recipientId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

Map<String, dynamic> _package({
  String id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  String name = 'Вокал — 8 занятий',
  String basePriceMinor = '800000',
  num unitCount = 8,
}) => {
  'id': id,
  'name': name,
  'basePriceMinor': basePriceMinor,
  'currencyCode': 'RUB',
  'unitCount': unitCount,
};

SubscriptionPurchasePreview _preview({
  required PurchaseSubscriptionInput input,
  bool canCommit = true,
  String previewToken = 'signed-preview',
}) => SubscriptionPurchasePreview(
  recipientStudentId: _recipientId,
  payerStudentId: input.payerStudentId,
  fundingMode: input.fundingMode,
  currencyCode: 'RUB',
  finalPriceMinor: BigInt.from(640000),
  payerBalanceMinor: BigInt.from(800000),
  paidNowMinor: BigInt.from(640000),
  balanceAfterMinor: canCommit ? BigInt.from(160000) : BigInt.from(-1),
  canCommit: canCommit,
  shortageMinor: canCommit ? BigInt.zero : BigInt.one,
  debtMinor: canCommit ? BigInt.zero : BigInt.one,
  overpaymentMinor: canCommit ? BigInt.from(160000) : BigInt.zero,
  previewToken: previewToken,
);

SubscriptionIssueController _controller({
  Map<String, dynamic>? package,
  SubscriptionIssuePreview? onPreview,
  SubscriptionIssueSubmit? onSubmit,
  SubscriptionIdentityFactory? identityFactory,
  DateTime? commandTimestamp,
}) => SubscriptionIssueController(
  package: package ?? _package(),
  recipientStudentId: _recipientId,
  recipientLabel: 'Иванов Иван',
  onPreview: onPreview ?? (input) async => _preview(input: input),
  onSubmit: onSubmit ?? (_) async {},
  commandTimestamp: commandTimestamp ?? DateTime.utc(2026, 1, 31, 12),
  identityFactory: identityFactory,
);

void main() {
  test('purchase defaults to today, no expiration and full payment', () {
    final controller = _controller();
    addTearDown(controller.dispose);

    final json = controller.buildPurchase().toJson();

    expect(json['startsAt'], '2026-01-31');
    expect(json.containsKey('expiresAt'), isTrue);
    expect(json['expiresAt'], isNull);
    expect(json['paymentAmountMinor'], '800000');
    expect(json['paymentOccurredAt'], '2026-01-31T12:00:00.000Z');
    expect(json['paymentMethod'], 'cashless');
  });

  test(
    'local midnight keeps the local start date and inclusive calendar month',
    () {
      final commandTimestamp = DateTime(2026, 8, 31, 0, 15);
      final controller = _controller(commandTimestamp: commandTimestamp);
      addTearDown(controller.dispose);
      controller.setIndefinite(false);

      final json = controller.buildPurchase().toJson();

      expect(json['startsAt'], '2026-08-31');
      expect(json['expiresAt'], '2026-09-30');
      expect(
        json['paymentOccurredAt'],
        commandTimestamp.toUtc().toIso8601String(),
      );
    },
  );

  test('backdating start recalculates untouched default expiry', () {
    final controller = _controller(
      commandTimestamp: DateTime.utc(2026, 8, 29, 12),
    );
    addTearDown(controller.dispose);

    controller.setStartsAt(DateTime.utc(2026, 6, 18));
    controller.setIndefinite(false);

    expect(controller.buildPurchase().startsAt, DateTime.utc(2026, 6, 18));
    expect(controller.buildPurchase().expiresAt, DateTime.utc(2026, 7, 18));
  });

  test('moving start forward recalculates untouched default expiry', () {
    final controller = _controller();
    addTearDown(controller.dispose);

    controller.setStartsAt(DateTime.utc(2026, 2, 10));
    controller.setIndefinite(false);

    expect(controller.buildPurchase().startsAt, DateTime.utc(2026, 2, 10));
    expect(controller.buildPurchase().expiresAt, DateTime.utc(2026, 3, 10));
  });

  test('explicit expiry survives later valid and invalid start changes', () {
    final controller = _controller();
    addTearDown(controller.dispose);

    controller.setExpiresAt(DateTime.utc(2026, 6, 30));
    controller.setStartsAt(DateTime.utc(2026, 2, 10));
    expect(controller.buildPurchase().expiresAt, DateTime.utc(2026, 6, 30));
    expect(controller.validateExpiresAt(), isNull);

    controller.setStartsAt(DateTime.utc(2026, 7, 1));
    expect(controller.draft.expiresAt, DateTime.utc(2026, 6, 30));
    expect(
      controller.validateExpiresAt(),
      'Дата окончания не может быть раньше даты начала',
    );
  });

  test('package switch restores indefinite validity', () {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.setExpiresAt(DateTime.utc(2026, 6, 30));

    controller.selectPackage(
      _package(id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
    );
    controller.setStartsAt(DateTime.utc(2026, 3, 18));

    expect(controller.buildPurchase().startsAt, DateTime.utc(2026, 3, 18));
    expect(controller.buildPurchase().expiresAt, isNull);
  });

  test('zero payment is allowed and does not claim a payment method', () {
    final controller = _controller();
    addTearDown(controller.dispose);

    controller.setPaymentAmount('0');
    final json = controller.buildPurchase().toJson();

    expect(json['paymentAmountMinor'], '0');
    expect(json.containsKey('paymentMethod'), isFalse);
    expect(json.containsKey('paymentOccurredAt'), isFalse);
  });

  test(
    'package switch rebuilds defaults and rotates the preview identity',
    () async {
      var sequence = 0;
      final controller = _controller(
        identityFactory: () => MagicMutationIdentity(
          idempotencyKey: 'key-${++sequence}',
          requestId: 'request-$sequence',
        ),
      );
      addTearDown(controller.dispose);
      final previousIdentity = controller.identity;

      controller.selectPackage(
        _package(
          id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          name: 'Гитара — 12 занятий',
          basePriceMinor: '1200000',
          unitCount: 12,
        ),
      );

      expect(
        controller.draft.packageId,
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      );
      expect(
        controller.buildPurchase().paymentAmountMinor,
        BigInt.from(1200000),
      );
      expect(controller.preview, isNull);
      expect(
        controller.identity.idempotencyKey,
        isNot(previousIdentity.idempotencyKey),
      );
    },
  );

  test('paid units follow the canonical obligation projection rule', () {
    expect(
      subscriptionPaidUnits(
        packageUnits: SubscriptionUnitAmount.parse(8),
        paidNowMinor: BigInt.zero,
        finalObligationMinor: BigInt.from(800000),
      ).format(),
      '0',
    );
    expect(
      subscriptionPaidUnits(
        packageUnits: SubscriptionUnitAmount.parse(8),
        paidNowMinor: BigInt.from(800000),
        finalObligationMinor: BigInt.from(800000),
      ).format(),
      '8',
    );
    expect(
      subscriptionPaidUnits(
        packageUnits: SubscriptionUnitAmount.parse(8),
        paidNowMinor: BigInt.from(300000),
        finalObligationMinor: BigInt.from(800000),
      ).format(),
      '3',
    );
    expect(
      subscriptionPaidUnits(
        packageUnits: SubscriptionUnitAmount.parse(8),
        paidNowMinor: BigInt.from(1000000),
        finalObligationMinor: BigInt.from(800000),
      ).format(),
      '8',
    );
    expect(
      subscriptionPaidUnits(
        packageUnits: SubscriptionUnitAmount.parse(8),
        paidNowMinor: BigInt.zero,
        finalObligationMinor: BigInt.zero,
      ).format(),
      '8',
    );
  });

  test('0,01 percent is one basis point and rounds PostgreSQL half-up', () {
    final controller = _controller(package: _package(basePriceMinor: '5000'));
    addTearDown(controller.dispose);

    controller.selectDiscountMode(SubscriptionIssueDiscountMode.percent);
    controller.setDiscountValue('0,01');
    controller.setDiscountReason('Точная скидка');

    expect(controller.pricing.discountMinor, BigInt.one);
    expect(controller.buildPurchase().issue.discount!.toJson(), {
      'type': 'percent',
      'percent': 0.01,
      'reason': 'Точная скидка',
    });
  });

  test('100,01 percent is rejected before preview', () async {
    var previewCalls = 0;
    final controller = _controller(
      onPreview: (input) async {
        previewCalls++;
        return _preview(input: input);
      },
    );
    addTearDown(controller.dispose);
    controller.selectDiscountMode(SubscriptionIssueDiscountMode.percent);
    controller.setDiscountValue('100,01');
    controller.setDiscountReason('Слишком большая скидка');

    expect(await controller.submit(), SubscriptionIssueSubmitResult.blocked);
    expect(controller.error, 'Допустимо от 0,01% до 100%');
    expect(previewCalls, 0);
  });

  test('fixed discount above base is rejected before preview', () async {
    var previewCalls = 0;
    final controller = _controller(
      package: _package(basePriceMinor: '10000'),
      onPreview: (input) async {
        previewCalls++;
        return _preview(input: input);
      },
    );
    addTearDown(controller.dispose);
    controller.selectDiscountMode(SubscriptionIssueDiscountMode.fixed);
    controller.setDiscountValue('100,01');
    controller.setDiscountReason('Слишком большая скидка');

    expect(await controller.submit(), SubscriptionIssueSubmitResult.blocked);
    expect(controller.error, 'Скидка не может превышать стоимость');
    expect(previewCalls, 0);
  });

  test('enabled surcharge requires a positive amount and a reason', () async {
    var previewCalls = 0;
    final controller = _controller(
      onPreview: (input) async {
        previewCalls++;
        return _preview(input: input);
      },
    );
    addTearDown(controller.dispose);
    controller.setSurchargeEnabled(true);

    expect(await controller.submit(), SubscriptionIssueSubmitResult.blocked);
    expect(controller.error, 'Введите положительную сумму');

    controller.setSurchargeAmount('100');
    expect(await controller.submit(), SubscriptionIssueSubmitResult.blocked);
    expect(controller.error, 'Укажите причину доплаты');
    expect(previewCalls, 0);
  });

  test('installments must all remain positive', () async {
    final controller = _controller(package: _package(basePriceMinor: '2'));
    addTearDown(controller.dispose);
    controller.selectFundingMode(SubscriptionFundingMode.installment);
    controller.setInstallmentCount(3);

    expect(await controller.submit(), SubscriptionIssueSubmitResult.blocked);
    expect(controller.error, 'Итог должен позволять 3 положительных платежа.');
  });

  test('insufficient balance preview never invokes commit', () async {
    var submitCalls = 0;
    final controller = _controller(
      onPreview: (input) async => _preview(input: input, canCommit: false),
      onSubmit: (_) async => submitCalls++,
    );
    addTearDown(controller.dispose);

    expect(await controller.submit(), SubscriptionIssueSubmitResult.blocked);
    expect(controller.error, 'Покупку нельзя провести с указанными условиями.');
    expect(submitCalls, 0);
  });

  test('one payment action previews and commits the exact purchase', () async {
    final previews = <PurchaseSubscriptionInput>[];
    final submissions = <SubscriptionIssueSubmission>[];
    final controller = _controller(
      onPreview: (input) async {
        previews.add(input);
        return _preview(input: input);
      },
      onSubmit: (submission) async => submissions.add(submission),
    );
    addTearDown(controller.dispose);

    expect(await controller.submit(), SubscriptionIssueSubmitResult.committed);
    expect(previews, hasLength(1));
    expect(submissions, hasLength(1));
    expect(submissions.single.purchase.toJson(), previews.single.toJson());
    expect(submissions.single.preview.previewToken, 'signed-preview');
  });

  test(
    'pricing change before payment rotates identity and clears stale state',
    () {
      var sequence = 0;
      MagicMutationIdentity identityFactory() {
        sequence++;
        return MagicMutationIdentity(
          idempotencyKey: 'key-$sequence',
          requestId: 'request-$sequence',
        );
      }

      final controller = _controller(identityFactory: identityFactory);
      addTearDown(controller.dispose);
      final initialIdentity = controller.identity;

      controller.selectDiscountMode(SubscriptionIssueDiscountMode.percent);

      expect(controller.preview, isNull);
      expect(
        controller.identity.idempotencyKey,
        isNot(initialIdentity.idempotencyKey),
      );
      expect(controller.error, isNull);
    },
  );

  test(
    'late preview after pricing mutation cannot replace the current preview',
    () async {
      var identitySequence = 0;
      final previewRequests = <PurchaseSubscriptionInput>[];
      final previewCompleters = <Completer<SubscriptionPurchasePreview>>[];
      final submissions = <SubscriptionIssueSubmission>[];
      final controller = _controller(
        identityFactory: () {
          identitySequence++;
          return MagicMutationIdentity(
            idempotencyKey: 'key-$identitySequence',
            requestId: 'request-$identitySequence',
          );
        },
        onPreview: (input) {
          previewRequests.add(input);
          final completer = Completer<SubscriptionPurchasePreview>();
          previewCompleters.add(completer);
          return completer.future;
        },
        onSubmit: (submission) async => submissions.add(submission),
      );
      addTearDown(controller.dispose);

      final identityA = controller.identity;
      final pendingA = controller.submit();
      expect(previewCompleters, hasLength(1));

      controller.selectDiscountMode(SubscriptionIssueDiscountMode.percent);
      controller.setDiscountValue('20');
      controller.setDiscountReason('Семейная скидка');
      final identityB = controller.identity;
      expect(identityB.idempotencyKey, isNot(identityA.idempotencyKey));
      expect(controller.preview, isNull);

      final pendingB = controller.submit();
      expect(previewCompleters, hasLength(2));
      previewCompleters[1].complete(
        _preview(input: previewRequests[1], previewToken: 'preview-b'),
      );
      expect(await pendingB, SubscriptionIssueSubmitResult.committed);
      expect(controller.preview?.previewToken, 'preview-b');

      previewCompleters[0].complete(
        _preview(input: previewRequests[0], previewToken: 'preview-a'),
      );
      expect(await pendingA, SubscriptionIssueSubmitResult.blocked);
      expect(controller.preview?.previewToken, 'preview-b');
      expect(controller.error, isNull);

      expect(submissions, hasLength(1));
      expect(submissions.single.preview.previewToken, 'preview-b');
      expect(submissions.single.purchase.toJson(), previewRequests[1].toJson());
      expect(
        submissions.single.identity.idempotencyKey,
        identityB.idempotencyKey,
      );
    },
  );

  test('failed commit retry keeps identity and exact purchase JSON', () async {
    final submissions = <SubscriptionIssueSubmission>[];
    final controller = _controller(
      onSubmit: (submission) async {
        submissions.add(submission);
        if (submissions.length == 1) throw StateError('ambiguous failure');
      },
    );
    addTearDown(controller.dispose);
    controller.selectDiscountMode(SubscriptionIssueDiscountMode.percent);
    controller.setDiscountValue('20');
    controller.setDiscountReason('Семейная скидка');

    expect(await controller.submit(), SubscriptionIssueSubmitResult.failed);
    expect(controller.attempted, isTrue);
    expect(controller.fieldsEnabled, isFalse);
    expect(await controller.submit(), SubscriptionIssueSubmitResult.committed);

    expect(submissions, hasLength(2));
    expect(
      submissions.last.identity.idempotencyKey,
      submissions.first.identity.idempotencyKey,
    );
    expect(
      submissions.last.purchase.toJson(),
      submissions.first.purchase.toJson(),
    );
  });

  test('installments are UTC month-clamped with remainder first', () {
    final controller = _controller(package: _package(basePriceMinor: '1000'));
    addTearDown(controller.dispose);
    controller.selectFundingMode(SubscriptionFundingMode.installment);
    controller.setInstallmentCount(3);

    final installments = controller.buildPurchase().issue.installments;
    expect(installments.map((item) => item.amountMinor), [
      BigInt.from(334),
      BigInt.from(333),
      BigInt.from(333),
    ]);
    expect(installments.map((item) => item.dueAt), [
      DateTime.utc(2026, 1, 31, 12),
      DateTime.utc(2026, 2, 28, 12),
      DateTime.utc(2026, 3, 31, 12),
    ]);
  });

  test(
    'initial payment reduces the amount distributed across installments',
    () {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.selectFundingMode(SubscriptionFundingMode.installment);
      controller.setPaymentAmount('2500');

      final purchase = controller.buildPurchase();

      expect(purchase.paymentAmountMinor, BigInt.from(250000));
      expect(purchase.issue.installments.map((item) => item.amountMinor), [
        BigInt.from(275000),
        BigInt.from(275000),
      ]);
    },
  );
}
