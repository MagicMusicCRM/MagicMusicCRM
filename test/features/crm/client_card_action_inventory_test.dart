import 'dart:io';

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
  test('client card tabs are named by surface', () {
    final clientCardSource = File(
      'lib/features/crm/presentation/client_card/client_card.dart',
    ).readAsStringSync();

    expect(clientCardSource, isNot(contains('client_card_tabs_a.dart')));
    expect(clientCardSource, isNot(contains('client_card_tabs_b.dart')));
    expect(clientCardSource, contains('client_card_header.dart'));
    expect(clientCardSource, contains('client_card_overview_tab.dart'));
    expect(clientCardSource, contains('client_card_tasks_tab.dart'));
    expect(clientCardSource, contains('client_card_collaboration_tabs.dart'));
    expect(clientCardSource, contains('client_card_presentation.dart'));
  });

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
      find.byKey(const Key('client-section-jump-documents')),
      findsNothing,
    );
    const orderedSections = [
      'overview',
      'contacts',
      'lessons',
      'subscriptions',
      'progress',
      'payments',
      'history_tasks',
    ];
    final tops = [
      for (final section in orderedSections)
        tester.getTopLeft(find.byKey(Key('client-section-jump-$section'))).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(
      find.descendant(
        of: find.byKey(const Key('client-section-jump-contacts')),
        matching: find.text('Контакты'),
      ),
      findsOneWidget,
    );
    expect(find.text('→ Контакты'), findsNothing);

    for (final section in const ['history_tasks', 'contacts']) {
      await tester.tap(find.byKey(Key('client-section-jump-$section')));
      await tester.pumpAndSettle();
      final target = find.byKey(Key('client-desktop-section-$section'));
      expect(target, findsOneWidget);
      expect(
        tester
            .getRect(target)
            .overlaps(
              tester.getRect(find.byKey(const Key('client-desktop-canvas'))),
            ),
        isTrue,
        reason: section,
      );
    }
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
    expect(find.text('Продать абонемент'), findsOneWidget);
    expect(find.text('Выдать абонемент'), findsNothing);

    final progress = find.text('Прогресс');
    await tester.ensureVisible(progress);
    await tester.tap(progress);
    await tester.pumpAndSettle();
    expect(find.text('Назначить ДЗ'), findsOneWidget);
  });
}
