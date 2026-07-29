import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_sheet.dart';

typedef _IdempotentCall = ({
  String path,
  Object? data,
  MagicMutationIdentity identity,
});

class _IssueApiClient extends MagicApiClient {
  _IssueApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<_IdempotentCall> calls = [];

  @override
  Future<T> postIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls.add((path: path, data: data, identity: identity));
    if (path.endsWith('/subscriptions/issue')) {
      return <String, dynamic>{
            'subscription': {'id': '11111111-1111-4111-8111-111111111111'},
          }
          as T;
    }
    return <String, dynamic>{
          'payment': {'id': '22222222-2222-4222-8222-222222222222'},
        }
        as T;
  }
}

const _package = <String, dynamic>{
  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'name': 'Вокал — 8 занятий',
  'basePriceMinor': '800000',
  'currencyCode': 'RUB',
};

Future<void> _openIssueSheet(
  WidgetTester tester, {
  required SubscriptionIssueSubmit onSubmit,
  Size size = const Size(320, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showSubscriptionIssueFormSheet(
                context,
                package: _package,
                onSubmit: onSubmit,
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

String _normalized(String value) =>
    value.replaceAll('\u00a0', ' ').replaceAll('\u202f', ' ');

List<String> _textsInside(WidgetTester tester, Finder parent) => tester
    .widgetList<Text>(find.descendant(of: parent, matching: find.byType(Text)))
    .map((widget) => _normalized(widget.data ?? ''))
    .toList(growable: false);

void main() {
  test(
    'service sends canonical issue and payment DTOs with owned identities',
    () async {
      final api = _IssueApiClient();
      final service = MagicCrmService(api);
      const issueIdentity = MagicMutationIdentity(
        idempotencyKey: 'issue-stable-key',
        requestId: 'issue-stable-request',
      );
      const paymentIdentity = MagicMutationIdentity(
        idempotencyKey: 'payment-stable-key',
        requestId: 'payment-stable-request',
      );
      final dueAt = DateTime.utc(2026, 8, 1, 12);

      final issue = await service.issueSubscription(
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        input: IssueSubscriptionInput(
          packageId: _package['id']! as String,
          discount: SubscriptionDiscountInput.percent(
            basisPoints: 2000,
            reason: 'Летняя акция',
          ),
          installments: [
            SubscriptionInstallmentInput(
              dueAt: dueAt,
              amountMinor: BigInt.from(320000),
            ),
            SubscriptionInstallmentInput(
              dueAt: DateTime.utc(2026, 9, 1, 12),
              amountMinor: BigInt.from(320000),
            ),
          ],
          paymentMethod: SubscriptionPaymentMethod.cashless,
        ),
        identity: issueIdentity,
      );
      final issuedId =
          (issue['subscription'] as Map<String, dynamic>)['id']! as String;
      await service.recordSubscriptionPayment(
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        input: RecordSubscriptionPaymentInput(
          issuedSubscriptionId: issuedId,
          amountMinor: BigInt.from(100000),
          method: SubscriptionPaymentMethod.cashless,
          occurredAt: DateTime.utc(2026, 8, 1, 12, 30),
          currencyCode: 'RUB',
        ),
        identity: paymentIdentity,
      );

      expect(api.calls, hasLength(2));
      expect(api.calls.first.path, endsWith('/subscriptions/issue'));
      expect(api.calls.first.identity, same(issueIdentity));
      expect(api.calls.first.data, {
        'packageId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'discount': {
          'type': 'percent',
          'percent': 20,
          'reason': 'Летняя акция',
        },
        'installments': [
          {'dueAt': '2026-08-01T12:00:00.000Z', 'amountMinor': '320000'},
          {'dueAt': '2026-09-01T12:00:00.000Z', 'amountMinor': '320000'},
        ],
        'paymentMethod': 'cashless',
      });
      expect(api.calls.last.path, endsWith('/subscription-payments'));
      expect(api.calls.last.identity, same(paymentIdentity));
      expect(api.calls.last.data, {
        'issuedSubscriptionId': '11111111-1111-4111-8111-111111111111',
        'amountMinor': '100000',
        'method': 'cashless',
        'occurredAt': '2026-08-01T12:30:00.000Z',
        'currencyCode': 'RUB',
      });
    },
  );

  testWidgets(
    'narrow form calculates 8000 - 20%, exact installments and stable retry',
    (tester) async {
      final submissions = <SubscriptionIssueSubmission>[];
      await _openIssueSheet(
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

      expect(tester.takeException(), isNull);
      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-discount-percent')),
      );
      await tester.enterText(
        find.byKey(const Key('subscription-discount-value')),
        '20',
      );
      await tester.enterText(
        find.byKey(const Key('subscription-discount-reason')),
        'Семейная скидка',
      );
      await tester.pump();

      expect(
        _textsInside(tester, find.byKey(const Key('subscription-issue-final'))),
        contains('6 400 ₽'),
      );

      await _tapVisible(tester, find.text('Рассрочка'));
      await _tapVisible(tester, find.text('Внести оплату сейчас'));
      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-payment-cashless')),
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-issue-submit')),
      );
      await tester.pumpAndSettle();

      expect(submissions, hasLength(1));
      expect(find.byKey(const Key('subscription-issue-error')), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('subscription-discount-value')),
            )
            .enabled,
        isFalse,
      );

      await _tapVisible(tester, find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(submissions, hasLength(2));

      final first = submissions.first;
      final retry = submissions.last;
      expect(
        retry.issueIdentity.idempotencyKey,
        first.issueIdentity.idempotencyKey,
      );
      expect(retry.issueIdentity.requestId, first.issueIdentity.requestId);
      expect(
        retry.payment!.identity.idempotencyKey,
        first.payment!.identity.idempotencyKey,
      );
      expect(retry.payment!.occurredAt, first.payment!.occurredAt);
      expect(first.issue.toJson()['discount'], {
        'type': 'percent',
        'percent': 20,
        'reason': 'Семейная скидка',
      });
      expect(first.issue.toJson()['paymentMethod'], 'cashless');
      expect(first.payment!.amountMinor, BigInt.from(640000));

      final installments = first.issue.installments;
      expect(installments, hasLength(2));
      expect(
        installments.fold<BigInt>(
          BigInt.zero,
          (sum, item) => sum + item.amountMinor,
        ),
        BigInt.from(640000),
      );
      expect(
        installments.every((item) => item.amountMinor > BigInt.zero),
        isTrue,
      );
      expect(find.text('Условия абонемента'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fixed discount is serialized in minor units', (tester) async {
    SubscriptionIssueSubmission? captured;
    await _openIssueSheet(
      tester,
      size: const Size(800, 900),
      onSubmit: (submission) async => captured = submission,
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('subscription-discount-fixed')),
    );
    await tester.enterText(
      find.byKey(const Key('subscription-discount-value')),
      '1600',
    );
    await tester.enterText(
      find.byKey(const Key('subscription-discount-reason')),
      'Персональная скидка',
    );
    await tester.pump();
    expect(
      _textsInside(tester, find.byKey(const Key('subscription-issue-final'))),
      contains('6 400 ₽'),
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('subscription-issue-submit')),
    );
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured!.issue.toJson()['discount'], {
      'type': 'fixed',
      'fixedMinor': '160000',
      'reason': 'Персональная скидка',
    });
    expect(tester.takeException(), isNull);
  });
}
