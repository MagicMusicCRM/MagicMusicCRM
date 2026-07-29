import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/subscription_catalog_widget.dart';

typedef _ApiCall = ({String path, Object? data, Map<String, dynamic> query});

class _CatalogApiClient extends MagicApiClient {
  _CatalogApiClient()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final activePackage = <String, dynamic>{
    'id': 'active-package',
    'name': 'Фортепиано — 8 часов',
    'unitCount': 8,
    'basePriceMinor': 800000,
    'currencyCode': 'RUB',
    'validityDays': 30,
    'active': true,
    'version': 3,
  };

  final archivedPackage = <String, dynamic>{
    'id': 'archived-package',
    'name': 'Архивный абонемент',
    'unitCount': 4,
    'basePriceMinor': 360000,
    'currencyCode': 'RUB',
    'active': false,
    'archivedAt': '2026-07-01T10:00:00.000Z',
    'version': 7,
  };

  final List<_ApiCall> gets = [];
  final List<_ApiCall> posts = [];
  final List<_ApiCall> patches = [];
  final List<_ApiCall> deletes = [];
  bool failPatchWithConflict = false;
  Completer<void>? deleteGate;

  Map<String, dynamic> _query(Map<String, dynamic>? value) =>
      Map<String, dynamic>.from(value ?? const <String, dynamic>{});

  Map<String, dynamic>? _body(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final query = _query(queryParameters);
    gets.add((path: path, data: null, query: query));
    if (path == '/crm/subscription-packages') {
      final items = <Map<String, dynamic>>[
        Map<String, dynamic>.from(activePackage),
        if (query['includeArchived'] == true)
          Map<String, dynamic>.from(archivedPackage),
      ];
      return <String, dynamic>{'items': items} as T;
    }
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    posts.add((path: path, data: _body(data), query: _query(queryParameters)));
    return <String, dynamic>{'id': 'saved-package', 'version': 1} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    patches.add((
      path: path,
      data: _body(data),
      query: _query(queryParameters),
    ));
    if (failPatchWithConflict) {
      failPatchWithConflict = false;
      activePackage
        ..['name'] = 'Фортепиано — версия сервера'
        ..['version'] = 4;
      throw const MagicApiException(
        statusCode: 409,
        message: 'Пакет уже изменён в другой вкладке.',
      );
    }
    return <String, dynamic>{'id': 'active-package', 'version': 4} as T;
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    deletes.add((
      path: path,
      data: _body(data),
      query: _query(queryParameters),
    ));
    await deleteGate?.future;
    return <String, dynamic>{'id': 'active-package', 'version': 4} as T;
  }
}

Future<void> _pumpCatalog(
  WidgetTester tester,
  _CatalogApiClient api, {
  required String role,
  Size size = const Size(900, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(MagicToast.dismiss);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(body: SubscriptionCatalogWidget(role: role)),
      ),
    ),
  );

  for (
    var attempt = 0;
    attempt < 40 &&
        find
            .byKey(const ValueKey('subscription-package-active-package'))
            .evaluate()
            .isEmpty;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

String _normalizeSpaces(String value) =>
    value.replaceAll('\u00a0', ' ').replaceAll('\u202f', ' ');

List<String> _visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => _normalizeSpaces(widget.data ?? ''))
    .toList(growable: false);

