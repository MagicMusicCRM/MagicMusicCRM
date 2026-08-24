import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/crm_configuration_workspace.dart';

class ConfigurationTestApi extends MagicApiClient {
  ConfigurationTestApi({
    required this.role,
    required this.capabilities,
    this.baseVersion = 1,
    Map<String, dynamic>? snapshot,
  }) : snapshot = snapshot ?? _defaultSnapshot,
       super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String role;
  final List<String> capabilities;
  final Map<String, dynamic> snapshot;
  int baseVersion;
  int configurationReads = 0;
  final List<String?> configurationScopeReads = [];
  int publishes = 0;
  int draftSaves = 0;
  int rollbacks = 0;
  int sourceCreates = 0;
  Map<String, dynamic>? submittedSnapshot;
  final List<Map<String, dynamic>> sources = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/access/me') {
      return <String, dynamic>{
            'accountId': '10000000-0000-4000-8000-000000000001',
            'role': role,
            'accessVersion': 1,
            'capabilities': capabilities,
            'scopes': const {'client': 'branch', 'schedule': 'branch'},
          }
          as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': const [
              {'id': '20000000-0000-4000-8000-000000000001', 'name': 'Сокол'},
            ],
          }
          as T;
    }
    if (path == '/crm/client-config/sources') {
      return <String, dynamic>{'items': sources} as T;
    }
    if (path == '/crm/configuration/draft') {
      configurationScopeReads.add(queryParameters?['branchId']?.toString());
      configurationReads++;
      return <String, dynamic>{
            'baseVersion': baseVersion,
            'dirty': false,
            'snapshot': snapshot,
          }
          as T;
    }
    if (path == '/crm/configuration/revisions') {
      return <String, dynamic>{
            'items': const [
              {'id': 'revision-1', 'version': 1, 'reason': 'Базовая версия'},
              {'id': 'revision-0', 'version': 0, 'reason': 'Исходная версия'},
            ],
          }
          as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/configuration/preview') {
      submittedSnapshot = Map<String, dynamic>.from(
        (data as Map)['snapshot'] as Map,
      );
      return <String, dynamic>{
            'valid': true,
            'blockingIssues': const [],
            'affectedScreens': const ['lead.create'],
            'changes': const {
              'fieldsCreated': 0,
              'fieldsUpdated': 1,
              'fieldsArchived': 0,
              'settingsChanged': 0,
              'settlementTypesChanged': 1,
              'compensationRulesChanged': 1,
            },
            'warnings': const [
              'Новые правила применятся только к будущим решениям.',
            ],
          }
          as T;
    }
    if (path == '/crm/client-config/sources') {
      final payload = Map<String, dynamic>.from(data! as Map);
      sourceCreates++;
      final source = <String, dynamic>{
        'id': 'source-$sourceCreates',
        'canonicalName': payload['canonicalName'],
        'displayName': payload['displayName'],
        'isActive': true,
        'isSystem': false,
        'version': 1,
      };
      sources.add(source);
      return source as T;
    }
    if (path == '/crm/configuration/publish') {
      publishes++;
      baseVersion++;
      return <String, dynamic>{'version': baseVersion} as T;
    }
    if (path == '/crm/configuration/rollback') {
      rollbacks++;
      return <String, dynamic>{'version': 2, 'rollbackFromVersion': 0} as T;
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/crm/client-config/sources/')) {
      final id = path.split('/').last;
      final source = sources.firstWhere((item) => item['id'] == id);
      final payload = Map<String, dynamic>.from(data! as Map);
      if (payload['canonicalName'] != null) {
        source['canonicalName'] = payload['canonicalName'];
      }
      if (payload['displayName'] != null) {
        source['displayName'] = payload['displayName'];
      }
      if (payload['isActive'] != null) {
        source['isActive'] = payload['isActive'];
      }
      source['version'] = (source['version'] as int) + 1;
      return source as T;
    }
    throw StateError('Unexpected PATCH $path');
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/crm/client-config/sources/')) {
      final id = path.split('/').last;
      final source = sources.firstWhere((item) => item['id'] == id);
      source['isActive'] = false;
      source['version'] = (source['version'] as int) + 1;
      return source as T;
    }
    throw StateError('Unexpected DELETE $path');
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/configuration/draft') {
      draftSaves++;
      submittedSnapshot = Map<String, dynamic>.from(
        (data as Map)['snapshot'] as Map,
      );
      return <String, dynamic>{'saved': true} as T;
    }
    throw StateError('Unexpected PUT $path');
  }

  static const _defaultSnapshot = <String, dynamic>{
    'categories': [
      {'key': 'general', 'label': 'Основное', 'order': 0, 'active': true},
    ],
    'fields': [
      {
        'id': '30000000-0000-4000-8000-000000000000',
        'visibility': {'lead': true, 'student': true},
        'key': 'sourceId',
        'label': 'Рекламный источник',
        'valueType': 'select',
        'required': true,
        'active': true,
        'system': true,
        'categoryKey': 'general',
        'order': 0,
        'width': 'half',
        'placements': ['create', 'edit', 'card', 'table'],
        'options': <String>[],
      },
      {
        'id': '30000000-0000-4000-8000-000000000001',
        'visibility': {'lead': true, 'student': true},
        'key': 'goal',
        'label': 'Цель обучения',
        'valueType': 'text',
        'required': false,
        'active': true,
        'system': false,
        'categoryKey': 'general',
        'order': 1,
        'width': 'full',
        'placements': ['create', 'edit', 'card'],
        'options': <String>[],
      },
    ],
    'optionSets': <Map<String, dynamic>>[],
    'businessSettings': [
      {
        'key': 'payment_reminder_days',
        'label': 'Напоминание об оплате',
        'valueType': 'integer',
        'unit': 'дн.',
        'min': 0,
        'max': 60,
        'value': 3,
        'branchOverridable': true,
      },
    ],
    'lessonSettlementTypes': [
      {
        'stableKey': 'lesson',
        'label': 'Занятие',
        'colorToken': 'success',
        'hourShareBasisPoints': 10000,
        'allowedContexts': ['settle'],
        'active': true,
        'order': 0,
      },
      {
        'stableKey': 'free_lesson',
        'label': 'Бесплатное занятие',
        'colorToken': 'warning',
        'hourShareBasisPoints': 0,
        'allowedContexts': ['cancel', 'reschedule', 'settle'],
        'active': true,
        'order': 1,
      },
    ],
    'teacherCompensationRules': [
      {
        'stableKey': 'none',
        'label': 'Не оплачивать',
        'mode': 'none',
        'value': '0',
        'active': true,
        'order': 0,
      },
      {
        'stableKey': 'standard',
        'label': 'Полная стандартная ставка',
        'mode': 'standard',
        'value': '0',
        'active': true,
        'order': 1,
      },
    ],
  };
}

