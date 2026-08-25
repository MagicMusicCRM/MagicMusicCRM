import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card_fake_api.dart';

/// #2 (контракт 6): PATCH /crm/leads/:id при сохранении карточки.
///
/// Сервер валидирует `statusId` как `@IsUUID()`. Легаси-маппер подставляет
/// 'new' лидам «Без статуса» — раньше карточка слала его на каждом сохранении
/// и весь PATCH (включая правки телефона) падал с 400 у ~22% лидов.
void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  test('client card data responsibilities have semantic parts', () {
    final owner = File(
      'lib/features/crm/presentation/client_card/client_card.dart',
    ).readAsStringSync();
    expect(owner, isNot(contains("part 'client_card_data.dart';")));
    for (final part in const [
      'client_card_internal_context.dart',
      'client_card_counterpart_resolution.dart',
      'client_card_loaders.dart',
      'client_card_realtime.dart',
      'client_card_persistence.dart',
    ]) {
      expect(owner, contains("part '$part';"));
    }
  });

  test('client card editor responsibilities have semantic parts', () {
    final owner = File(
      'lib/features/crm/presentation/client_card/client_card.dart',
    ).readAsStringSync();
    expect(owner, isNot(contains("part 'client_card_editors.dart';")));
    for (final part in const [
      'client_card_custom_fields.dart',
      'client_card_custom_field_inputs.dart',
      'client_card_moderation.dart',
      'client_card_contact_editors.dart',
      'client_card_assignment_editors.dart',
      'client_card_comment_editor.dart',
      'client_card_family_access.dart',
    ]) {
      expect(owner, contains("part '$part';"));
    }
  });

  testWidgets('blacklist captures a reason and mutates the open lead', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    final api = FakeCardApiClient(
      lead: const {
        'id': 'lead-1',
        'firstName': 'Иван',
        'lastName': 'Петров',
        'phone': '+79990000000',
        'blacklisted': false,
      },
    );
    await pumpClientCard(tester, api: api, seed: const {'id': 'lead-1'});

    final toggle = find.widgetWithText(SwitchListTile, 'Чёрный список');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'оскорбления в чате');
    await tester.tap(find.widgetWithText(FilledButton, 'В чёрный список'));
    await tester.pumpAndSettle();

    expect(
      api.patchRequests,
      contains(
        predicate<CardPostCall>(
          (request) =>
              request.path == '/crm/leads/lead-1/blacklist' &&
              request.data['blacklisted'] == true &&
              request.data['reason'] == 'оскорбления в чате',
        ),
      ),
    );
    expect(find.text('Клиент в чёрном списке'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

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
    final statusPicker = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(statusPicker);
    await tester.tap(statusPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(api.updateLeadBody, isNotNull);
    expect(api.updateLeadBody!['statusId'], uuid);
  });

  testWidgets('сохранение карточки сбрасывает все кеши доски лидов', (
    tester,
  ) async {
    final api = FakeCardApiClient(lead: rawLead());
    final container = ProviderContainer(
      overrides: [
        magicApiClientProvider.overrideWithValue(api),
        crmRealtimeProvider.overrideWith(
          (ref) => const Stream<CrmChangedEvent>.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      leadBoardProvider(const LeadBoardFilters(q: 'UAT')),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container.read(
      leadBoardProvider(const LeadBoardFilters(q: 'UAT')).future,
    );

    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Иван', 'custom_data': {}},
      statuses: statuses,
      container: container,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(api.leadBoardQueries.where((query) => query == 'UAT').length, 2);
  });

  test('закрытая доска не возвращается из устаревшего family-кеша', () async {
    final api = FakeCardApiClient();
    final container = ProviderContainer(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final provider = leadBoardProvider(const LeadBoardFilters(q: 'UAT'));

    final first = container.listen(provider, (_, _) {});
    await container.read(provider.future);
    first.close();
    await container.pump();
    final second = container.listen(provider, (_, _) {});
    addTearDown(second.close);
    await container.read(provider.future);

    expect(api.leadBoardQueries, ['UAT', 'UAT']);
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

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SearchablePickerField &&
              widget.label == 'Рекламный источник *',
        ),
        findsOneWidget,
      );
      for (final label in const [
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

  testWidgets('card writes canonical typed values with definition ids', (
    tester,
  ) async {
    const definitionId = '30000000-0000-4000-8000-000000000777';
    final api = FakeCardApiClient(
      lead: rawLead(customData: const {'favoriteColor': 'Синий'}),
      customFields: const [
        {
          'id': definitionId,
          'entityType': 'lead',
          'key': 'favoriteColor',
          'label': 'Любимый цвет',
          'valueType': 'text',
          'placements': ['edit', 'card'],
        },
      ],
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'lead-1'},
      statuses: statuses,
    );

    await tester.ensureVisible(
      find.byKey(const Key('client-custom-fields-expansion')),
    );
    await tester.tap(find.text('Дополнительные поля'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            widget.key.toString().contains('leads-favoriteColor-'),
      ),
      'Зелёный',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(api.updateLeadBody?['customFields'], [
      {'definitionId': definitionId, 'value': 'Зелёный'},
    ]);
  });

  testWidgets('card placement is read-only and configured widths are honored', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeCardApiClient(
      lead: rawLead(
        customData: const {'favoriteColor': 'Синий', 'campaignCode': 'A-17'},
      ),
      customFields: const [
        {
          'entityType': 'lead',
          'key': 'favoriteColor',
          'label': 'Любимый цвет',
          'valueType': 'text',
          'width': 'half',
          'placements': ['card'],
        },
        {
          'entityType': 'lead',
          'key': 'campaignCode',
          'label': 'Код кампании',
          'valueType': 'text',
          'width': 'third',
          'placements': ['edit', 'card'],
        },
      ],
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'lead-1'},
      statuses: statuses,
    );

    await tester.ensureVisible(
      find.byKey(const Key('client-custom-fields-expansion')),
    );
    await tester.tap(find.text('Дополнительные поля'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('custom-field-readonly-favoriteColor')),
      findsOneWidget,
    );
    expect(find.text('Синий'), findsOneWidget);
    final half = tester.getSize(
      find.byKey(const ValueKey('custom-field-layout-favoriteColor')),
    );
    final third = tester.getSize(
      find.byKey(const ValueKey('custom-field-layout-campaignCode')),
    );
    expect(half.width, closeTo(third.width * 1.5, 5));
  });
}
