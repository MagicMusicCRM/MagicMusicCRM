import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_controller.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_models.dart';

const _recipientId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

Map<String, dynamic> _package({String basePriceMinor = '800000'}) => {
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'name': 'Вокал — 8 занятий',
  'basePriceMinor': basePriceMinor,
  'currencyCode': 'RUB',
};

SubscriptionPurchasePreview _preview({
  required PurchaseSubscriptionInput input,
  bool canCommit = true,
}) => SubscriptionPurchasePreview(
  recipientStudentId: _recipientId,
  payerStudentId: input.payerStudentId,
  fundingMode: input.fundingMode,
  currencyCode: 'RUB',
  finalPriceMinor: BigInt.from(640000),
  payerBalanceMinor: BigInt.from(800000),
  balanceAfterMinor: canCommit ? BigInt.from(160000) : BigInt.from(-1),
  canCommit: canCommit,
  shortageMinor: canCommit ? BigInt.zero : BigInt.one,
  previewToken: 'signed-preview',
);

SubscriptionIssueController _controller({
  Map<String, dynamic>? package,
  SubscriptionIssuePreview? onPreview,
  SubscriptionIssueSubmit? onSubmit,
  SubscriptionIdentityFactory? identityFactory,
}) => SubscriptionIssueController(
  package: package ?? _package(),
  recipientStudentId: _recipientId,
  recipientLabel: 'Иванов Иван',
  onPreview: onPreview ?? (input) async => _preview(input: input),
  onSubmit: onSubmit ?? (_) async {},
  commandTimestamp: DateTime.utc(2026, 1, 31, 12),
  identityFactory: identityFactory,
);

void main() {
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

    expect(
      await controller.submit(),
      SubscriptionIssueSubmitResult.previewLoaded,
    );
    expect(await controller.submit(), SubscriptionIssueSubmitResult.blocked);
    expect(controller.error, 'На личном счёте недостаточно средств.');
    expect(submitCalls, 0);
  });

  test(
    'pricing change after preview rotates identity and clears preview',
    () async {
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
      expect(
        await controller.submit(),
        SubscriptionIssueSubmitResult.previewLoaded,
      );
      expect(controller.preview, isNotNull);

      controller.selectDiscountMode(SubscriptionIssueDiscountMode.percent);

      expect(controller.preview, isNull);
      expect(
        controller.identity.idempotencyKey,
        isNot(initialIdentity.idempotencyKey),
      );
      expect(controller.error, isNull);
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

    expect(
      await controller.submit(),
      SubscriptionIssueSubmitResult.previewLoaded,
    );
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
}
