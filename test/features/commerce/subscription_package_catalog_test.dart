import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';

const _branchId = '20000000-0000-4000-8000-000000000001';

class _PackageCatalogApi extends MagicApiClient {
  _PackageCatalogApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final packages = <Map<String, dynamic>>[
    {
      'id': 'package-active',
      'name': 'Базовый пакет',
      'unitCount': 8,
      'basePriceMinor': '1800000',
      'currencyCode': 'RUB',
      'active': true,
      'isActive': true,
      'version': 3,
    },
    {
      'id': 'package-archived',
      'name': 'Старый пакет',
      'unitCount': 4,
      'basePriceMinor': '900000',
      'currencyCode': 'RUB',
      'active': false,
      'isActive': false,
      'archivedAt': '2026-08-01T00:00:00.000Z',
      'version': 4,
    },
  ];
  final packageQueries = <Map<String, dynamic>>[];
  final creates = <Map<String, dynamic>>[];
  final lifecycleCalls = <String, int>{};

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/access/me') {
      return <String, dynamic>{
            'accountId': '10000000-0000-4000-8000-000000000001',
            'role': 'director',
            'accessVersion': 1,
            'capabilities': const [
              'system.settings.manage',
              'commerce.package.manage',
            ],
            'scopes': const {'schedule': 'school'},
          }
          as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': const [
              {'id': _branchId, 'name': 'Сокол'},
            ],
          }
          as T;
    }
    if (path == '/crm/subscription-packages') {
      final query = Map<String, dynamic>.from(queryParameters ?? const {});
      packageQueries.add(query);
      final includeArchived = query['includeArchived'] == true;
      return <String, dynamic>{
            'items': packages
                .where((item) => includeArchived || item['isActive'] == true)
                .map(Map<String, dynamic>.from)
                .toList(),
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
    if (path == '/crm/subscription-packages') {
      final body = Map<String, dynamic>.from(data! as Map);
      creates.add(body);
      final branchId = body['branchId']?.toString();
      final created = <String, dynamic>{
        'id': 'package-created-${creates.length}',
        ...body,
        'lessonsTotal': body['unitCount'],
        'price': (int.parse(body['basePriceMinor'].toString()) / 100),
        'branchName': branchId == _branchId ? 'Сокол' : null,
        'active': true,
        'isActive': true,
        'version': 1,
      };
      packages.add(created);
      return created as T;
    }
    if (path.endsWith('/restore')) {
      final id = path.split('/')[3];
      final expectedVersion = queryParameters!['expectedVersion'] as int;
      lifecycleCalls['restore:$id'] = expectedVersion;
      final item = packages.firstWhere((entry) => entry['id'] == id);
      item
        ..['active'] = true
        ..['isActive'] = true
        ..['archivedAt'] = null
        ..['version'] = expectedVersion + 1;
      return Map<String, dynamic>.from(item) as T;
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/crm/subscription-packages/')) {
      final id = path.split('/').last;
      final expectedVersion = queryParameters!['expectedVersion'] as int;
      lifecycleCalls['archive:$id'] = expectedVersion;
      final item = packages.firstWhere((entry) => entry['id'] == id);
      item
        ..['active'] = false
        ..['isActive'] = false
        ..['archivedAt'] = '2026-08-12T00:00:00.000Z'
        ..['version'] = expectedVersion + 1;
      return Map<String, dynamic>.from(item) as T;
    }
    throw StateError('Unexpected DELETE $path');
  }
}

Future<void> _pumpCatalog(WidgetTester tester, _PackageCatalogApi api) async {
  tester.view.physicalSize = const Size(1300, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(
        home: Scaffold(
          body: SystemSettingsWorkspace(role: 'director', initialArea: 'sales'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _createPackage(
  WidgetTester tester, {
  required String name,
  bool forBranch = false,
}) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Новый абонемент'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Название'), name);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Количество часов'),
    '12',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Цена, ₽'),
    '30000',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Срок действия, дней'),
    '60',
  );
  if (forBranch) {
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сокол').last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.widgetWithText(ElevatedButton, 'Создать'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'director creates school and branch packages, archives and restores them',
    (tester) async {
      final api = _PackageCatalogApi();
      await _pumpCatalog(tester, api);

      expect(find.text('Базовый пакет'), findsOneWidget);
      expect(find.text('Старый пакет'), findsNothing);

      await _createPackage(tester, name: '12×60 — 30 000 ₽');
      await _createPackage(tester, name: '12×60 — Сокол', forBranch: true);

      expect(api.creates, hasLength(2));
      expect(api.creates.first, {
        'name': '12×60 — 30 000 ₽',
        'unitCount': 12,
        'basePriceMinor': '3000000',
        'currencyCode': 'RUB',
        'validityDays': 60,
      });
      expect(api.creates.last['branchId'], _branchId);
      expect(find.text('Сокол'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('archive-subscription-package-package-created-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Архивировать'));
      await tester.pumpAndSettle();
      expect(api.lifecycleCalls['archive:package-created-1'], 1);
      expect(find.text('12×60 — 30 000 ₽'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('subscription-packages-archive-filter')),
      );
      await tester.pumpAndSettle();
      expect(
        api.packageQueries.any((query) => query['includeArchived'] == true),
        isTrue,
      );
      expect(find.text('12×60 — 30 000 ₽'), findsOneWidget);
      expect(find.text('В архиве'), findsWidgets);

      await tester.tap(
        find.byKey(
          const ValueKey('restore-subscription-package-package-created-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Восстановить'));
      await tester.pumpAndSettle();

      expect(api.lifecycleCalls['restore:package-created-1'], 2);
      expect(
        find.descendant(
          of: find.widgetWithText(Card, '12×60 — 30 000 ₽'),
          matching: find.text('Активен'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
