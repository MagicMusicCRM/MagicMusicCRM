import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';

void main() {
  group('MagicAuthService', () {
    test('login saves v3 session and emits auth state', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/login',
          statusCode: 200,
          body: {
            'user': {
              'id': 'user-a',
              'email': 'user@example.com',
              'role': 'client',
              'emailVerified': true,
            },
            'session': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'tokenType': 'Bearer',
              'expiresIn': 900,
            },
          },
        ),
      ]);
      final store = MemoryMagicTokenStore();
      final service = MagicAuthService(_client(adapter, store));
      final states = <MagicAuthSession?>[];
      final subscription = service.watchSession().listen(states.add);

      final response = await service.signInWithPassword(
        email: 'user@example.com',
        password: 'password-123',
      );

      expect(response.user?.email, 'user@example.com');
      expect(response.hasSession, isTrue);
      expect((await store.read())?.accessToken, 'access-token');
      await Future<void>.delayed(Duration.zero);
      expect(states.last?.accessToken, 'access-token');
      await subscription.cancel();
    });

    test('signup keeps session empty until email verification/login', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/signup',
          statusCode: 201,
          body: {
            'user': {
              'id': 'user-a',
              'email': 'user@example.com',
              'role': 'client',
              'emailVerified': false,
            },
            'emailVerificationRequired': true,
          },
        ),
      ]);
      final store = MemoryMagicTokenStore();
      final service = MagicAuthService(_client(adapter, store));

      final response = await service.signUpWithPassword(
        email: 'user@example.com',
        password: 'password-123',
        fullName: 'User Example',
      );

      expect(response.emailVerificationRequired, isTrue);
      expect(response.hasSession, isFalse);
      expect(await store.read(), isNull);
    });

    test('signup clears an existing local session first', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/signup',
          statusCode: 201,
          body: {
            'user': {
              'id': 'user-b',
              'email': 'new@example.com',
              'role': 'client',
              'emailVerified': false,
            },
            'emailVerificationRequired': true,
          },
        ),
      ]);
      final store = MemoryMagicTokenStore(
        const MagicApiTokens(
          accessToken: 'old-access-token',
          refreshToken: 'old-refresh-token',
          tokenType: 'Bearer',
          expiresIn: 900,
        ),
      );
      final service = MagicAuthService(_client(adapter, store));

      await service.signUpWithPassword(
        email: 'new@example.com',
        password: 'password-123',
        fullName: 'New User',
      );

      expect(await store.read(), isNull);
    });

    test(
      'login reports email OTP requirement without saving a session',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/auth/login',
            statusCode: 200,
            body: {
              'user': {
                'id': 'user-a',
                'email': 'user@example.com',
                'role': 'client',
                'emailVerified': true,
              },
              'emailOtpRequired': true,
            },
          ),
        ]);
        final store = MemoryMagicTokenStore();
        final service = MagicAuthService(_client(adapter, store));

        final response = await service.signInWithPassword(
          email: 'user@example.com',
          password: 'password-123',
        );

        expect(response.emailOtpRequired, isTrue);
        expect(response.hasSession, isFalse);
        expect(await store.read(), isNull);
      },
    );

    test(
      'login OTP challenge clears an existing local session first',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/auth/login',
            statusCode: 200,
            body: {
              'user': {
                'id': 'user-b',
                'email': 'other@example.com',
                'role': 'client',
                'emailVerified': true,
              },
              'emailOtpRequired': true,
            },
          ),
        ]);
        final store = MemoryMagicTokenStore(
          const MagicApiTokens(
            accessToken: 'old-access-token',
            refreshToken: 'old-refresh-token',
            tokenType: 'Bearer',
            expiresIn: 900,
          ),
        );
        final service = MagicAuthService(_client(adapter, store));

        final response = await service.signInWithPassword(
          email: 'other@example.com',
          password: 'password-123',
        );

        expect(response.emailOtpRequired, isTrue);
        expect(await store.read(), isNull);
      },
    );

    test(
      'email OTP verification saves v3 session when backend returns tokens',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/auth/otp/verify',
            statusCode: 200,
            body: {
              'user': {
                'id': 'user-a',
                'email': 'user@example.com',
                'role': 'client',
                'emailVerified': true,
              },
              'session': {
                'accessToken': 'access-token',
                'refreshToken': 'refresh-token',
                'tokenType': 'Bearer',
                'expiresIn': 900,
              },
            },
          ),
        ]);
        final store = MemoryMagicTokenStore();
        final service = MagicAuthService(_client(adapter, store));

        final response = await service.verifyEmailOtp(
          email: 'user@example.com',
          token: '123456',
        );

        expect(response.hasSession, isTrue);
        expect((await store.read())?.accessToken, 'access-token');
        expect(adapter.requests.single.body, {
          'email': 'user@example.com',
          'code': '123456',
        });
      },
    );

    test('signup OTP without session clears stale local tokens', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/otp/verify',
          statusCode: 200,
          body: {
            'user': {
              'id': 'user-b',
              'email': 'new@example.com',
              'role': 'client',
              'emailVerified': true,
            },
          },
        ),
      ]);
      final store = MemoryMagicTokenStore(
        const MagicApiTokens(
          accessToken: 'old-access-token',
          refreshToken: 'old-refresh-token',
          tokenType: 'Bearer',
          expiresIn: 900,
        ),
      );
      final service = MagicAuthService(_client(adapter, store));

      final response = await service.verifySignupOtp(
        email: 'new@example.com',
        token: '123456',
      );

      expect(response.hasSession, isFalse);
      expect(await store.read(), isNull);
    });

    test('sets password through authenticated v3 endpoint', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(path: '/auth/password', statusCode: 200, body: null),
      ]);
      final store = MemoryMagicTokenStore(
        const MagicApiTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          tokenType: 'Bearer',
          expiresIn: 900,
        ),
      );
      final service = MagicAuthService(_client(adapter, store));

      await service.setPassword('new-strong-password-123');

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.body, {
        'password': 'new-strong-password-123',
      });
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer access-token',
      );
    });

    test('loads auth identities through authenticated v3 endpoint', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/identities',
          statusCode: 200,
          body: {
            'items': [
              {'provider': 'email'},
            ],
          },
        ),
      ]);
      final store = MemoryMagicTokenStore(
        const MagicApiTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          tokenType: 'Bearer',
          expiresIn: 900,
        ),
      );
      final service = MagicAuthService(_client(adapter, store));

      final identities = await service.getUserIdentities();

      expect(identities.map((item) => item.provider), ['email']);
      expect(adapter.requests.single.method, 'GET');
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer access-token',
      );
    });
  });
}

