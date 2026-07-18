import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'card_fake_api.dart';

/// #12: строка задачи раскрывается тапом — полный текст, автор, исполнитель,
/// срок (красным и с пометкой, если просрочен).
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
      leadTasks: [
        {
          'id': 'task-1',
          'title': 'Позвонить клиенту',
          'description': 'Обсудить расписание занятий и удобное время.',
          'status': 'open',
          'priority': 'high',
          'assignedName': 'Мария Петрова',
          'creatorName': 'Олег Сидоров',
          'dueAt': '2026-07-10T10:00:00.000Z',
          'createdAt': '2026-07-01T09:00:00.000Z',
        },
      ],
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Иван', 'custom_data': {}},
      statuses: const [],
    );

    // Вкладка «Задачи».
    await tester.tap(find.text('Задачи'));
    await tester.pumpAndSettle();

    expect(find.text('Позвонить клиенту'), findsOneWidget);
    // Свёрнутая строка не показывает детали.
    expect(find.text('Обсудить расписание занятий и удобное время.'), findsNothing);
    expect(find.text('Олег Сидоров'), findsNothing);

    await tester.tap(find.text('Позвонить клиенту'));
    await tester.pumpAndSettle();

    expect(
      find.text('Обсудить расписание занятий и удобное время.'),
      findsOneWidget,
    );
    expect(find.text('Олег Сидоров'), findsOneWidget); // Поставил
    expect(find.text('Мария Петрова'), findsOneWidget); // Исполнитель
    expect(find.textContaining('просрочена'), findsOneWidget); // срок в прошлом
    expect(find.textContaining('Создана'), findsOneWidget);
    expect(find.text('Высокий'), findsOneWidget); // приоритет

    // Повторный тап сворачивает обратно.
    await tester.tap(find.text('Позвонить клиенту'));
    await tester.pumpAndSettle();
    expect(find.text('Олег Сидоров'), findsNothing);
  });
}
