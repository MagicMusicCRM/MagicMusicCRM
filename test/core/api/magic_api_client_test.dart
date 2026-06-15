import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_tokens.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';

void main() {
  group('MagicApiClient', () {
    test('adds bearer token to authenticated requests', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(path: '/profile/me', statusCode: 200, body: {'ok': true}),
      ]);
      final client = _client(
        adapter,
        tokens: const MagicApiTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          tokenType: 'Bearer',
          expiresIn: 900,
        ),
      );

      final response = await client.get<Map<String, dynamic>>('/profile/me');

      expect(response['ok'], isTrue);
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer access-token',
      );
    });

    test(
      'refreshes once after unauthorized response and retries request',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/profile/me',
            statusCode: 401,
            body: {'message': 'Unauthorized'},
          ),
          _FakeResponse(
            path: '/auth/refresh',
            statusCode: 200,
            body: {
              'session': {
                'accessToken': 'next-access-token',
                'refreshToken': 'next-refresh-token',
                'tokenType': 'Bearer',
                'expiresIn': 900,
              },
            },
          ),
          _FakeResponse(
            path: '/profile/me',
            statusCode: 200,
            body: {'id': 'user-a'},
          ),
        ]);
        final store = MemoryMagicTokenStore(
          const MagicApiTokens(
            accessToken: 'expired-access-token',
            refreshToken: 'refresh-token',
            tokenType: 'Bearer',
            expiresIn: 900,
          ),
        );
        final client = _client(adapter, store: store);

        final response = await client.get<Map<String, dynamic>>('/profile/me');

        expect(response['id'], 'user-a');
        expect(
          adapter.requests.last.headers['Authorization'],
          'Bearer next-access-token',
        );
        expect((await store.read())?.refreshToken, 'next-refresh-token');
      },
    );

    test('shares one refresh across parallel unauthorized requests', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/profile/me',
          statusCode: 401,
          body: {'message': 'Unauthorized'},
        ),
        _FakeResponse(
          path: '/crm/overview',
          statusCode: 401,
          body: {'message': 'Unauthorized'},
        ),
        _FakeResponse(
          path: '/auth/refresh',
          statusCode: 200,
          delay: const Duration(milliseconds: 20),
          body: {
            'session': {
              'accessToken': 'next-access-token',
              'refreshToken': 'next-refresh-token',
              'tokenType': 'Bearer',
              'expiresIn': 900,
            },
          },
        ),
        _FakeResponse(
          path: '/profile/me',
          statusCode: 200,
          body: {'id': 'user-a'},
        ),
        _FakeResponse(
          path: '/crm/overview',
          statusCode: 200,
          body: {'ok': true},
        ),
      ]);
      final store = MemoryMagicTokenStore(
        const MagicApiTokens(
          accessToken: 'expired-access-token',
          refreshToken: 'refresh-token',
          tokenType: 'Bearer',
          expiresIn: 900,
        ),
      );
      final client = _client(adapter, store: store);

      final responses = await Future.wait([
        client.get<Map<String, dynamic>>('/profile/me'),
        client.get<Map<String, dynamic>>('/crm/overview'),
      ]);

      expect(responses.first['id'], 'user-a');
      expect(responses.last['ok'], isTrue);
      expect(
        adapter.requests.where(
          (request) => request.uri.path == '/auth/refresh',
        ),
        hasLength(1),
      );
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer next-access-token',
      );
      expect((await store.read())?.refreshToken, 'next-refresh-token');
    });

    test('clears tokens when refresh fails', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/profile/me',
          statusCode: 401,
          body: {'message': 'Unauthorized'},
        ),
        _FakeResponse(
          path: '/auth/refresh',
          statusCode: 401,
          body: {'message': 'Refresh expired'},
        ),
      ]);
      final store = MemoryMagicTokenStore(
        const MagicApiTokens(
          accessToken: 'expired-access-token',
          refreshToken: 'refresh-token',
          tokenType: 'Bearer',
          expiresIn: 900,
        ),
      );
      final client = _client(adapter, store: store);

      await expectLater(
        client.get<Map<String, dynamic>>('/profile/me'),
        throwsA(isA<MagicApiException>()),
      );
      expect(await store.read(), isNull);
    });

    test('maps backend validation errors to typed exception', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/login',
          statusCode: 400,
          body: {
            'message': ['email must be an email'],
            'error': 'Bad Request',
            'statusCode': 400,
          },
        ),
      ]);
      final client = _client(adapter);

      await expectLater(
        client.post<Map<String, dynamic>>(
          '/auth/login',
          data: {'email': 'bad'},
          authenticated: false,
        ),
        throwsA(
          isA<MagicApiException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having(
                (error) => error.message,
                'message',
                'email must be an email',
              ),
        ),
      );
    });

    test('keeps base URL path prefix for v3 API deployments', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/api/health',
          statusCode: 200,
          body: {'status': 'ok'},
        ),
      ]);
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.phantom-net.ru/api/',
          validateStatus: (status) => status != null && status < 400,
        ),
      )..httpClientAdapter = adapter;
      final client = MagicApiClient(
        baseUrl: 'https://api.phantom-net.ru/api',
        tokenStore: MemoryMagicTokenStore(),
        dio: dio,
      );

      final response = await client.get<Map<String, dynamic>>(
        '/health',
        authenticated: false,
      );

      expect(response['status'], 'ok');
    });

    test(
      'sends PUT requests through the shared authenticated pipeline',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/messages/msg-a/reactions/like',
            statusCode: 200,
            body: {'messageId': 'msg-a'},
          ),
        ]);
        final client = _client(
          adapter,
          tokens: const MagicApiTokens(
            accessToken: 'access-token',
            refreshToken: 'refresh-token',
            tokenType: 'Bearer',
            expiresIn: 900,
          ),
        );

        final response = await client.put<Map<String, dynamic>>(
          '/messenger/messages/msg-a/reactions/like',
        );

        expect(response['messageId'], 'msg-a');
        expect(adapter.requests.single.method, 'PUT');
        expect(
          adapter.requests.single.headers['Authorization'],
          'Bearer access-token',
        );
      },
    );
  });
}

MagicApiClient _client(
  _FakeAdapter adapter, {
  MagicApiTokens? tokens,
  MemoryMagicTokenStore? store,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.phantom-net.ru',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return MagicApiClient(
    baseUrl: 'https://api.phantom-net.ru',
    tokenStore: store ?? MemoryMagicTokenStore(tokens),
    dio: dio,
  );
}

class _FakeResponse {
  final String path;
  final int statusCode;
  final Object? body;
  final Duration delay;

  const _FakeResponse({
    required this.path,
    required this.statusCode,
    required this.body,
    this.delay = Duration.zero,
  });
}

class _FakeAdapter implements HttpClientAdapter {
  final List<_FakeResponse> _responses;
  final List<RequestOptions> requests = [];

  _FakeAdapter(this._responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_responses.isEmpty) {
      return ResponseBody.fromString(
        jsonEncode({'message': 'Unexpected request: ${options.path}'}),
        500,
      );
    }

    final response = _responses.removeAt(0);
    expect(options.uri.path, response.path);
    if (response.delay > Duration.zero) {
      await Future<void>.delayed(response.delay);
    }
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
