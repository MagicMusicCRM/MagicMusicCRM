import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/services/notification_service.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_release_gate_service.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/account_deletion_status_screen.dart';
import 'package:magic_music_crm/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts and reaches the login gate without credentials', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicTokenStoreProvider.overrideWithValue(MemoryMagicTokenStore()),
          magicAuthServiceProvider.overrideWith(
            (_) => _DelayedUnauthenticatedAuthService(),
          ),
          notificationServiceProvider.overrideWith(
            _NoopNotificationService.new,
          ),
        ],
        child: const MagicMusicApp(),
      ),
    );

    await _pumpUntilVisible(tester, find.text('Вход в систему'));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.light);
    expect(app.themeMode, ThemeMode.light);

    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.text('Телефон или почта'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Забыли пароль?'), findsOneWidget);
    expect(find.text('Создать аккаунт'), findsOneWidget);

    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();

    expect(find.text('Введите корректную почту'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
  });

  testWidgets('submits the account deletion form without backend secrets', (
    tester,
  ) async {
    final releaseGate = _FakeReleaseGateService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicTokenStoreProvider.overrideWithValue(MemoryMagicTokenStore()),
          magicAuthServiceProvider.overrideWith(
            (_) => _AuthenticatedAuthService(),
          ),
          releaseGateServiceProvider.overrideWithValue(releaseGate),
          routerProvider.overrideWithValue(_accountDeletionSmokeRouter()),
          notificationServiceProvider.overrideWith(
            _NoopNotificationService.new,
          ),
        ],
        child: const MagicMusicApp(),
      ),
    );

    await _pumpUntilVisible(tester, find.text('Удалить аккаунт'));

    expect(
      find.textContaining('Запрос на удаление аккаунта будет отправлен'),
      findsOneWidget,
    );
    expect(find.text('Причина обращения'), findsOneWidget);
    expect(find.text('Отправить запрос'), findsOneWidget);
    expect(_submitButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byType(TextField),
      'Прошу удалить тестовый аккаунт',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(_submitButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Отправить запрос'));
    await tester.pumpAndSettle();

    expect(releaseGate.requestedReason, 'Прошу удалить тестовый аккаунт');
    expect(find.text('Запрос принят'), findsOneWidget);
    expect(
      find.textContaining('Администрация проверит запрос'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $finder');
}

class _NoopNotificationService extends NotificationService {
  _NoopNotificationService(super.ref);

  @override
  Future<void> setupNotifications() async {}

  @override
  Future<void> syncCurrentDeviceToken() async {}
}

class _DelayedUnauthenticatedAuthService extends MagicAuthService {
  _DelayedUnauthenticatedAuthService()
    : super(
        MagicApiClient(
          baseUrl: 'https://integration.invalid/api',
          tokenStore: MemoryMagicTokenStore(),
        ),
      );

  @override
  Future<MagicAuthSession?> currentSession() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return null;
  }

  @override
  Stream<MagicAuthSession?> watchSession() async* {
    yield await currentSession();
  }
}

GoRouter _accountDeletionSmokeRouter() {
  return GoRouter(
    initialLocation: '/delete-account',
    routes: [
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const AccountDeletionScreen(),
      ),
      GoRoute(
        path: '/account-deletion-status',
        builder: (context, state) => const AccountDeletionStatusScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );
}

FilledButton _submitButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Отправить запрос'),
  );
}

class _AuthenticatedAuthService extends MagicAuthService {
  _AuthenticatedAuthService()
    : super(
        MagicApiClient(
          baseUrl: 'https://integration.invalid/api',
          tokenStore: MemoryMagicTokenStore(),
        ),
      );

  static const _session = MagicAuthSession(
    accessToken: 'integration-access-token',
    refreshToken: 'integration-refresh-token',
  );

  @override
  Future<MagicAuthSession?> currentSession() async => _session;

  @override
  Stream<MagicAuthSession?> watchSession() async* {
    yield _session;
  }

  @override
  Future<void> signOut() async {}
}

class _FakeReleaseGateService extends MagicReleaseGateService {
  _FakeReleaseGateService()
    : super(
        MagicApiClient(
          baseUrl: 'https://integration.invalid/api',
          tokenStore: MemoryMagicTokenStore(),
        ),
      );

  String? requestedReason;
  bool _deletionPending = false;

  @override
  Future<ReleaseGateStatus> getGateStatus() async {
    return ReleaseGateStatus(
      role: 'client',
      profileComplete: true,
      legalAccepted: true,
      deletionPending: _deletionPending,
    );
  }

  @override
  Future<String> requestAccountDeletion({String? reason}) async {
    requestedReason = reason;
    _deletionPending = true;
    return 'deletion-request-1';
  }

  @override
  Future<AccountDeletionRequest?> getPendingDeletionRequest() async {
    if (!_deletionPending) return null;
    return AccountDeletionRequest(
      id: 'deletion-request-1',
      status: 'pending',
      requestedAt: DateTime.utc(2026, 6, 15),
      reason: requestedReason,
    );
  }
}
