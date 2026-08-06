import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/models/types.dart';

import 'card_fake_api.dart';

/// #2 (контракт 6): PATCH /crm/leads/:id при сохранении карточки.
///
/// Сервер валидирует `statusId` как `@IsUUID()`. Легаси-маппер подставляет
/// 'new' лидам «Без статуса» — раньше карточка слала его на каждом сохранении
/// и весь PATCH (включая правки телефона) падал с 400 у ~22% лидов.
void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  const uuid = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  const statuses = <StatusRecord>[
    (uuid, 'Новый', Colors.amber),
    ('bbbbbbbb-cccc-4ddd-8eee-ffffffffffff', 'В работе', Colors.blue),
  ];

  Map<String, dynamic> rawLead({
    String? statusId,
    String? assignedTo,
    String? assignedName,
    Map<String, dynamic> customData = const {},
  }) => {
    'id': 'lead-1',
    'firstName': 'Иван',
    'lastName': 'Петров',
    'phone': '+79990000000',
    'statusId': statusId,
    'assignedTo': assignedTo,
    'assignedName': assignedName,
    'customData': customData,
  };

  testWidgets('лид без статуса: statusId и notes не уходят в PATCH', (
    tester,
  ) async {
    final api = FakeCardApiClient(lead: rawLead());
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Иван', 'custom_data': {}},
      statuses: statuses,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    final body = api.updateLeadBody;
    expect(body, isNotNull);
    // Легаси-фолбэк 'new' не должен превращаться в statusId.
    expect(body!.containsKey('statusId'), isFalse);
    // #10: блок «Заметки» удалён — поле notes больше не отправляется, сервер
    // сохраняет существующие заметки нетронутыми.
    expect(body.containsKey('notes'), isFalse);
    expect(body.containsKey('clearAssignedTo'), isFalse);
    expect(body['firstName'], 'Иван');
  });

  testWidgets('неизменённый UUID-статус тоже не отправляется', (tester) async {
    final api = FakeCardApiClient(lead: rawLead(statusId: uuid));
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Иван', 'custom_data': {}},
      statuses: statuses,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(api.updateLeadBody, isNotNull);
    expect(api.updateLeadBody!.containsKey('statusId'), isFalse);
  });

  testWidgets('выбранный в пикере статус уходит как UUID', (tester) async {
    final api = FakeCardApiClient(lead: rawLead());
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Иван', 'custom_data': {}},
      statuses: statuses,
    );

    // Статус-пикер — первый дропдаун вкладки «Инфо».
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(api.updateLeadBody, isNotNull);
    expect(api.updateLeadBody!['statusId'], uuid);
  });

  testWidgets('ответственный лида уходит канонически как assignedTo', (
    tester,
  ) async {
    final api = FakeCardApiClient(lead: rawLead());
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Иван', 'custom_data': {}},
      statuses: statuses,
    );

    final responsibleControl = find
        .ancestor(
          of: find.text('Ответственный'),
          matching: find.byType(InkWell),
        )
        .first;
    await tester.ensureVisible(responsibleControl);
    await tester.pumpAndSettle();
    await tester.tap(responsibleControl);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Мария');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мария Управляющая'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    final body = api.updateLeadBody!;
    expect(body['assignedTo'], '55555555-5555-4555-8555-555555555555');
    final customData = body['customDataPatch'] as Map<String, dynamic>;
    expect(customData.containsKey('responsibleUserId'), isFalse);
  });

  testWidgets('explicit lead responsible clear sends clearAssignedTo', (
    tester,
  ) async {
    const responsibleId = '55555555-5555-4555-8555-555555555555';
    final api = FakeCardApiClient(
      lead: rawLead(
        assignedTo: responsibleId,
        assignedName: 'Мария Управляющая',
        customData: {
          'responsible': 'Мария Управляющая',
          'responsibleUserId': responsibleId,
          'responsibleName': 'Мария Управляющая',
        },
      ),
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Иван', 'custom_data': {}},
      statuses: statuses,
    );

    final clear = find.byTooltip('Очистить');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    final body = api.updateLeadBody!;
    expect(body['clearAssignedTo'], isTrue);
    expect(body.containsKey('assignedTo'), isFalse);
    final customData = body['customDataPatch'] as Map<String, dynamic>;
    expect(customData.containsKey('responsible'), isFalse);
    expect(customData.containsKey('responsibleUserId'), isFalse);
    expect(customData.containsKey('responsibleName'), isFalse);
  });

  testWidgets('converted clear is mirrored to lead and student halves', (
    tester,
  ) async {
    const responsibleId = '55555555-5555-4555-8555-555555555555';
    final legacyResponsible = <String, dynamic>{
      'responsible': 'Мария Управляющая',
      'responsibleUserId': responsibleId,
      'responsibleName': 'Мария Управляющая',
    };
    final api = FakeCardApiClient(
      lead: rawLead(
        assignedTo: responsibleId,
        assignedName: 'Мария Управляющая',
        customData: legacyResponsible,
      ),
      student: {
        'id': 'student-1',
        'leadId': 'lead-1',
        'status': 'active',
        'firstName': 'Иван',
        'lastName': 'Петров',
        'phone': '+79990000000',
        'customData': legacyResponsible,
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'student-1'},
      entityType: 'student',
      statuses: statuses,
      settle: false,
    );

    final clear = find.byTooltip('Очистить');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final leadBody = api.updateLeadBody!;
    final studentBody = api.updateStudentBody!;
    expect(leadBody['clearAssignedTo'], isTrue);
    expect(studentBody['clearResponsible'], isTrue);
    for (final body in [leadBody, studentBody]) {
      final customData = body['customDataPatch'] as Map<String, dynamic>;
      expect(customData.containsKey('responsible'), isFalse);
      expect(customData.containsKey('responsibleUserId'), isFalse);
      expect(customData.containsKey('responsibleName'), isFalse);
    }
  });

  testWidgets(
    'source and key business fields stay primary without legacy duplicate',
    (tester) async {
      const sourceId = 'cccccccc-dddd-4eee-8fff-aaaaaaaaaaaa';
      final api = FakeCardApiClient(
        lead: {...rawLead(), 'sourceId': sourceId},
        sources: const [
          {'id': sourceId, 'displayName': 'Рекомендация', 'isActive': true},
        ],
        customFields: const [
          {
            'entity': 'leads',
            'key': 'requestType',
            'label': 'Тип обращения',
            'type': 'text',
          },
          {
            'entity': 'leads',
            'key': 'learningGoal',
            'label': 'Цель обучения',
            'type': 'text',
          },
          {
            'entity': 'leads',
            'key': 'level',
            'label': 'Уровень',
            'type': 'text',
          },
          {
            'entity': 'leads',
            'key': 'category',
            'label': 'Категория',
            'type': 'text',
          },
          {
            'entity': 'leads',
            'key': 'lessonType',
            'label': 'Тип обучения',
            'type': 'text',
          },
          {
            'entity': 'leads',
            'key': 'adSource',
            'label': 'Старый рекламный источник',
            'type': 'text',
          },
          {
            'entity': 'leads',
            'key': 'shirtSize',
            'label': 'Размер футболки',
            'type': 'text',
          },
        ],
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: const {'id': 'lead-1'},
        statuses: statuses,
      );

      for (final label in const [
        'Рекламный источник *',
        'Тип обращения',
        'Цель обучения',
        'Уровень',
        'Категория',
        'Тип обучения',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Старый рекламный источник'), findsNothing);
      expect(find.text('Размер футболки'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('client-custom-fields-expansion')),
      );
      await tester.tap(find.text('Дополнительные поля'));
      await tester.pumpAndSettle();

      expect(find.text('Размер футболки'), findsOneWidget);
      expect(find.text('Старый рекламный источник'), findsNothing);
    },
  );
}
