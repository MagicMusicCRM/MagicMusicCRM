import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import '../crm/client_card/card_fake_api.dart';

const _studentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _issuedId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _newPackageId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

const _previewResponse = <String, dynamic>{
  'issuedSubscriptionId': _issuedId,
  'expectedVersion': 4,
  'oldPackageId': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'newPackage': {
    'id': _newPackageId,
    'version': 7,
    'name': 'Вокал — 12 часов',
    'unitCount': 12,
  },
  'usage': {
    'usedUnits': '3',
    'reservedLessonCount': 4,
    'reservedUnits': '4',
    'transferableReservationCount': 3,
    'transferableReservationUnits': '3',
    'releasedReservationCount': 1,
    'releasedReservationUnits': '1',
    'futureLessonCount': 4,
    'futureUnits': '4',
  },
  'financial': {
    'currencyCode': 'RUB',
    'oldFinalMinor': '800000',
    'newFinalMinor': '1000000',
    'actualPaidMinor': '800000',
    'obligationDeltaMinor': '200000',
    'resultingPosition': {'kind': 'debt', 'amountMinor': '200000'},
  },
  'warnings': [
    {
      'code': 'USED_UNITS_TRANSFERRED',
      'units': '3',
      'message': 'Использованные единицы будут перенесены.',
    },
    {
      'code': 'FUTURE_LESSONS_PRESERVED',
      'count': 4,
      'units': '4',
      'message': 'Будущие занятия и резервы сохранятся.',
    },
    {
      'code': 'RESERVATIONS_RELEASED_FOR_CAPACITY',
      'count': 1,
      'units': '1',
      'message': 'Один резерв будет освобождён из-за объёма пакета.',
    },
    {
      'code': 'ACTUAL_PAYMENTS_PRESERVED',
      'message': 'Фактические платежи останутся неизменными.',
    },
  ],
  'previewToken': 'signed-preview-token',
  'expiresAt': '2026-08-01T12:15:00.000Z',
};

const _replacementResponse = <String, dynamic>{
  'replacement': {
    'oldSubscriptionId': _issuedId,
    'oldSubscriptionVersion': 5,
    'newSubscriptionId': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
    'newSubscriptionVersion': 1,
    'newPackageId': _newPackageId,
    'newPackageVersion': 7,
    'usedUnits': '3',
    'transferredReservationCount': 3,
    'transferredReservationUnits': '3',
    'releasedReservationCount': 1,
    'releasedReservationUnits': '1',
    'deltaMinor': '200000',
    'positionKind': 'debt',
    'positionMinor': '200000',
    'ccy': 'RUB',
    'obligationFactId': 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
  },
  'replayed': false,
  'auditId': 'audit-replace',
  'eventId': 'event-replace',
};

const _activePackage = <String, dynamic>{
  'id': _newPackageId,
  'name': 'Вокал — 12 часов',
  'unitCount': 12,
  'basePriceMinor': '1000000',
  'currencyCode': 'RUB',
  'active': true,
  'version': 7,
};