MagicApiClient _client(_FakeAdapter adapter, MemoryMagicTokenStore store) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.phantom-net.ru',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return MagicApiClient(
    baseUrl: 'https://api.phantom-net.ru',
    tokenStore: store,
    dio: dio,
  );
}

class _FakeResponse {
  final String path;
  final int statusCode;
  final Object? body;

  const _FakeResponse({
    required this.path,
    required this.statusCode,
    required this.body,
  });
}

class _FakeAdapter implements HttpClientAdapter {
  final List<_FakeResponse> _responses;
  final List<_CapturedRequest> requests = [];

  _FakeAdapter(this._responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_responses.isEmpty) {
      return ResponseBody.fromString(
        jsonEncode({'message': 'Unexpected request: ${options.path}'}),
        500,
      );
    }

    final response = _responses.removeAt(0);
    expect(options.uri.path, response.path);
    final requestBody = options.data is Map<String, dynamic>
        ? options.data as Map<String, dynamic>
        : <String, dynamic>{};
    requests.add(
      _CapturedRequest(
        method: options.method,
        body: requestBody,
        headers: options.headers,
      ),
    );
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CapturedRequest {
  final String method;
  final Map<String, dynamic> body;
  final Map<String, dynamic> headers;

  const _CapturedRequest({
    required this.method,
    required this.body,
    required this.headers,
  });
}
