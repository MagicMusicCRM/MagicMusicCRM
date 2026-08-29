import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_sheet.dart';

typedef _Call = ({String path, Object? data, MagicMutationIdentity? identity});

class _PurchaseApiClient extends MagicApiClient {
  _PurchaseApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final calls = <_Call>[];

  Map<String, dynamic> get preview => const {
    'recipientStudentId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'payerStudentId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'fundingMode': 'personal_account',
    'currencyCode': 'RUB',
    'finalPriceMinor': '640000',
    'payerBalanceMinor': '800000',
    'paidNowMinor': '640000',
    'balanceAfterMinor': '160000',
    'canCommit': true,
    'shortageMinor': '0',
    'debtMinor': '0',
    'overpaymentMinor': '160000',
    'previewToken': 'signed-preview',
  };

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((path: path, data: data, identity: null));
    return preview as T;
  }

  @override
  Future<T> postIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((path: path, data: data, identity: identity));
    return <String, dynamic>{
          'subscription': {'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'},
        }
        as T;
  }
}

const _package = <String, dynamic>{
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'name': 'Вокал — 8 занятий',
  'basePriceMinor': '800000',
  'currencyCode': 'RUB',
  'unitCount': 8,
};
const _recipientId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _payerId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

SubscriptionPurchasePreview _preview({
  String payerId = _recipientId,
  SubscriptionFundingMode mode = SubscriptionFundingMode.personalAccount,
  BigInt? finalPriceMinor,
}) => SubscriptionPurchasePreview(
  recipientStudentId: _recipientId,
  payerStudentId: payerId,
  fundingMode: mode,
  currencyCode: 'RUB',
  finalPriceMinor: finalPriceMinor ?? BigInt.from(640000),
  payerBalanceMinor: BigInt.from(800000),
  paidNowMinor: finalPriceMinor ?? BigInt.from(640000),
  balanceAfterMinor:
      BigInt.from(800000) - (finalPriceMinor ?? BigInt.from(640000)),
  canCommit: true,
  shortageMinor: BigInt.zero,
  debtMinor: BigInt.zero,
  overpaymentMinor:
      BigInt.from(800000) - (finalPriceMinor ?? BigInt.from(640000)),
  previewToken: 'signed-preview',
);

