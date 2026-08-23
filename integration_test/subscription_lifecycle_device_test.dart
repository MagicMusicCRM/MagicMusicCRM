import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../test/features/crm/client_card/card_fake_api.dart';
import 'evidence_screenshot.dart';

const _studentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _issuedId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _newPackageId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('subscription list, cancel and replace remain in the card', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
      subscriptionPackages: const [
        {
          'id': _newPackageId,
          'name': 'Вокал — 12 часов',
          'unitCount': 12,
          'basePriceMinor': '1000000',
          'currencyCode': 'RUB',
          'active': true,
          'version': 7,
        },
      ],
      cancellationPreview: const {
        'issuedSubscriptionId': _issuedId,
        'expectedVersion': 4,
        'package': {
          'id': 'package-old',
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
          'lessons': <Map<String, dynamic>>[],
        },
        'warnings': [
          {
            'code': 'FUTURE_LESSONS_PRESERVED',
            'count': 2,
            'units': '2',
            'message': 'Будущие занятия сохранятся.',
          },
        ],
        'previewToken': 'cancel-preview',
        'expiresAt': '2026-08-07T12:15:00.000Z',
      },
      replacementPreview: const {
        'issuedSubscriptionId': _issuedId,
        'expectedVersion': 4,
        'oldPackageId': 'package-old',
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
        'warnings': <Map<String, dynamic>>[],
        'previewToken': 'replace-preview',
        'expiresAt': '2026-08-07T12:15:00.000Z',
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': _studentId, 'custom_data': <String, dynamic>{}},
      entityType: 'student',
      statuses: const [],
    );

    await _tapVisible(tester, find.text('Абонементы'));
    await captureEvidence(tester, 'subscription-active-card-actions');

    await _tapVisible(
      tester,
      find.byKey(const Key('subscription-cancel-$_issuedId')),
    );
    await _boundedFrames(tester);
    expect(find.text('Отменить абонемент'), findsOneWidget);
    await captureEvidence(tester, 'subscription-cancel-financial-impact');
    await tester.binding.handlePopRoute();
    await _boundedFrames(tester);

    await _tapVisible(
      tester,
      find.byKey(const Key('subscription-replace-$_issuedId')),
    );
    await _boundedFrames(tester);
    await _tapVisible(
      tester,
      find.byKey(const Key('issue-subscription-package-$_newPackageId')),
    );
    await _boundedFrames(tester);
    expect(find.text('Долг после замены'), findsOneWidget);
    await captureEvidence(tester, 'subscription-replace-financial-impact');
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _boundedFrames(tester);
}

Future<void> _boundedFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
