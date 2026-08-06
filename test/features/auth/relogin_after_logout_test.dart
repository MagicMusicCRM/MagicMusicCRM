import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/login_screen.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

/// Regression for the reported bug: «после входа и выхода из аккаунта в тот же
/// аккаунт с правильными данными не пускает». The backend issues a session on
/// every attempt (verified in prod audit), so the break is client-side — the
/// router keys off [magicAuthStateProvider], and after a logout→login cycle it
/// must observe the *new* session, otherwise the app stays stuck on /login.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('magicAuthStateProvider reflects the session after logout→login',
      () async {
    final store = MemoryMagicTokenStore();
    final adapter = _FakeAdapter();
    final service = MagicAuthService(_client(adapter, store));

    final container = ProviderContainer(
      overrides: [magicAuthServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    // The router permanently watches this provider in the real app.
    container.listen(magicAuthStateProvider, (_, _) {}, fireImmediately: true);
    await _settle();

    // ── First login ──────────────────────────────────────────────────────────
    adapter.enqueueLogin('access-1', 'refresh-1');
    await service.signInWithPassword(
      email: 'user@example.com',
      password: 'pw',
    );
    await _settle();
    expect(
      container.read(magicAuthStateProvider).asData?.value?.accessToken,
      'access-1',
      reason: 'first login should surface a session',
    );

    // ── Logout ───────────────────────────────────────────────────────────────
    await service.signOut();
    await _settle();
    expect(
      container.read(magicAuthStateProvider).asData?.value,
      isNull,
      reason: 'logout should clear the session',
    );

    // ── Second login (same account, correct credentials) ─────────────────────
    adapter.enqueueLogin('access-2', 'refresh-2');
    await service.signInWithPassword(
      email: 'user@example.com',
      password: 'pw',
    );
    await _settle();
    expect(
      container.read(magicAuthStateProvider).asData?.value?.accessToken,
      'access-2',
      reason: 'RE-LOGIN after logout must surface the new session — otherwise '
          'the router never leaves /login',
    );
  });

  testWidgets('login error keeps credentials and permits a retry',
      (tester) async {
    final store = MemoryMagicTokenStore();
    final adapter = _FakeAdapter();
    final service = MagicAuthService(_client(adapter, store));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicAuthServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'user@example.com');
    await tester.enterText(fields.at(1), 'correct-password');
    await tester.ensureVisible(find.text('Войти'));
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();

    expect(adapter.loginRequests, 1);
    expect(
      tester.widget<TextFormField>(fields.at(0)).controller?.text,
      'user@example.com',
    );
    expect(
      tester.widget<TextFormField>(fields.at(1)).controller?.text,
      'correct-password',
    );

    adapter.enqueueLogin('access-retry', 'refresh-retry');
    await tester.ensureVisible(find.text('Войти'));
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();

    expect(adapter.loginRequests, 2);
    expect((await service.currentSession())?.accessToken, 'access-retry');
  });
}

Future<void> _settle() async {
  // Let the broadcast stream + StreamProvider propagate across microtasks.
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

MagicApiClient _client(_FakeAdapter adapter, MemoryMagicTokenStore store) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.example.test',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return MagicApiClient(
    baseUrl: 'https://api.example.test',
    tokenStore: store,
    dio: dio,
  );
}

class _FakeAdapter implements HttpClientAdapter {
  final List<Map<String, Object?>> _loginBodies = [];
  int loginRequests = 0;

  void enqueueLogin(String access, String refresh) {
    _loginBodies.add({
      'user': {
        'id': 'user-a',
        'email': 'user@example.com',
        'role': 'client',
        'emailVerified': true,
      },
      'session': {
        'accessToken': access,
        'refreshToken': refresh,
        'tokenType': 'Bearer',
        'expiresIn': 900,
      },
    });
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/auth/login') {
      loginRequests++;
      if (_loginBodies.isNotEmpty) {
        return ResponseBody.fromString(
          jsonEncode(_loginBodies.removeAt(0)),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
    }
    return ResponseBody.fromString(
      jsonEncode({'message': 'unexpected ${options.uri.path}'}),
      500,
    );
  }

  @override
  void close({bool force = false}) {}
}