Future<void> _pump(
  WidgetTester tester,
  ConfigurationTestApi api, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: CrmConfigurationRouteScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('director can publish the untouched baseline as version one', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      baseVersion: 0,
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
    );
    await _pump(tester, api);

    expect(find.text('Начальная настройка · версия 0'), findsOneWidget);
    final publish = find.byKey(const ValueKey('configuration-publish'));
    expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);
    await tester.tap(publish);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина публикации *'),
      'Первая настройка школы',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать'));
    await tester.pumpAndSettle();

    expect(api.publishes, 1);
    expect(api.baseVersion, 1);
    expect(find.text('Опубликовано · версия 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('director manages sources only inside field options', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
    );
    api.sources.add({
      'id': 'source-app',
      'canonicalName': 'app',
      'displayName': 'Приложение',
      'isActive': true,
      'isSystem': true,
      'version': 1,
    });
    await _pump(tester, api, size: const Size(900, 900));

    expect(find.text('Источники клиентов'), findsNothing);
    await tester.tap(find.text('Варианты для полей'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рекламный источник'));
    await tester.pumpAndSettle();
    expect(find.text('Приложение'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('client-source-menu-source-app')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('add-client-source')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('client-source-name')),
      'Рекомендация',
    );
    await tester.tap(find.byKey(const ValueKey('save-client-source')));
    await tester.pumpAndSettle();

    expect(api.sourceCreates, 1);
    expect(find.text('Рекомендация'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('client-source-menu-source-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('client-source-name')),
      'По рекомендации',
    );
    await tester.tap(find.byKey(const ValueKey('save-client-source')));
    await tester.pumpAndSettle();
    expect(find.text('По рекомендации'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('client-source-menu-source-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Архивировать'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Архивировать'));
    await tester.pumpAndSettle();
    expect(find.textContaining('В архиве'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('client-source-menu-source-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Восстановить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('В архиве'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('director edits a draft and publishes through impact preview', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
    );
    await _pump(tester, api);

    expect(find.text('Поля и категории'), findsOneWidget);
    expect(find.text('Варианты для полей'), findsOneWidget);
    expect(find.text('Бизнес-параметры'), findsOneWidget);
    expect(find.text('Вся школа'), findsOneWidget);

    await tester.tap(find.byTooltip('Добавить категорию'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Название *'),
      'Маркетинг',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Стабильный ключ *'),
      'marketing',
    );
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('configuration-publish')));
    await tester.pumpAndSettle();
    expect(find.text('Предпросмотр публикации'), findsOneWidget);
    final wireFields = (api.submittedSnapshot!['fields'] as List).cast<Map>();
    expect(
      wireFields
          .where((field) => field['key'] == 'goal')
          .map((field) => field['entityType']),
      containsAll(<String>['lead', 'student']),
    );
    expect(
      wireFields.every((field) => !field.containsKey('visibility')),
      isTrue,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина публикации *'),
      'Настроили карточку лида',
    );
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    expect(api.publishes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('director renames reorders and archives an unused category', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
      snapshot: {
        ...ConfigurationTestApi._defaultSnapshot,
        'categories': const [
          {'key': 'general', 'label': 'Основное', 'order': 0, 'active': true},
          {
            'key': 'marketing',
            'label': 'Маркетинг',
            'order': 1,
            'active': true,
          },
        ],
      },
    );
    await _pump(tester, api);

    await tester.tap(find.byTooltip('Изменить категорию').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Название *'),
      'Маркетинг и реклама',
    );
    await tester.tap(find.byKey(const ValueKey('category-active')));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Маркетинг и реклама'), findsOneWidget);
    expect(find.text('marketing · в архиве'), findsOneWidget);

    await tester.tap(find.byTooltip('Выше').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('configuration-publish')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина публикации *'),
      'Упорядочили категории',
    );
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    final categories = (api.submittedSnapshot!['categories'] as List)
        .cast<Map>();
    expect(categories.first['key'], 'marketing');
    expect(categories.first['label'], 'Маркетинг и реклама');
    expect(categories.first['active'], isFalse);
    expect(categories.first['order'], 0);
  });

  testWidgets('field editor exposes all types widths and placements', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
    );
    await _pump(tester, api);

    await tester.tap(find.text('Цель обучения'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    for (final entry in const {
      'text': 'Текст',
      'textarea': 'Многострочный текст',
      'number': 'Число',
      'money': 'Деньги',
      'duration': 'Длительность',
      'boolean': 'Флажок',
      'toggle': 'Переключатель',
      'date': 'Дата',
      'datetime': 'Дата и время',
      'select': 'Один вариант',
      'radio': 'Радиокнопки',
      'multi_select': 'Несколько вариантов',
      'checkbox_group': 'Группа флажков',
      'email': 'Почта',
      'phone': 'Телефон',
      'url': 'Ссылка',
    }.entries) {
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('field-type')),
      );
      dropdown.onChanged!(entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsWidgets, reason: entry.key);
    }
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('field-type')),
        )
        .onChanged!('textarea');
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('field-width')),
        )
        .onChanged!('half');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('field-placement-create')));
    await tester.tap(find.byKey(const ValueKey('field-placement-table')));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('configuration-publish')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина публикации *'),
      'Настроили размещение поля',
    );
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    final field = (api.submittedSnapshot!['fields'] as List)
        .cast<Map>()
        .firstWhere((item) => item['key'] == 'goal');
    expect(field['valueType'], 'textarea');
    expect(field['width'], 'half');
    expect(field['placements'], ['edit', 'card', 'table']);
  });

  testWidgets(
    'director configures independent lesson and teacher catalogs and publishes impact',
    (tester) async {
      final api = ConfigurationTestApi(
        role: 'director',
        capabilities: const [
          'config.crm.read',
          'config.crm.edit',
          'config.crm.publish',
        ],
      );
      await _pump(tester, api);

      await tester.tap(find.text('Занятия и оплата'));
      await tester.pumpAndSettle();
      expect(find.text('Типы списания занятия'), findsOneWidget);
      expect(find.text('Типы оплаты преподавателю'), findsOneWidget);

      await tester.tap(find.text('Бесплатное занятие'));
      await tester.pumpAndSettle();
      expect(find.text('Так метка выглядит в занятии'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('edit-commerce-catalog-item')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название *'),
        'Бесплатное занятие без списания',
      );
      await tester.tap(find.widgetWithText(SwitchListTile, 'Активно'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final freeLessonTile = find
          .ancestor(
            of: find.text('Бесплатное занятие без списания').first,
            matching: find.byType(ListTile),
          )
          .first;
      await tester.ensureVisible(freeLessonTile);
      await tester.tap(
        find.descendant(of: freeLessonTile, matching: find.byTooltip('Выше')),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Полная стандартная ставка'));
      await tester.tap(find.text('Полная стандартная ставка'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('edit-commerce-catalog-item')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('commerce-compensation-mode')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Фиксированная сумма').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Сумма, ₽ *'),
        '1500,50',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('configuration-publish')));
      await tester.pumpAndSettle();
      expect(
        find.text('Типов списания изменено: 1 · типов оплаты преподавателю: 1'),
        findsOneWidget,
      );
      expect(
        find.text('• Новые правила применятся только к будущим решениям.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Причина публикации *'),
        'Обновили правила занятия и оплаты',
      );
      await tester.tap(find.text('Опубликовать'));
      await tester.pumpAndSettle();

      final submitted = api.submittedSnapshot!;
      final settlements = submitted['lessonSettlementTypes'] as List;
      expect((settlements.first as Map)['stableKey'], 'free_lesson');
      expect((settlements.first as Map)['active'], isFalse);
      final compensation = (submitted['teacherCompensationRules'] as List)
          .cast<Map>()
          .singleWhere((item) => item['stableKey'] == 'standard');
      expect(compensation['mode'], 'fixed');
      expect(compensation['value'], '150050');
      expect(api.publishes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local catalog changes are guarded by Save Discard Cancel back flow',
    (tester) async {
      final api = ConfigurationTestApi(
        role: 'director',
        capabilities: const [
          'config.crm.read',
          'config.crm.edit',
          'config.crm.publish',
        ],
      );
      await _pump(tester, api);
      await tester.tap(find.text('Занятия и оплата'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Занятие'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('edit-commerce-catalog-item')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название *'),
        'Обычное занятие',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Сохранить изменения?'), findsOneWidget);
      expect(find.text('Остаться'), findsOneWidget);
      expect(find.text('Не сохранять'), findsOneWidget);
      await tester.tap(find.text('Сохранить').last);
      await tester.pumpAndSettle();
      expect(api.draftSaves, 1);
      expect(
        ((api.submittedSnapshot!['lessonSettlementTypes'] as List).first
            as Map)['label'],
        'Обычное занятие',
      );
    },
  );

  testWidgets('director can publish rollback as a new configuration revision', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
    );
    await _pump(tester, api);
    await tester.tap(find.text('История версий'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Опубликовать откат к этой версии'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина *'),
      'Возвращаем утверждённую версию',
    );
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(api.rollbacks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delegated manager is branch-only and cannot publish', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'manager',
      capabilities: const ['config.crm.read', 'config.crm.edit'],
    );
    await _pump(tester, api, size: const Size(390, 844));

    expect(find.text('Вся школа'), findsNothing);
    expect(find.text('Сокол'), findsOneWidget);
    expect(find.text('Занятия и оплата'), findsNothing);
    expect(find.byKey(const ValueKey('add-settlement-type')), findsNothing);
    expect(find.byKey(const ValueKey('configuration-publish')), findsNothing);
    expect(api.configurationReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('director changing scope reloads the selected branch draft', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
    );
    await _pump(tester, api);

    await tester.tap(find.byKey(const ValueKey('configuration-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сокол').last);
    await tester.pumpAndSettle();

    expect(api.configurationScopeReads, [
      null,
      '20000000-0000-4000-8000-000000000001',
    ]);
    expect(find.text('Сокол'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final role in const ['admin', 'teacher', 'client']) {
    testWidgets(
      '$role sees forbidden state and issues no configuration request',
      (tester) async {
        final api = ConfigurationTestApi(role: role, capabilities: const []);
        await _pump(tester, api);

        expect(
          find.text('Недостаточно прав для изменения настроек.'),
          findsOneWidget,
        );
        expect(find.text('Занятия и оплата'), findsNothing);
        expect(api.configurationReads, 0);
      },
    );
  }

  testWidgets('inline field options migrate losslessly to one option set', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
      snapshot: inlineOptionsSnapshot(),
    );
    await _pump(tester, api);

    expect(find.text('Черновик · версия 1'), findsOneWidget);
    await tester.tap(find.text('Формат занятий'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();

    expect(find.text('Набор вариантов *'), findsOneWidget);
    expect(find.text('Формат занятий: варианты'), findsOneWidget);
    expect(find.text('Варианты через запятую *'), findsNothing);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('configuration-publish')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина публикации *'),
      'Перенесли варианты в единый набор',
    );
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    final submitted = api.submittedSnapshot!;
    final field = (submitted['fields'] as List).single as Map;
    final set = (submitted['optionSets'] as List).single as Map;
    expect(field['optionSetKey'], 'lesson_format_options');
    expect(field['options'], ['Онлайн', 'Офлайн']);
    expect((set['options'] as List).map((item) => (item as Map)['label']), [
      'Онлайн',
      'Офлайн',
    ]);
  });

  testWidgets('field editor only attaches prepared option sets', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
      snapshot: inlineOptionsSnapshot(),
    );
    await _pump(tester, api);

    await tester.tap(find.text('Формат занятий'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('field-create-option-set')), findsNothing);
    expect(
      find.text('Состав набора меняется только в разделе «Варианты для полей»'),
      findsOneWidget,
    );
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('field-type')),
        )
        .onChanged!('multi_select');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Сначала добавьте подходящий набор в разделе «Варианты для полей»',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Сначала создайте подходящий набор в разделе «Варианты для полей»',
      ),
      findsOneWidget,
    );
    expect(find.text('Настройка поля'), findsOneWidget);
    expect(api.submittedSnapshot, isNull);
  });

  testWidgets('option editor preserves keys while reordering and archiving', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
      snapshot: {
        ...ConfigurationTestApi._defaultSnapshot,
        'optionSets': const [
          {
            'key': 'directions',
            'label': 'Направления',
            'multiple': false,
            'options': [
              {'key': 'vocal', 'label': 'Вокал', 'order': 0, 'active': true},
              {'key': 'guitar', 'label': 'Гитара', 'order': 1, 'active': true},
            ],
          },
        ],
      },
    );
    await _pump(tester, api);

    await tester.tap(find.text('Варианты для полей'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Направления'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Вариант 1 *'),
      'Эстрадный вокал',
    );
    await tester.tap(find.byTooltip('Ниже').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Архивировать вариант').first);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('configuration-publish')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина публикации *'),
      'Актуализировали направления',
    );
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    final set = (api.submittedSnapshot!['optionSets'] as List).single as Map;
    final options = (set['options'] as List).cast<Map>();
    expect(options[0], {
      'key': 'guitar',
      'label': 'Гитара',
      'order': 0,
      'active': false,
    });
    expect(options[1], {
      'key': 'vocal',
      'label': 'Эстрадный вокал',
      'order': 1,
      'active': true,
    });
  });

  testWidgets('legacy lead and student field copies become one shared field', (
    tester,
  ) async {
    final api = ConfigurationTestApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
      snapshot: {
        ...ConfigurationTestApi._defaultSnapshot,
        'fields': [
          ...ConfigurationTestApi._defaultSnapshot['fields'] as List,
          const {
            'entityType': 'lead',
            'key': 'preferredDirection',
            'label': 'Направление',
            'valueType': 'select',
            'required': false,
            'active': true,
            'system': false,
            'categoryKey': 'general',
            'order': 2,
            'width': 'half',
            'placements': ['card'],
            'options': ['Для себя'],
            'optionSetKey': 'lead_preferredDirection_options',
          },
          const {
            'entityType': 'student',
            'key': 'preferredDirection',
            'label': 'Направление',
            'valueType': 'select',
            'required': false,
            'active': true,
            'system': false,
            'categoryKey': 'general',
            'order': 2,
            'width': 'half',
            'placements': ['card'],
            'options': ['Для себя'],
            'optionSetKey': 'student_preferredDirection_options',
          },
        ],
        'optionSets': const [
          {
            'key': 'lead_preferredDirection_options',
            'label': 'Направления лида',
            'multiple': false,
            'options': [
              {'key': 'self', 'label': 'Для себя', 'order': 0, 'active': true},
            ],
          },
          {
            'key': 'student_preferredDirection_options',
            'label': 'Направления ученика',
            'multiple': false,
            'options': [
              {'key': 'self', 'label': 'Для себя', 'order': 0, 'active': true},
            ],
          },
        ],
      },
    );
    await _pump(tester, api);

    await tester.tap(find.text('Варианты для полей'));
    await tester.pumpAndSettle();

    expect(find.text('Направление: варианты'), findsOneWidget);
    expect(find.text('Карточки лида и ученика · 1 вариант'), findsOneWidget);
    final fields = api.submittedSnapshot?['fields'] as List?;
    expect(fields, isNull, reason: 'Миграция остаётся локальным draft до save');
  });
}

Map<String, dynamic> inlineOptionsSnapshot() => {
  ...ConfigurationTestApi._defaultSnapshot,
  'fields': [
    {
      'id': '30000000-0000-4000-8000-000000000002',
      'entityType': 'lead',
      'key': 'lesson_format',
      'label': 'Формат занятий',
      'valueType': 'select',
      'required': false,
      'active': true,
      'system': false,
      'categoryKey': 'general',
      'order': 0,
      'width': 'full',
      'placements': ['create', 'edit', 'card'],
      'options': ['Онлайн', 'Офлайн'],
    },
  ],
};
