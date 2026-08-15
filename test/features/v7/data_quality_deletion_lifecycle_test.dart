import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/data_quality_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/deletion_requests_widget.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_status_screen.dart';

class _LifecycleApi extends MagicApiClient {
  _LifecycleApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  List<Map<String, dynamic>> phoneQueue = [
    {
      'id': '10000000-0000-4000-8000-000000000001',
      'entityType': 'lead',
      'entityId': '20000000-0000-4000-8000-000000000001',
      'rawPhone': '8 999 123',
      'reason': 'too_short',
    },
  ];
  List<Map<String, dynamic>> deletionQueue = [
    {
      'id': '30000000-0000-4000-8000-000000000001',
      'status': 'pending',
      'profileName': 'UAT Клиент',
      'reason': 'Запрос UAT',
    },
  ];
  final List<Map<String, dynamic>> patches = [];
  final List<String> deletes = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/phone-review-queue') {
      return <String, dynamic>{'items': phoneQueue} as T;
    }
    if (path == '/crm/phone-review-queue/count') {
      return <String, dynamic>{'count': phoneQueue.length} as T;
    }
    if (path == '/crm/merge-candidates') {
      return <String, dynamic>{'items': const []} as T;
    }
    if (path == '/admin/deletion-requests') {
      return <String, dynamic>{'items': deletionQueue} as T;
    }
    if (path == '/profile/deletion-request') {
      return <String, dynamic>{
            'id': '40000000-0000-4000-8000-000000000001',
            'status': 'pending',
            'reason': 'Запрос UAT',
            'requestedAt': '2026-08-12T10:00:00.000Z',
          }
          as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data! as Map);
    patches.add({'path': path, 'data': body});
    if (path.startsWith('/crm/phone-review-queue/')) {
      phoneQueue = [];
      return <String, dynamic>{
            'id': path.split('/').last,
            'action': body['action'],
            'resolvedPhone': '+79991234567',
          }
          as T;
    }
    if (path.startsWith('/admin/deletion-requests/')) {
      deletionQueue = [
        {...deletionQueue.single, 'status': body['status']},
      ];
      return deletionQueue.single as T;
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
    deletes.add(path);
    if (path == '/profile/deletion-request') {
      return <String, dynamic>{
            'id': '40000000-0000-4000-8000-000000000001',
            'status': 'cancelled',
            'reason': 'Запрос UAT',
            'requestedAt': '2026-08-12T10:00:00.000Z',
          }
          as T;
    }
    throw StateError('Unexpected DELETE $path');
  }
}

Future<void> _pump(WidgetTester tester, _LifecycleApi api, Widget child) async {
  tester.view.physicalSize = const Size(1100, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone review requires a reason and writes a corrected payload', (
    tester,
  ) async {
    final api = _LifecycleApi();
    await _pump(tester, api, const DataQualityWidget());

    await tester.tap(
      find.byKey(
        const ValueKey(
          'resolve-phone-review-10000000-0000-4000-8000-000000000001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.byKey(const ValueKey('submit-phone-review-resolution'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('phone-review-phone')),
      '8 (999) 123-45-67',
    );
    await tester.enterText(
      find.byKey(const ValueKey('phone-review-note')),
      'Подтверждено по карточке клиента',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(api.patches, hasLength(1));
    expect(api.patches.single['path'], contains('/crm/phone-review-queue/'));
    expect(api.patches.single['data'], {
      'action': 'corrected',
      'phone': '8 (999) 123-45-67',
      'resolutionNote': 'Подтверждено по карточке клиента',
    });
    expect(find.text('Очередь пуста. Все номера в порядке'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'pending deletion advances only through processing and completion',
    (tester) async {
      final api = _LifecycleApi();
      await _pump(tester, api, const DeletionRequestsWidget(canManage: true));

      expect(find.text('В работу'), findsOneWidget);
      expect(find.text('Выполнить'), findsNothing);
      expect(find.text('Отклонить'), findsNothing);

      await tester.tap(find.text('В работу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В работу').last);
      await tester.pumpAndSettle();

      expect(api.patches.single['data'], {'status': 'processing'});
      expect(find.text('Выполнить'), findsOneWidget);
      expect(find.text('Отклонить'), findsOneWidget);

      await tester.tap(find.text('Выполнить'));
      await tester.pumpAndSettle();
      final completeButton = find.widgetWithText(ElevatedButton, 'Выполнить');
      expect(tester.widget<ElevatedButton>(completeButton).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Резолюция'),
        'PII проверена, обязательная история сохранена',
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-deletion-anonymization')),
      );
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(completeButton).onPressed,
        isNotNull,
      );
      await tester.tap(completeButton);
      await tester.pumpAndSettle();

      expect(api.patches, hasLength(2));
      expect(api.patches.last['data'], {
        'status': 'completed',
        'resolutionNote': 'PII проверена, обязательная история сохранена',
      });
      expect(find.text('Выполнен'), findsWidgets);
      expect(find.text('Выполнить'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('read-only deletion queue never renders mutation actions', (
    tester,
  ) async {
    final api = _LifecycleApi();
    await _pump(tester, api, const DeletionRequestsWidget(canManage: false));

    expect(find.text('UAT Клиент'), findsOneWidget);
    expect(find.text('В работу'), findsNothing);
    expect(find.text('Выполнить'), findsNothing);
    expect(find.text('Отклонить'), findsNothing);
    expect(api.patches, isEmpty);
  });

  testWidgets('client can cancel a pending request and return to the app', (
    tester,
  ) async {
    final api = _LifecycleApi();
    final router = GoRouter(
      initialLocation: '/deletion-status',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('CRM доступна')),
        GoRoute(
          path: '/deletion-status',
          builder: (_, _) => const AccountDeletionStatusScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: MaterialApp.router(
          theme: ThemeData.dark(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cancel-deletion-request')));
    await tester.pumpAndSettle();
    expect(find.text('Отозвать запрос?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('confirm-cancel-deletion-request')),
    );
    await tester.pumpAndSettle();

    expect(api.deletes, ['/profile/deletion-request']);
    expect(find.text('CRM доступна'), findsOneWidget);
  });
}
