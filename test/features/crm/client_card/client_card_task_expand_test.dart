import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'card_fake_api.dart';

/// Client history uses the same canonical shared-task detail and audit flow.
void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('задача в карточке лида раскрывается по тапу', (tester) async {
    final api = FakeCardApiClient(
      lead: {
        'id': 'lead-1',
        'firstName': 'Иван',
        'statusId': null,
        'customData': <String, dynamic>{},
      },
      sharedTasks: [
        {
          'id': '11111111-1111-4111-8111-111111111111',
          'title': 'Позвонить клиенту',
          'body': 'Обсудить расписание занятий и удобное время.',
          'state': 'open',
          'version': 1,
          'startAt': '2026-08-10T10:00:00.000Z',
          'allDay': false,
          'audiences': [
            {'type': 'allBranches'},
          ],
          'linkedEntity': {'type': 'lead', 'id': 'lead-1'},
        },
      ],
      sharedTaskHistory: const [
        {
          'id': 'history-1',
          'action': 'workflow.shared_task_created',
          'actorName': 'Олег Сидоров',
          'occurredAt': '2026-08-01T09:00:00.000Z',
        },
      ],
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Иван', 'custom_data': {}},
      statuses: const [],
    );

    final historyAndTasks = find.text('История и задачи');
    await tester.ensureVisible(historyAndTasks);
    await tester.tap(historyAndTasks);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Задачи'));
    await tester.pumpAndSettle();

    expect(find.text('Позвонить клиенту'), findsOneWidget);
    expect(
      find.text('Обсудить расписание занятий и удобное время.'),
      findsOneWidget,
    );
    expect(find.text('Олег Сидоров'), findsNothing);

    final task = find.text('Позвонить клиенту');
    await tester.ensureVisible(task);
    await tester.pumpAndSettle();
    await tester.tap(task);
    await tester.pumpAndSettle();

    expect(find.text('История'), findsWidgets);
    expect(find.text('Задача создана'), findsOneWidget);
    expect(find.textContaining('Олег Сидоров'), findsOneWidget);
    expect(find.text('Лид'), findsOneWidget);
    expect(find.byKey(const Key('shared-task-linked-entity')), findsOneWidget);
  });
}
