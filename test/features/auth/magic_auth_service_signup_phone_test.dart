import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';

void main() {
  group('MagicAuthService.signUpWithPassword phone threading', () {
    test('sends phone in POST body when phone is provided', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/signup',
          statusCode: 200,
          body: {
            'user': {
              'id': 'user-a',
              'email': 'a@b.c',
              'role': 'client',
              'emailVerified': false,
            },
            'emailVerificationRequired': true,
          },
        ),
      ]);
      final service = MagicAuthService(_client(adapter));

      await service.signUpWithPassword(
        email: 'a@b.c',
        password: 'xxxxxxxxxxxx',
        fullName: 'Иван',
        phone: '+79991234567',
      );

      expect(adapter.requests.single.body['phone'], '+79991234567');
    });

    test('omits phone key from POST body when phone is not provided', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/signup',
          statusCode: 200,
          body: {
            'user': {
              'id': 'user-b',
              'email': 'b@c.d',
              'role': 'client',
              'emailVerified': false,
            },
            'emailVerificationRequired': true,
          },
        ),
      ]);
      final service = MagicAuthService(_client(adapter));

      await service.signUpWithPassword(
        email: 'b@c.d',
        password: 'xxxxxxxxxxxx',
        fullName: 'Мария',
      );

      expect(adapter.requests.single.body.containsKey('phone'), isFalse);
    });

    test('omits phone key from POST body when phone is empty string', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/auth/signup',
          statusCode: 200,
          body: {
            'user': {
              'id': 'user-c',
              'email': 'c@d.e',
              'role': 'client',
              'emailVerified': false,
            },
            'emailVerificationRequired': true,
          },
        ),
      ]);
      final service = MagicAuthService(_client(adapter));

      await service.signUpWithPassword(
        email: 'c@d.e',
        password: 'xxxxxxxxxxxx',
        fullName: 'Петр',
        phone: '   ',
      );

      expect(adapter.requests.single.body.containsKey('phone'), isFalse);
    });
  });
}

MagicApiClient _client(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.phantom-net.ru',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return MagicApiClient(
    baseUrl: 'https://api.phantom-net.ru',
    tokenStore: MemoryMagicTokenStore(),
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

class _CapturedRequest {
  final String method;
  final Map<String, dynamic> queryParameters;
  final Map<String, dynamic> body;

  const _CapturedRequest({
    required this.method,
    required this.queryParameters,
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
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
        body: requestBody,
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
