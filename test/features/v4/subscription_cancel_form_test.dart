import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import '../crm/client_card/card_fake_api.dart';

const _studentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _issuedId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const _previewResponse = <String, dynamic>{
  'issuedSubscriptionId': _issuedId,
  'expectedVersion': 4,
  'package': {
    'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'name': 'Вокал — 8 часов',
    'unitCount': 8,
  },
  'usage': {'usedUnits': '3'},
  'financial': {
    'currencyCode': 'RUB',
    'finalMinor': '640000',
    'actualPaidMinor': '500000',
    'writeoffMinor': '160000',
    'balanceMinor': '-140000',
  },
  'future': {
    'lessonCount': 2,
    'reservedLessonCount': 2,
    'reservedUnits': '2',
    'lessons': [
      {
        'lessonId': '11111111-1111-4111-8111-111111111111',
        'scheduledAt': '2026-08-05T12:00:00.000Z',
        'units': '1',
        'reserved': true,
      },
      {
        'lessonId': '22222222-2222-4222-8222-222222222222',
        'scheduledAt': '2026-08-12T12:00:00.000Z',
        'units': '1',
        'reserved': true,
      },
    ],
  },
  'warnings': [
    {
      'code': 'FUTURE_LESSONS_PRESERVED',
      'count': 2,
      'units': '2',
      'message': 'Будущие занятия сохранятся.',
    },
    {
      'code': 'ACTUAL_PAYMENTS_PRESERVED',
      'message': 'Платежи и списания останутся неизменными.',
    },
  ],
  'previewToken': 'signed-cancel-preview',
  'expiresAt': '2026-08-01T12:15:00.000Z',
};

const _cancellationResponse = <String, dynamic>{
  'cancellation': {
    'issuedSubscriptionId': _issuedId,
    'version': 5,
    'status': 'cancelled',
    'releasedReservationCount': 2,
    'releasedReservationUnits': '2',
    'futureLessonCount': 2,
  },
  'replayed': false,
  'auditId': 'audit-cancel',
  'eventId': 'event-cancel',
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

  test(
    'typed service preserves exact cancel preview and confirm contracts',
    () async {
      final api = FakeCardApiClient(
        cancellationPreview: _previewResponse,
        cancellationResult: _cancellationResponse,
      );
      final service = MagicCrmService(api);
      const identity = MagicMutationIdentity(
        idempotencyKey: 'cancel-stable-key',
        requestId: 'cancel-stable-request',
      );

      final preview = await service.previewSubscriptionCancellation(
        _studentId,
        issuedSubscriptionId: _issuedId,
      );
      final result = await service.cancelSubscription(
        _studentId,
        issuedSubscriptionId: _issuedId,
        input: CancelSubscriptionInput(
          expectedVersion: preview.expectedVersion,
          previewToken: preview.previewToken,
          reason: 'client.requested_cancel',
        ),
        identity: identity,
      );

      expect(preview.package.name, 'Вокал — 8 часов');
      expect(preview.usage.usedUnits, '3');
      expect(preview.financial.actualPaidMinor, BigInt.from(500000));
      expect(preview.financial.writeoffMinor, BigInt.from(160000));
      expect(preview.financial.balanceMinor, BigInt.from(-140000));
      expect(preview.future.lessons, hasLength(2));
      expect(api.postRequests.single.path, endsWith('/cancel/preview'));
      expect(api.postRequests.single.data, isEmpty);

      expect(api.idempotentRequests.single.path, endsWith('/cancel'));
      expect(api.idempotentRequests.single.identity, same(identity));
      expect(api.idempotentRequests.single.data, {
        'expectedVersion': 4,
        'previewToken': 'signed-cancel-preview',
        'confirm': true,
        'reason': 'client.requested_cancel',
      });
      expect(result.cancellation.status, 'cancelled');
      expect(result.cancellation.releasedReservationCount, 2);
      expect(result.cancellation.futureLessonCount, 2);
    },
  );

  testWidgets(
    'active client-card subscription previews impact and retries cancel stably',
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
            'packagePrice': 6400,
            'paidAmount': 5000,
          },
        ],
        cancellationPreview: _previewResponse,
        cancellationResult: _cancellationResponse,
        cancellationFailures: 1,
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: const {'id': _studentId, 'custom_data': <String, dynamic>{}},
        entityType: 'student',
        statuses: const [],
      );

      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-cancel-$_issuedId')),
      );
      await _pumpFrames(tester);

      expect(find.text('Отменить абонемент'), findsOneWidget);
      expect(
        find.byKey(const Key('subscription-cancel-financial')),
        findsOneWidget,
      );
      expect(find.text('Фактически оплачено'), findsOneWidget);
      expect(find.text('Списано за занятия'), findsOneWidget);
      expect(find.text('Текущий баланс'), findsOneWidget);
      expect(
        _normalizedTexts(
          tester,
          find.byKey(const Key('subscription-cancel-financial')),
        ),
        containsAll(<String>['5 000 ₽', '1 600 ₽', '-1 400 ₽']),
      );
      expect(find.text('Будущие занятия сохранятся'), findsWidgets);
      expect(find.textContaining('Покрытие будущих резервов'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final reason = find.byKey(const Key('subscription-cancel-reason'));
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'client.requested_cancel');
      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-cancel-confirmation')),
      );
      await tester.binding.handlePopRoute();
      await _pumpFrames(tester);
      expect(find.text('Сохранить изменения?'), findsOneWidget);
      await tester.tap(find.text('Остаться'));
      await _pumpFrames(tester);
      expect(find.text('Отменить абонемент'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(reason).controller!.text,
        'client.requested_cancel',
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-cancel-submit')),
      );
      await _pumpFrames(tester);

      expect(api.idempotentRequests, hasLength(1));
      expect(
        find.byKey(const Key('subscription-cancel-error')),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsOneWidget);
      expect(tester.widget<TextFormField>(reason).enabled, isFalse);

      await _tapVisible(
        tester,
        find.byKey(const Key('subscription-cancel-submit')),
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
        'previewToken': 'signed-cancel-preview',
        'confirm': true,
        'reason': 'client.requested_cancel',
      });
      expect(api.studentCardLoadCount, 2);
      expect(find.text('Абонемент отменён'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
