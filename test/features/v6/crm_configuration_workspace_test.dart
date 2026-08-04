import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/crm_configuration_workspace.dart';

class _ConfigurationApi extends MagicApiClient {
  _ConfigurationApi({required this.role, required this.capabilities})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String role;
  final List<String> capabilities;
  int configurationReads = 0;
  int publishes = 0;

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
    if (path == '/crm/configuration/draft') {
      configurationReads++;
      return <String, dynamic>{
            'baseVersion': 1,
            'dirty': false,
            'snapshot': _snapshot,
          }
          as T;
    }
    if (path == '/crm/configuration/revisions') {
      return <String, dynamic>{
            'items': const [
              {'id': 'revision-1', 'version': 1, 'reason': 'Базовая версия'},
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
      return <String, dynamic>{
            'valid': true,
            'blockingIssues': const [],
            'affectedScreens': const ['lead.create'],
            'changes': const {
              'fieldsCreated': 0,
              'fieldsUpdated': 1,
              'fieldsArchived': 0,
              'settingsChanged': 0,
            },
          }
          as T;
    }
    if (path == '/crm/configuration/publish') {
      publishes++;
      return <String, dynamic>{'version': 2} as T;
    }
    throw StateError('Unexpected POST $path');
  }

  static const _snapshot = <String, dynamic>{
    'categories': [
      {'key': 'general', 'label': 'Основное', 'order': 0, 'active': true},
    ],
    'fields': [
      {
        'id': '30000000-0000-4000-8000-000000000001',
        'entityType': 'lead',
        'key': 'goal',
        'label': 'Цель обучения',
        'valueType': 'text',
        'required': false,
        'active': true,
        'system': false,
        'categoryKey': 'general',
        'order': 0,
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
  };
}

Future<void> _pump(
  WidgetTester tester,
  _ConfigurationApi api, {
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
  testWidgets('director edits a draft and publishes through impact preview', (
    tester,
  ) async {
    final api = _ConfigurationApi(
      role: 'director',
      capabilities: const [
        'config.crm.read',
        'config.crm.edit',
        'config.crm.publish',
      ],
    );
    await _pump(tester, api);

    expect(find.text('Поля и категории'), findsOneWidget);
    expect(find.text('Справочники'), findsOneWidget);
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
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина публикации *'),
      'Настроили карточку лида',
    );
    await tester.tap(find.text('Опубликовать'));
    await tester.pumpAndSettle();

    expect(api.publishes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delegated manager is branch-only and cannot publish', (
    tester,
  ) async {
    final api = _ConfigurationApi(
      role: 'manager',
      capabilities: const ['config.crm.read', 'config.crm.edit'],
    );
    await _pump(tester, api, size: const Size(390, 844));

    expect(find.text('Вся школа'), findsNothing);
    expect(find.text('Сокол'), findsOneWidget);
    expect(find.byKey(const ValueKey('configuration-publish')), findsNothing);
    expect(api.configurationReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'admin sees forbidden state and issues no configuration request',
    (tester) async {
      final api = _ConfigurationApi(role: 'admin', capabilities: const []);
      await _pump(tester, api);

      expect(
        find.text('Недостаточно прав для конфигурации CRM.'),
        findsOneWidget,
      );
      expect(api.configurationReads, 0);
    },
  );
}