Future<void> _fillPackageForm(
  WidgetTester tester, {
  required String name,
  required String units,
  required String price,
}) async {
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(5));
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), units);
  await tester.enterText(fields.at(2), price);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('issue selector excludes inactive and archived package rows', () {
    final active = <String, dynamic>{
      'id': 'active',
      'active': true,
      'archivedAt': null,
    };
    expect(
      activeSubscriptionPackages([
        active,
        {'id': 'inactive', 'active': false},
        {
          'id': 'archived',
          'active': true,
          'archivedAt': '2026-07-01T00:00:00Z',
        },
      ]),
      [active],
    );
  });

  testWidgets(
    'Manager receives only active packages and has a read-only catalog',
    (tester) async {
      final api = _CatalogApiClient();
      await _pumpCatalog(tester, api, role: 'manager');

      expect(
        find.byKey(const ValueKey('subscription-package-active-package')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('subscription-package-archived-package')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('subscription-catalog-create')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('subscription-package-archive-active-package'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('subscription-package-restore-archived-package'),
        ),
        findsNothing,
      );

      final catalogRequest = api.gets.singleWhere(
        (call) => call.path == '/crm/subscription-packages',
      );
      expect(catalogRequest.query, {'limit': 100});
      expect(_visibleText(tester), contains('8 000 ₽'));

      await tester.tap(
        find.byKey(const ValueKey('subscription-package-active-package')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Редактировать абонемент'), findsNothing);
      expect(api.posts, isEmpty);
      expect(api.patches, isEmpty);
      expect(api.deletes, isEmpty);
    },
  );

  testWidgets(
    'Director can create and edit canonical packages with expectedVersion',
    (tester) async {
      final api = _CatalogApiClient();
      await _pumpCatalog(tester, api, role: 'director');

      final catalogRequest = api.gets.firstWhere(
        (call) => call.path == '/crm/subscription-packages',
      );
      expect(catalogRequest.query, {'limit': 100, 'includeArchived': true});
      expect(
        find.byKey(const ValueKey('subscription-package-archived-package')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('subscription-catalog-create')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Новый абонемент'), findsOneWidget);
      await _fillPackageForm(
        tester,
        name: 'Вокал — 10 часов',
        units: '10',
        price: '8000',
      );
      final createButton = find.widgetWithText(ElevatedButton, 'Создать');
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();
      MagicToast.dismiss();
      await tester.pump();

      final createCall = api.posts.singleWhere(
        (call) => call.path == '/crm/subscription-packages',
      );
      expect(createCall.data, {
        'name': 'Вокал — 10 часов',
        'unitCount': 10,
        'basePriceMinor': '800000',
        'currencyCode': 'RUB',
      });

      await tester.tap(
        find.byKey(const ValueKey('subscription-package-active-package')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Редактировать абонемент'), findsOneWidget);
      await _fillPackageForm(
        tester,
        name: 'Фортепиано — 12,5 часов',
        units: '12,5',
        price: '9000',
      );
      final saveButton = find.widgetWithText(ElevatedButton, 'Сохранить');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      MagicToast.dismiss();
      await tester.pump();

      final editCall = api.patches.singleWhere(
        (call) => call.path == '/crm/subscription-packages/active-package',
      );
      expect(editCall.data, {
        'name': 'Фортепиано — 12,5 часов',
        'unitCount': 12.5,
        'basePriceMinor': '900000',
        'currencyCode': 'RUB',
        'validityDays': 30,
        'branchId': null,
        'expectedVersion': 3,
      });
    },
  );

  testWidgets(
    'Director archive and restore commands carry the current version',
    (tester) async {
      final api = _CatalogApiClient();
      await _pumpCatalog(tester, api, role: 'director');

      await tester.tap(
        find.byKey(
          const ValueKey('subscription-package-archive-active-package'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Архивировать абонемент?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Архивировать'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      MagicToast.dismiss();
      await tester.pump();

      final archiveCall = api.deletes.singleWhere(
        (call) => call.path == '/crm/subscription-packages/active-package',
      );
      expect(archiveCall.query, {'expectedVersion': 3});

      await tester.tap(
        find.byKey(
          const ValueKey('subscription-package-restore-archived-package'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      MagicToast.dismiss();
      await tester.pump();

      final restoreCall = api.posts.singleWhere(
        (call) =>
            call.path == '/crm/subscription-packages/archived-package/restore',
      );
      expect(restoreCall.query, {'expectedVersion': 7});
      expect(restoreCall.data, isEmpty);
    },
  );

  testWidgets('stale edit requires an explicit fresh reload before retry', (
    tester,
  ) async {
    final api = _CatalogApiClient()..failPatchWithConflict = true;
    await _pumpCatalog(tester, api, role: 'director');

    await tester.tap(
      find.byKey(const ValueKey('subscription-package-active-package')),
    );
    await tester.pumpAndSettle();
    await _fillPackageForm(
      tester,
      name: 'Фортепиано — изменено',
      units: '8',
      price: '8000',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Сохранить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Редактировать абонемент'), findsOneWidget);
    expect(find.text('Каталог уже изменён'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subscription-package-stale-banner')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Сохранить'),
          )
          .onPressed,
      isNull,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      api.gets
          .where((call) => call.path == '/crm/subscription-packages')
          .length,
      greaterThanOrEqualTo(2),
    );
    MagicToast.dismiss();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('subscription-package-reload-latest')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('subscription-package-stale-banner')),
      findsNothing,
    );
    final refreshedFields = find.byType(TextFormField);
    expect(
      tester.widget<TextFormField>(refreshedFields.at(0)).controller?.text,
      'Фортепиано — версия сервера',
    );
    MagicToast.dismiss();
    await tester.pump();

    await _fillPackageForm(
      tester,
      name: 'Фортепиано — согласованная версия',
      units: '9',
      price: '8500',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Сохранить'));
    await tester.pumpAndSettle();
    expect(api.patches, hasLength(2));
    expect(
      (api.patches.first.data as Map<String, dynamic>)['expectedVersion'],
      3,
    );
    expect(
      (api.patches.last.data as Map<String, dynamic>)['expectedVersion'],
      4,
    );
    expect(find.text('Редактировать абонемент'), findsNothing);
    MagicToast.dismiss();
    await tester.pump();
  });

  testWidgets('archive disables its row until the request completes', (
    tester,
  ) async {
    final api = _CatalogApiClient()..deleteGate = Completer<void>();
    await _pumpCatalog(tester, api, role: 'director');
    final archiveKey = find.byKey(
      const ValueKey('subscription-package-archive-active-package'),
    );

    await tester.tap(archiveKey);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(TextButton, 'Архивировать'));
    await tester.pump();
    await tester.pump();

    expect(api.deletes, hasLength(1));
    expect(tester.widget<IconButton>(archiveKey).onPressed, isNull);
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(of: archiveKey, matching: find.byType(ListTile)),
          )
          .onTap,
      isNull,
    );

    api.deleteGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.deletes, hasLength(1));
    MagicToast.dismiss();
    await tester.pump();
  });

  testWidgets('catalog fits a 390x844 viewport without overflow', (
    tester,
  ) async {
    final api = _CatalogApiClient();
    await _pumpCatalog(
      tester,
      api,
      role: 'director',
      size: const Size(390, 844),
    );

    expect(
      find.byKey(const ValueKey('subscription-package-active-package')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
