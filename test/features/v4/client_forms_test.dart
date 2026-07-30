import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms.dart';

class _ClientFormsFakeApi extends MagicApiClient {
  _ClientFormsFakeApi({
    this.failFirstLeadWithInactiveSource = false,
    this.configurationForbidden = false,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool failFirstLeadWithInactiveSource;
  final bool configurationForbidden;
  int sourceLoads = 0;
  int leadCreates = 0;
  final posts = <({String path, Map<String, dynamic> data})>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (configurationForbidden && path.startsWith('/crm/client-config/')) {
      throw const MagicApiException(message: 'Forbidden', statusCode: 403);
    }
    if (path == '/crm/client-config/sources') {
      sourceLoads++;
      final sourceId = failFirstLeadWithInactiveSource && sourceLoads > 1
          ? '20000000-0000-4000-8000-000000000002'
          : '20000000-0000-4000-8000-000000000001';
      return <String, dynamic>{
            'items': [
              {
                'id': sourceId,
                'canonicalName': sourceLoads > 1 ? 'refreshed' : 'site',
                'displayName': sourceLoads > 1 ? 'Новый источник' : 'Сайт',
                'isActive': true,
                'version': 1,
              },
            ],
          }
          as T;
    }
    if (path == '/crm/client-config/fields') {
      final entityType = queryParameters?['entityType'];
      return <String, dynamic>{
            'items': entityType == 'lead'
                ? [
                    {
                      'id': '30000000-0000-4000-8000-000000000001',
                      'entityType': 'lead',
                      'key': 'goal',
                      'label': 'Цель',
                      'valueType': 'text',
                      'required': true,
                      'isActive': true,
                      'isSystem': false,
                      'options': const <String>[],
                      'version': 1,
                    },
                  ]
                : const <Map<String, dynamic>>[],
          }
          as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {'id': '40000000-0000-4000-8000-000000000001', 'name': 'Центр'},
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
    final body = Map<String, dynamic>.from(data! as Map);
    posts.add((path: path, data: body));
    if (path == '/crm/leads') {
      leadCreates++;
      if (failFirstLeadWithInactiveSource && leadCreates == 1) {
        throw const MagicApiException(
          message: 'Выберите активный источник.',
          statusCode: 422,
          details: {
            'field': 'sourceId',
            'code': 'SOURCE_INACTIVE',
            'message': 'Выберите активный источник.',
          },
        );
      }
      return <String, dynamic>{'id': 'lead-a'} as T;
    }
    if (path == '/crm/students') {
      return <String, dynamic>{'id': 'student-a'} as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  _ClientFormsFakeApi api, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterLeadMinimum(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('lead-first-name')), 'Анна');
  await tester.enterText(
    find.byKey(const ValueKey('lead-last-name')),
    'Иванова',
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('lead-phone')),
      matching: find.byType(TextField),
    ),
    '9991234567',
  );
  await tester.tap(find.byKey(const ValueKey('lead-source')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Сайт').last);
  await tester.enterText(
    find.byKey(const ValueKey('custom-field-goal')),
    'Вокал',
  );
}

void main() {
  testWidgets(
    'narrow Lead form validates required fields and sends strict DTO',
    (tester) async {
      final api = _ClientFormsFakeApi();
      await _pump(tester, const LeadCreateDialog(), api);

      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('lead-submit')));
      await tester.pump();
      expect(find.text('Укажите имя.'), findsOneWidget);
      expect(find.text('Укажите фамилию.'), findsOneWidget);
      expect(find.text('Выберите источник.'), findsOneWidget);

      await _enterLeadMinimum(tester);
      await tester.tap(find.byKey(const ValueKey('lead-submit')));
      await tester.pumpAndSettle();

      final call = api.posts.single;
      expect(call.path, '/crm/leads');
      expect(call.data, {
        'firstName': 'Анна',
        'lastName': 'Иванова',
        'phone': '+79991234567',
        'sourceId': '20000000-0000-4000-8000-000000000001',
        'customFields': [
          {
            'definitionId': '30000000-0000-4000-8000-000000000001',
            'value': 'Вокал',
          },
        ],
      });
    },
  );

  testWidgets(
    'inactive source refresh keeps input and requires a fresh choice',
    (tester) async {
      final api = _ClientFormsFakeApi(failFirstLeadWithInactiveSource: true);
      await _pump(tester, const LeadCreateDialog(), api);
      await _enterLeadMinimum(tester);

      await tester.tap(find.byKey(const ValueKey('lead-submit')));
      await tester.pumpAndSettle();

      expect(api.sourceLoads, 2);
      expect(find.text('Анна'), findsOneWidget);
      expect(
        find.text('Источник был архивирован. Выберите другой.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('lead-source')));
      await tester.pumpAndSettle();
      expect(find.text('Новый источник'), findsOneWidget);
    },
  );

  testWidgets('Student form sends branch/status and remains overflow-free', (
    tester,
  ) async {
    final api = _ClientFormsFakeApi();
    await _pump(
      tester,
      const StudentCreateDialogV4(),
      api,
      size: const Size(320, 700),
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('student-first-name')),
      'Пётр',
    );
    await tester.enterText(
      find.byKey(const ValueKey('student-last-name')),
      'Смирнов',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('student-phone')),
        matching: find.byType(TextField),
      ),
      '9995554433',
    );
    await tester.tap(find.byKey(const ValueKey('student-submit')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(api.posts.single.data, {
      'firstName': 'Пётр',
      'lastName': 'Смирнов',
      'phone': '+79995554433',
      'branchId': '40000000-0000-4000-8000-000000000001',
      'status': 'active',
      'customFields': const <Map<String, dynamic>>[],
    });
  });

  testWidgets('configuration control is hidden and 403 is handled in-dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ClientConfigurationButton(allowed: false)),
      ),
    );
    expect(
      find.byKey(const ValueKey('client-configuration-open')),
      findsNothing,
    );

    final api = _ClientFormsFakeApi(configurationForbidden: true);
    await _pump(tester, const ClientConfigurationDialog(), api);
    expect(
      find.text(
        'Настройка доступна только Директору и администратору системы.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
