import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../crm/client_card/card_fake_api.dart';

const _student = <String, dynamic>{
  'id': 'student-1',
  'firstName': 'Анна',
  'lastName': 'Смирнова',
  'status': 'active',
  'branchId': 'branch-1',
  'branchName': 'Главный',
};

void main() {
  testWidgets('desktop owns one action per section and collapses finance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(role: 'manager', student: _student);

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
      find.byKey(const Key('client-section-jump-history_tasks')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('client-section-jump-progress')),
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

    for (final key in const [
      Key('payment-movements-expansion'),
      Key('payment-installments-expansion'),
    ]) {
      final expansion = tester.widget<ExpansionTile>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(ExpansionTile),
        ),
      );
      expect(expansion.initiallyExpanded, isFalse);
    }
  });

  testWidgets('lead subscription and homework actions live only in sections', (
    tester,
  ) async {
    final api = FakeCardApiClient(
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
      api: api,
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

    final subscriptions = find.text('Абонементы');
    await tester.ensureVisible(subscriptions);
    await tester.tap(subscriptions);
    await tester.pumpAndSettle();
    expect(find.text('Выдать абонемент'), findsOneWidget);

    final progress = find.text('Прогресс');
    await tester.ensureVisible(progress);
    await tester.tap(progress);
    await tester.pumpAndSettle();
    expect(find.text('Назначить ДЗ'), findsOneWidget);
  });
}
