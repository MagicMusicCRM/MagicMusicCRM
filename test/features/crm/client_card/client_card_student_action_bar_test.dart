import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/models/types.dart';

import 'card_fake_api.dart';

/// Бар ученика хранит только контекстные действия и на 360dp переносится
/// Wrap'ом без переполнения. Общего меню «Действия» больше нет.
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

    expect(find.text('Действия'), findsNothing);
    expect(find.text('Открыть в расписании'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
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

    final subscriptions = find.text('Абонементы');
    await tester.ensureVisible(subscriptions);
    await tester.tap(subscriptions);
    await tester.pumpAndSettle();
    expect(find.text('Выдать абонемент'), findsOneWidget);
    expect(find.text('Создать ученика'), findsNothing);
  });

  testWidgets('pending lead edits are saved before subscription conversion', (
    tester,
  ) async {
    const statusId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    final api = FakeCardApiClient(
      lead: {
        'id': 'lead-1',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'phone': '+79990000000',
        'statusId': null,
        'customData': <String, dynamic>{},
      },
      subscriptionPackages: const [
        {
          'id': 'package-1',
          'name': 'Демо — Фортепиано, 8 часов',
          'lessonsTotal': 8,
          'price': 24000,
        },
      ],
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Анна', 'custom_data': {}},
      statuses: const <StatusRecord>[(statusId, 'В работе', Colors.blue)],
    );

    final status = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(status);
    await tester.tap(status);
    await tester.pumpAndSettle();
    await tester.tap(find.text('В работе').last);
    await tester.pumpAndSettle();

    final subscriptions = find.text('Абонементы');
    await tester.ensureVisible(subscriptions);
    await tester.tap(subscriptions);
    await tester.pumpAndSettle();
    final issue = find.text('Выдать абонемент');
    await tester.ensureVisible(issue);
    await tester.tap(issue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Демо — Фортепиано, 8 часов'));
    await tester.pumpAndSettle();

    expect(api.updateLeadBody?['statusId'], statusId);
    expect(api.requests, [
      'PATCH /crm/leads/lead-1',
      'POST /crm/leads/lead-1/subscriptions/issue',
    ]);
    await tester.pump(const Duration(seconds: 4));
  });
}