const _archivedPackage = <String, dynamic>{
  'id': '99999999-9999-4999-8999-999999999999',
  'name': 'Архивный пакет',
  'unitCount': 6,
  'basePriceMinor': '500000',
  'currencyCode': 'RUB',
  'active': false,
  'archivedAt': '2026-07-01T00:00:00.000Z',
  'version': 3,
};

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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
  setUpAll(() => initializeDateFormatting('ru'));

  test('typed service preserves exact preview and confirm contracts', () async {
    final api = FakeCardApiClient(
      replacementPreview: _previewResponse,
      replacementResult: _replacementResponse,
    );
    final service = MagicCrmService(api);
    const identity = MagicMutationIdentity(
      idempotencyKey: 'replace-stable-key',
      requestId: 'replace-stable-request',
    );

    final preview = await service.previewSubscriptionReplacement(
      _studentId,
      issuedSubscriptionId: _issuedId,
      newPackageId: _newPackageId,
    );
    final result = await service.replaceSubscription(
      _studentId,
      issuedSubscriptionId: _issuedId,
      input: ReplaceSubscriptionInput(
        expectedVersion: preview.expectedVersion,
        previewToken: preview.previewToken,
        reason: 'client.requested_change',
      ),
      identity: identity,
    );

    expect(preview.newPackage.name, 'Вокал — 12 часов');
    expect(preview.usage.usedUnits, '3');
    expect(preview.usage.futureLessonCount, 4);
    expect(preview.usage.releasedReservationCount, 1);
    expect(
      preview.financial.resultingPosition.kind,
      SubscriptionFinancialPositionKind.debt,
    );
    expect(
      preview.financial.resultingPosition.amountMinor,
      BigInt.from(200000),
    );
    expect(preview.warnings, hasLength(4));
    expect(api.postRequests.single.path, endsWith('/replace/preview'));
    expect(api.postRequests.single.data, {'newPackageId': _newPackageId});

    expect(api.idempotentRequests.single.path, endsWith('/replace'));
    expect(api.idempotentRequests.single.identity, same(identity));
    expect(api.idempotentRequests.single.data, {
      'expectedVersion': 4,
      'previewToken': 'signed-preview-token',
      'confirm': true,
      'reason': 'client.requested_change',
    });
    expect(result.replacement.newPackageId, _newPackageId);
    expect(result.replacement.positionMinor, BigInt.from(200000));
    expect(result.replayed, isFalse);
  });

  testWidgets(
    'active client-card subscription previews warnings and retries replace stably',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeCardApiClient(
        student: const {
          'id': _studentId,
          'firstName': 'Анна',
          'lastName': 'Смирнова',
          'status': 'active',
          'customData': <String, dynamic>{},
        },
        studentSubscriptions: const [
          {
            'id': _issuedId,
            'studentId': _studentId,
            'lessonsTotal': 8,
            'lessonsUsed': 3,
            'status': 'active',
            'packageName': 'Вокал — 8 часов',
            'packagePrice': 8000,
            'paidAmount': 8000,
          },
        ],
        subscriptionPackages: const [_activePackage, _archivedPackage],
        replacementPreview: _previewResponse,
        replacementResult: _replacementResponse,
        replacementFailures: 1,
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: const {'id': _studentId, 'custom_data': <String, dynamic>{}},
        entityType: 'student',
        statuses: const [],
      );

      final replaceAction = find.byKey(
        const Key('subscription-replace-$_issuedId'),
      );
      await _tapVisible(tester, replaceAction);
      await _pumpFrames(tester);

      expect(find.text('Новый абонемент'), findsOneWidget);
      expect(find.text('Вокал — 12 часов'), findsOneWidget);
      expect(find.text('Архивный пакет'), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const Key('issue-subscription-package-$_newPackageId')),
      );
      await _pumpFrames(tester);

      expect(find.byKey(const Key('subscription-replace-old')), findsOneWidget);
      expect(find.byKey(const Key('subscription-replace-new')), findsOneWidget);
      expect(find.text('Использовано'), findsOneWidget);
      expect(find.text('Будущие занятия'), findsOneWidget);
      expect(find.text('Долг после замены'), findsOneWidget);
      expect(
        _normalizedTexts(
          tester,
          find.byKey(const Key('subscription-replace-financial')),
        ),
        contains('2 000 ₽'),
      );
      expect(
        find.text('Фактические платежи останутся неизменными.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final reason = find.byKey(const Key('subscription-replace-reason'));
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'client.requested_change');
      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-replace-confirmation')),
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-replace-submit')),
      );
      await _pumpFrames(tester);

      expect(api.idempotentRequests, hasLength(1));
      expect(
        find.byKey(const Key('subscription-replace-error')),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsOneWidget);
      expect(tester.widget<TextFormField>(reason).enabled, isFalse);

      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-replace-submit')),
      );
      await _pumpFrames(tester);

      expect(api.idempotentRequests, hasLength(2));
      final first = api.idempotentRequests.first;
      final retry = api.idempotentRequests.last;
      expect(retry.data, first.data);
      expect(retry.identity.idempotencyKey, first.identity.idempotencyKey);
      expect(retry.identity.requestId, first.identity.requestId);
      expect(first.data, {
        'expectedVersion': 4,
        'previewToken': 'signed-preview-token',
        'confirm': true,
        'reason': 'client.requested_change',
      });
      expect(api.studentCardLoadCount, 2);
      expect(find.text('Абонемент заменён'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
