import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/data_quality_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/deletion_requests_widget.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/legal_consent_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/notification_preferences_dialog.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_status_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/auth_methods_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';

import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('data-quality phone queue has a complete dark desktop flow', (
    tester,
  ) async {
    _desktop(tester);
    final api = _Uat115Api();
    await tester.pumpWidget(_host(api, const DataQualityWidget()));
    await tester.pumpAndSettle();

    expect(find.text('8 999 123'), findsOneWidget);
    expect(find.text('Разобрать'), findsOneWidget);
    await captureEvidence(tester, 'data-quality-phone-review-open');

    await tester.tap(find.text('Разобрать'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-review-phone')),
      '8 (999) 123-45-67',
    );
    await tester.enterText(
      find.byKey(const ValueKey('phone-review-note')),
      'Подтверждено по карточке клиента',
    );
    await tester.pump();
    await captureEvidence(tester, 'data-quality-phone-review-decision');
    await tester.tap(
      find.byKey(const ValueKey('submit-phone-review-resolution')),
    );
    await tester.pumpAndSettle();

    expect(api.phoneResolution?['action'], 'corrected');
    expect(
      api.phoneResolution?['resolutionNote'],
      'Подтверждено по карточке клиента',
    );
    expect(find.text('Очередь пуста — все номера в порядке'), findsOneWidget);
    await captureEvidence(tester, 'data-quality-phone-review-resolved');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'deletion queue follows exact state machine and Manager is read-only',
    (tester) async {
      _desktop(tester);
      final directorApi = _Uat115Api();
      await tester.pumpWidget(
        _host(directorApi, const DeletionRequestsWidget(canManage: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('В работу'), findsOneWidget);
      expect(find.text('Выполнить'), findsNothing);
      await captureEvidence(tester, 'deletion-request-pending-director');
      await tester.tap(find.text('В работу'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В работу').last);
      await tester.pumpAndSettle();

      expect(find.text('Выполнить'), findsOneWidget);
      expect(find.text('Отклонить'), findsOneWidget);
      await tester.tap(find.text('Выполнить'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Резолюция'),
        'PII проверена, обязательная история сохранена',
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-deletion-anonymization')),
      );
      await tester.pumpAndSettle();
      await captureEvidence(tester, 'deletion-request-completion-confirmation');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Выполнить'));
      await tester.pumpAndSettle();

      expect(directorApi.deletionStatuses, ['processing', 'completed']);
      expect(find.text('Выполнить'), findsNothing);
      await captureEvidence(tester, 'deletion-request-completed-director');
      await tester.pump(const Duration(seconds: 4));

      final managerApi = _Uat115Api();
      await tester.pumpWidget(
        _host(
          managerApi,
          const DeletionRequestsWidget(
            key: ValueKey('manager-deletion-queue'),
            canManage: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('UAT Клиент'), findsOneWidget);
      expect(find.text('В работу'), findsNothing);
      expect(managerApi.deletionStatuses, isEmpty);
      await captureEvidence(tester, 'deletion-request-manager-readonly');
    },
  );

  testWidgets(
    'client profile, auth, legal and notifications remain usable without credential mutation',
    (tester) async {
      _desktop(tester);
      final api = _Uat115Api();

      await tester.pumpWidget(_host(api, const ProfileScreen()));
      await tester.pumpAndSettle();
      expect(find.text('UAT'), findsWidgets);
      await captureEvidence(tester, 'uat-client-profile');

      await tester.pumpWidget(_host(api, const AuthMethodsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Почта и пароль'), findsOneWidget);
      expect(find.text('Можно входить по почте и паролю'), findsOneWidget);
      await captureEvidence(tester, 'uat-client-auth-methods');

      await tester.pumpWidget(
        _host(api, const LegalConsentScreen(requireAcceptance: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Актуальные документы MagicMusicCRM.'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('Политика конфиденциальности'),
        ),
        findsOneWidget,
      );
      await captureEvidence(tester, 'uat-client-legal-documents');

      await tester.pumpWidget(
        _host(api, const NotificationPreferencesDialog()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Настройки уведомлений'), findsOneWidget);
      expect(find.text('Новая заявка'), findsOneWidget);
      await captureEvidence(tester, 'uat-notification-preferences');

      expect(api.credentialMutations, isEmpty);

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
      await tester.pumpWidget(_routerHost(api, router));
      await tester.pumpAndSettle();
      expect(find.text('Запрос принят'), findsOneWidget);
      await captureEvidence(tester, 'uat-client-deletion-pending');
      await tester.tap(find.byKey(const ValueKey('cancel-deletion-request')));
      await tester.pumpAndSettle();
      await captureEvidence(tester, 'uat-client-deletion-cancel-confirmation');
      await tester.tap(
        find.byKey(const ValueKey('confirm-cancel-deletion-request')),
      );
      await tester.pumpAndSettle();

      expect(api.deletes, ['/profile/deletion-request']);
      expect(api.credentialMutations, isEmpty);
      expect(find.text('CRM доступна'), findsOneWidget);
      debugPrint('V7_UAT115_DEVICE_PASS');
    },
  );
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(MagicApiClient api, Widget child) => RepaintBoundary(
  key: evidenceRootKey,
  child: ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: Scaffold(body: child),
    ),
  ),
);

Widget _routerHost(_Uat115Api api, GoRouter router) => RepaintBoundary(
  key: evidenceRootKey,
  child: ProviderScope(
    overrides: [magicApiClientProvider.overrideWithValue(api)],
    child: MaterialApp.router(
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    ),
  ),
);

class _Uat115Api extends MagicApiClient {
  _Uat115Api()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  bool phoneOpen = true;
  String deletionStatus = 'pending';
  Map<String, dynamic>? phoneResolution;
  final List<String> deletionStatuses = [];
  final List<String> deletes = [];
  final List<String> credentialMutations = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/phone-review-queue') {
      return <String, dynamic>{
            'items': phoneOpen
                ? [
                    {
                      'id': 'phone-review-a',
                      'entityType': 'lead',
                      'entityId': 'lead-a',
                      'rawPhone': '8 999 123',
                      'reason': 'too_short',
                    },
                  ]
                : const [],
          }
          as T;
    }
    if (path == '/crm/phone-review-queue/count') {
      return <String, dynamic>{'count': phoneOpen ? 1 : 0} as T;
    }
    if (path == '/crm/merge-candidates') {
      return <String, dynamic>{'items': const []} as T;
    }
    if (path == '/admin/deletion-requests') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'deletion-a',
                'status': deletionStatus,
                'profileName': 'UAT Клиент',
                'email': 'uat-client@test.local',
                'reason': 'Больше не пользуюсь приложением',
              },
            ],
          }
          as T;
    }
    if (path == '/profile/me') {
      return <String, dynamic>{
            'userId': 'uat-client',
            'email': 'uat-client@test.local',
            'role': 'client',
            'firstName': 'UAT',
            'lastName': 'Клиент',
            'phone': '+79991234567',
            'dob': '2000-01-01',
            'emailOtp2faEnabled': true,
          }
          as T;
    }
    if (path == '/auth/identities') {
      return <String, dynamic>{
            'items': const [
              {'provider': 'email'},
              {'provider': 'google'},
            ],
          }
          as T;
    }
    if (path == '/legal/documents/current') {
      return <dynamic>[
            {
              'id': 'privacy',
              'type': 'privacy_policy',
              'version': '2026-08-12',
              'title': 'Политика конфиденциальности',
            },
            {
              'id': 'terms',
              'type': 'terms_of_use',
              'version': '2026-08-12',
              'title': 'Пользовательское соглашение',
            },
            {
              'id': 'deletion',
              'type': 'account_deletion',
              'version': '2026-08-12',
              'title': 'Удаление аккаунта',
            },
          ]
          as T;
    }
    if (path == '/admin/notifications/preferences') {
      return <String, dynamic>{
            'items': const [
              {
                'role': 'director',
                'eventType': 'new_lead',
                'enabled': true,
                'channels': ['in_app', 'push'],
              },
              {
                'role': 'manager',
                'eventType': 'new_lead',
                'enabled': true,
                'channels': ['in_app'],
              },
              {
                'role': 'teacher',
                'eventType': 'new_lead',
                'enabled': false,
                'channels': ['push'],
              },
            ],
          }
          as T;
    }
    if (path == '/profile/deletion-request') {
      return <String, dynamic>{
            'id': 'deletion-a',
            'status': 'pending',
            'reason': 'Больше не пользуюсь приложением',
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
    if (path.startsWith('/crm/phone-review-queue/')) {
      phoneResolution = body;
      phoneOpen = false;
      return <String, dynamic>{
            'id': 'phone-review-a',
            'action': body['action'],
            'resolvedPhone': '+79991234567',
          }
          as T;
    }
    if (path.startsWith('/admin/deletion-requests/')) {
      deletionStatus = body['status']?.toString() ?? deletionStatus;
      deletionStatuses.add(deletionStatus);
      return <String, dynamic>{'id': 'deletion-a', 'status': deletionStatus}
          as T;
    }
    if (path == '/profile/me' || path.startsWith('/auth/')) {
      credentialMutations.add('PATCH $path');
    }
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/admin/notifications/preferences') {
      credentialMutations.add('PUT $path');
    }
    return Map<String, dynamic>.from(data! as Map) as T;
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
            'id': 'deletion-a',
            'status': 'cancelled',
            'reason': 'Больше не пользуюсь приложением',
            'requestedAt': '2026-08-12T10:00:00.000Z',
          }
          as T;
    }
    throw StateError('Unexpected DELETE $path');
  }
}
