import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';

void main() {
  const uncertainMessage =
      'Не удалось получить подтверждение. Действие могло сохраниться. '
      'Обновите данные и проверьте результат перед повтором.';

  for (final method in ['POST', 'PATCH', 'PUT', 'DELETE']) {
    for (final failure in [
      DioExceptionType.connectionError,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ]) {
      test(
        '$method does not repeat an uncertain write after $failure',
        () async {
          final adapter = _InterruptedAdapter(
            failure,
            savedBeforeFailure: true,
          );
          final client = _client(adapter);

          await expectLater(
            client.request<Map<String, dynamic>>(
              method,
              '/crm/students',
              data: {'firstName': 'Тест'},
            ),
            throwsA(
              isA<MagicApiException>().having(
                (error) => error.toUserMessage(),
                'message',
                uncertainMessage,
              ),
            ),
          );

          expect(adapter.requests, hasLength(1));
          expect(adapter.savedRows, 1);
        },
      );
    }

    test(
      '$method retries a connection timeout with the same metadata',
      () async {
        final adapter = _InterruptedAdapter(DioExceptionType.connectionTimeout);
        final response = await _client(adapter).request<Map<String, dynamic>>(
          method,
          '/crm/students',
          data: {'firstName': 'Тест'},
        );
        expect(response['savedRows'], 1);
        expect(adapter.requests, hasLength(2));
        for (final header in ['Idempotency-Key', 'X-Request-Id']) {
          expect(adapter.requests.first.headers[header], isNotEmpty);
          expect(
            adapter.requests.last.headers[header],
            adapter.requests.first.headers[header],
          );
        }
      },
    );
  }

  for (final method in ['GET', 'HEAD', 'OPTIONS']) {
    for (final failure in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('$method recovers from $failure', () async {
        final adapter = _InterruptedAdapter(failure);
        await _client(adapter).request<Object?>(method, '/crm/students');
        expect(adapter.requests, hasLength(2));
      });
    }
  }

  test('read retries are bounded when the network stays unavailable', () async {
    final adapter = _InterruptedAdapter(
      DioExceptionType.connectionError,
      alwaysFail: true,
    );
    await expectLater(
      _client(adapter).get<Object?>('/crm/students'),
      throwsA(isA<MagicApiException>()),
    );
    expect(adapter.requests, hasLength(2));
  });

  test(
    'a caller-owned identity alone does not authorize a transport replay',
    () async {
      final adapter = _InterruptedAdapter(
        DioExceptionType.connectionError,
        savedBeforeFailure: true,
      );
      await expectLater(
        _client(adapter).postIdempotent<Object?>(
          '/crm/students',
          identity: MagicMutationIdentity.create('student-create'),
          data: {'firstName': 'Тест'},
        ),
        throwsA(isA<MagicApiException>()),
      );
      expect(adapter.savedRows, 1);
      expect(adapter.requests, hasLength(1));
    },
  );
}

MagicApiClient _client(_InterruptedAdapter adapter) {
  const baseUrl = 'http://localhost';
  final dio = Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  return MagicApiClient(
    baseUrl: baseUrl,
    tokenStore: MemoryMagicTokenStore(),
    dio: dio,
  );
}

/// Models a server without idempotency support that may commit before the
/// transport fails. A retry creates another row even with identical headers.
class _InterruptedAdapter implements HttpClientAdapter {
  _InterruptedAdapter(
    this.failure, {
    this.savedBeforeFailure = false,
    this.alwaysFail = false,
  });

  final DioExceptionType failure;
  final bool savedBeforeFailure;
  final bool alwaysFail;
  final requests = <RequestOptions>[];
  int savedRows = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requests.length == 1 || alwaysFail) {
      if (savedBeforeFailure) savedRows++;
      throw DioException(requestOptions: options, type: failure);
    }
    savedRows++;
    return ResponseBody.fromString(
      jsonEncode({'savedRows': savedRows}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