Future<void> _openSheet(
  WidgetTester tester, {
  required SubscriptionIssuePreview onPreview,
  required SubscriptionIssueSubmit onSubmit,
  Future<List<SearchableSelectItem>> Function(String query)? searchPayers,
  List<Map<String, dynamic>>? packages,
  String acceptedByLabel = 'Анна Администратор',
}) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showSubscriptionIssueFormSheet(
              context,
              package: _package,
              packages: packages,
              acceptedByLabel: acceptedByLabel,
              recipientStudentId: _recipientId,
              recipientLabel: 'Иванов Иван',
              searchPayers: searchPayers ?? (_) async => const [],
              onPreview: onPreview,
              onSubmit: onSubmit,
              commandTimestamp: DateTime.utc(2026, 8, 26),
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<String> _normalizedTexts(WidgetTester tester, Finder parent) => tester
    .widgetList<Text>(find.descendant(of: parent, matching: find.byType(Text)))
    .map(
      (widget) => (widget.data ?? '')
          .replaceAll('\u00a0', ' ')
          .replaceAll('\u202f', ' '),
    )
    .toList(growable: false);

void main() {
  testWidgets(
    'one sale sheet keeps package selector and payment fields together',
    (tester) async {
      await _openSheet(
        tester,
        packages: const [
          _package,
          {
            'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
            'name': 'Гитара — 12 занятий',
            'basePriceMinor': '1200000',
            'currencyCode': 'RUB',
            'unitCount': 12,
          },
        ],
        onPreview: (_) async => _preview(),
        onSubmit: (_) async {},
      );

      expect(
        find.byKey(const Key('subscription-package-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('subscription-payment-method')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('subscription-payment-comment')),
        findsOneWidget,
      );
      final acceptedBy = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('subscription-accepted-by')),
          matching: find.byType(TextField),
        ),
      );
      expect(acceptedBy.readOnly, isTrue);
      expect(acceptedBy.controller!.text, 'Анна Администратор');
    },
  );

  testWidgets('preview shows canonical paid units with the debt status color', (
    tester,
  ) async {
    await _openSheet(
      tester,
      onPreview: (_) async => SubscriptionPurchasePreview(
        recipientStudentId: _recipientId,
        payerStudentId: _recipientId,
        fundingMode: SubscriptionFundingMode.personalAccount,
        currencyCode: 'RUB',
        finalPriceMinor: BigInt.from(800000),
        payerBalanceMinor: BigInt.zero,
        paidNowMinor: BigInt.from(300000),
        balanceAfterMinor: BigInt.zero,
        canCommit: true,
        shortageMinor: BigInt.zero,
        debtMinor: BigInt.from(500000),
        overpaymentMinor: BigInt.zero,
        previewToken: 'partial-preview',
      ),
      onSubmit: (_) async {},
    );

    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));

    final status = tester.widget<Container>(
      find.byKey(const Key('subscription-paid-units-status')),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('subscription-paid-units-status')),
        matching: find.text('3 из 8 занятий'),
      ),
      findsOneWidget,
    );
    expect(
      (status.decoration! as BoxDecoration).border!.top.color,
      AppColor.warning,
    );
  });

  testWidgets('selected package and payment details reach preview', (
    tester,
  ) async {
    PurchaseSubscriptionInput? previewInput;
    await _openSheet(
      tester,
      packages: const [
        _package,
        {
          'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'name': 'Гитара — 12 занятий',
          'basePriceMinor': '1200000',
          'currencyCode': 'RUB',
          'unitCount': 12,
        },
      ],
      onPreview: (input) async {
        previewInput = input;
        return _preview();
      },
      onSubmit: (_) async {},
    );

    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const Key('subscription-package-selector')),
        )
        .onChanged!('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('subscription-payment-1200000')),
      '6000',
    );
    tester
        .widget<DropdownButtonFormField<SubscriptionPaymentMethod>>(
          find.byKey(const Key('subscription-payment-method')),
        )
        .onChanged!(SubscriptionPaymentMethod.cash);
    await tester.enterText(
      find.byKey(const Key('subscription-payment-comment')),
      'Оплата наличными',
    );
    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));

    expect(
      previewInput?.issue.packageId,
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    );
    expect(previewInput?.paymentAmountMinor, BigInt.from(600000));
    expect(previewInput?.issue.paymentMethod, SubscriptionPaymentMethod.cash);
    expect(previewInput?.paymentComment, 'Оплата наличными');
    expect(previewInput?.startsAt, DateTime.utc(2026, 8, 26));
    expect(previewInput?.expiresAt, DateTime.utc(2026, 9, 26));
  });

  testWidgets('existing subscription sale sends the selected payment method', (
    tester,
  ) async {
    PurchaseSubscriptionInput? previewInput;
    await _openSheet(
      tester,
      onPreview: (input) async {
        previewInput = input;
        return _preview();
      },
      onSubmit: (_) async {},
    );

    final method = tester
        .widget<DropdownButtonFormField<SubscriptionPaymentMethod>>(
          find.byKey(const Key('subscription-payment-method')),
        );
    method.onChanged!(SubscriptionPaymentMethod.cash);
    await tester.pump();
    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));

    expect(previewInput?.issue.paymentMethod, SubscriptionPaymentMethod.cash);
  });

  testWidgets('disposing during preview ignores the late completion', (
    tester,
  ) async {
    final preview = Completer<SubscriptionPurchasePreview>();
    await _openSheet(
      tester,
      onPreview: (_) => preview.future,
      onSubmit: (_) async {},
    );

    final submit = find.byKey(const Key('subscription-issue-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    preview.complete(_preview());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during commit ignores the late completion', (
    tester,
  ) async {
    final commit = Completer<void>();
    await _openSheet(
      tester,
      onPreview: (_) async => _preview(),
      onSubmit: (_) => commit.future,
    );
    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));

    final submit = find.byKey(const Key('subscription-issue-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    commit.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  test(
    'purchase uses preview + idempotent commit and never legacy issue',
    () async {
      final api = _PurchaseApiClient();
      final service = MagicCrmService(api);
      const identity = MagicMutationIdentity(
        idempotencyKey: 'purchase-stable-key',
        requestId: 'purchase-stable-request',
      );
      final input = PurchaseSubscriptionInput(
        issue: IssueSubscriptionInput(
          packageId: _package['id']! as String,
          paymentMethod: SubscriptionPaymentMethod.cashless,
          discount: SubscriptionDiscountInput.percent(
            basisPoints: 2000,
            reason: 'Семейная скидка',
          ),
        ),
        payerStudentId: _payerId,
        fundingMode: SubscriptionFundingMode.personalAccount,
        startsAt: DateTime.utc(2026, 8, 26),
        expiresAt: DateTime.utc(2026, 9, 26),
        paymentAmountMinor: BigInt.from(640000),
        paymentOccurredAt: DateTime.utc(2026, 8, 26, 12),
        purchaseReason: 'Родитель оплачивает обучение ребёнка',
      );

      final preview = await service.previewSubscriptionPurchase(
        _recipientId,
        input: input,
      );
      await service.purchaseSubscription(
        _recipientId,
        input: input,
        preview: preview,
        identity: identity,
      );

      expect(api.calls.map((call) => call.path), [
        '/crm/students/$_recipientId/subscriptions/purchase/preview',
        '/crm/students/$_recipientId/subscriptions/purchase',
      ]);
      expect(api.calls.last.identity, same(identity));
      expect(api.calls.last.data, containsPair('confirm', true));
      expect(
        api.calls.last.data,
        containsPair('previewToken', 'signed-preview'),
      );
      expect(api.calls.last.data, containsPair('payerStudentId', _payerId));
      expect(
        api.calls.last.data,
        containsPair('purchaseReason', 'Родитель оплачивает обучение ребёнка'),
      );
    },
  );

  testWidgets('preview is explicit and commit retry keeps one identity', (
    tester,
  ) async {
    final submissions = <SubscriptionIssueSubmission>[];
    await _openSheet(
      tester,
      onPreview: (input) async => _preview(mode: input.fundingMode),
      onSubmit: (submission) async {
        submissions.add(submission);
        if (submissions.length == 1) {
          throw const MagicApiException(message: 'Сбой после отправки');
        }
      },
    );
    await _tap(tester, find.byKey(const Key('subscription-discount-percent')));
    await tester.enterText(
      find.byKey(const Key('subscription-discount-value')),
      '20',
    );
    await tester.enterText(
      find.byKey(const Key('subscription-discount-reason')),
      'Семейная скидка',
    );
    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));

    expect(find.byKey(const Key('subscription-purchase-preview')), findsOne);
    expect(find.text('Получатель'), findsOne);
    expect(find.text('Плательщик'), findsOne);
    expect(
      _normalizedTexts(
        tester,
        find.byKey(const Key('subscription-purchase-preview')),
      ),
      contains('1 600 ₽'),
    );

    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));
    expect(submissions, hasLength(1));
    expect(find.text('Повторить'), findsOne);
    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));
    expect(submissions, hasLength(2));
    expect(
      submissions.first.identity.idempotencyKey,
      submissions.last.identity.idempotencyKey,
    );
    expect(
      submissions.first.purchase.issue.discount!.toJson(),
      submissions.last.purchase.issue.discount!.toJson(),
    );
  });

  testWidgets('overpayment survives preview and commit and is shown', (
    tester,
  ) async {
    PurchaseSubscriptionInput? previewInput;
    SubscriptionIssueSubmission? submission;
    await _openSheet(
      tester,
      onPreview: (input) async {
        previewInput = input;
        return SubscriptionPurchasePreview(
          recipientStudentId: _recipientId,
          payerStudentId: input.payerStudentId,
          fundingMode: input.fundingMode,
          currencyCode: 'RUB',
          finalPriceMinor: BigInt.from(800000),
          payerBalanceMinor: BigInt.zero,
          paidNowMinor: BigInt.from(900000),
          balanceAfterMinor: BigInt.from(100000),
          canCommit: true,
          shortageMinor: BigInt.zero,
          debtMinor: BigInt.zero,
          overpaymentMinor: BigInt.from(100000),
          previewToken: 'overpayment-preview',
        );
      },
      onSubmit: (value) async => submission = value,
    );
    final paymentAmount = find.byKey(
      const ValueKey<String>('subscription-payment-800000'),
    );

    await tester.enterText(paymentAmount, '9000');
    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));

    expect(previewInput?.paymentAmountMinor, BigInt.from(900000));
    final previewCard = find.byKey(const Key('subscription-purchase-preview'));
    expect(
      find.descendant(
        of: previewCard,
        matching: find.text('Переплата после покупки'),
      ),
      findsOneWidget,
    );
    expect(_normalizedTexts(tester, previewCard), contains('1 000 ₽'));

    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));

    expect(submission?.purchase.paymentAmountMinor, BigInt.from(900000));
    expect(submission?.preview.overpaymentMinor, BigInt.from(100000));
  });

  testWidgets('different payer requires a reason before preview', (
    tester,
  ) async {
    var previews = 0;
    final payerQueries = <String>[];
    await _openSheet(
      tester,
      searchPayers: (query) async {
        payerQueries.add(query);
        return [SearchableSelectItem(id: _payerId, label: 'Петров Пётр')];
      },
      onPreview: (input) async {
        previews++;
        return _preview(payerId: input.payerStudentId);
      },
      onSubmit: (_) async {},
    );
    await _tap(tester, find.byKey(const Key('subscription-payer')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('subscription-payer')),
        matching: find.byType(TextField),
      ),
      'Петров',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(payerQueries, contains('Петров'));
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('subscription-payer')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'Петров',
    );
    final payerMenu = tester.widget<DropdownMenu<String>>(
      find.descendant(
        of: find.byKey(const Key('subscription-payer')),
        matching: find.byType(DropdownMenu<String>),
      ),
    );
    expect(
      payerMenu.dropdownMenuEntries.map((entry) => entry.label),
      contains('Петров Пётр'),
    );
    expect(find.text('Петров Пётр'), findsWidgets);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(Scrollbar).last,
        matching: find.text('Петров Пётр'),
      ),
    );
    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));
    expect(find.text('Укажите причину оплаты с чужого счёта'), findsOne);
    expect(previews, 0);

    await tester.enterText(
      find.byKey(const Key('subscription-purchase-reason')),
      'Семейная оплата',
    );
    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));
    expect(previews, 1);
    expect(find.text('Петров Пётр'), findsWidgets);
  });

  testWidgets('fixed discount and installment schedule commit exact terms', (
    tester,
  ) async {
    PurchaseSubscriptionInput? previewInput;
    SubscriptionIssueSubmission? submission;
    await _openSheet(
      tester,
      onPreview: (input) async {
        previewInput = input;
        return _preview(
          mode: input.fundingMode,
          finalPriceMinor: BigInt.from(700000),
        );
      },
      onSubmit: (value) async => submission = value,
    );
    await _tap(tester, find.byKey(const Key('subscription-discount-fixed')));
    await tester.enterText(
      find.byKey(const Key('subscription-discount-value')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const Key('subscription-discount-reason')),
      'Фиксированная семейная скидка',
    );
    await _tap(
      tester,
      find.byKey(const Key('subscription-funding-installment')),
    );
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const Key('subscription-installment-count')),
        )
        .onChanged!(3);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('subscription-installment-preview')),
      findsOneWidget,
    );

    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));
    expect(previewInput, isNotNull);
    expect(previewInput!.fundingMode, SubscriptionFundingMode.installment);
    expect(previewInput!.issue.discount!.toJson(), {
      'type': 'fixed',
      'fixedMinor': '100000',
      'reason': 'Фиксированная семейная скидка',
    });
    expect(previewInput!.issue.installments, hasLength(3));
    expect(
      previewInput!.issue.installments.fold<BigInt>(
        BigInt.zero,
        (sum, installment) => sum + installment.amountMinor,
      ),
      BigInt.from(700000),
    );
    expect(
      previewInput!.issue.installments
          .map((installment) => installment.amountMinor)
          .toList(),
      [BigInt.from(233334), BigInt.from(233333), BigInt.from(233333)],
    );
    expect(find.text('Обязательство'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('subscription-issue-submit')));
    expect(submission, isNotNull);
    expect(submission!.purchase.toJson(), previewInput!.toJson());
  });
}
