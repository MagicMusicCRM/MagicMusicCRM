import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'card_fake_api.dart';

/// #13: бар действий ученика (Действия / Открыть в расписании / Отмена /
/// Сохранить) на телефонной ширине переносится Wrap'ом, а не переполняет
/// правый край, как раньше делал жёсткий Row.
void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('студенческий бар действий не переполняется на 360x690', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeCardApiClient(
      student: {
        'id': 'stu-1',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'status': 'Занимается',
        'customData': <String, dynamic>{},
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'stu-1', 'custom_data': {}},
      entityType: 'student',
      statuses: const [],
    );

    // Все кнопки бара на месте…
    expect(find.text('Действия'), findsOneWidget);
    expect(find.text('Открыть в расписании'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
    // …и вёрстка не бросила RenderFlex overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets('сохранение ученика шлёт PATCH без падений', (tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeCardApiClient(
      student: {
        'id': 'stu-1',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'status': 'Занимается',
        'customData': <String, dynamic>{},
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'stu-1', 'custom_data': {}},
      entityType: 'student',
      statuses: const [],
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(api.updateStudentBody, isNotNull);
    expect(api.updateStudentBody!['firstName'], 'Анна');
  });

  testWidgets('лид конвертируется только кнопкой выдачи абонемента', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      lead: {
        'id': 'lead-1',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'phone': '+79990000000',
        'statusId': null,
        'customData': <String, dynamic>{},
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Анна', 'custom_data': {}},
      statuses: const [],
    );

    expect(find.text('Выдать абонемент'), findsOneWidget);
    expect(find.text('Создать ученика'), findsNothing);
  });
}
