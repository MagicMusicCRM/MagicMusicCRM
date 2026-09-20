import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/observability/app_performance.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, int) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options, requests.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody ok({int status = 200}) => ResponseBody.fromString(
  '{"ok":true}',
  status,
  headers: {
    'content-type': ['application/json'],
    'server-timing': ['app;dur=12.5, db;dur=8', 'pool;dur=1.25'],
  },
);

MagicApiClient _client(_Adapter adapter) => MagicApiClient(
  baseUrl: 'https://example.test/api',
  tokenStore: MemoryMagicTokenStore(),
  dio: Dio()..httpClientAdapter = adapter,
);

void main() {
  test(
    'correlates GET timing without retaining route values, headers or payloads',
    () async {
      final adapter = _Adapter((_, _) async => ok());
      final api = _client(adapter);
      await api.get<Map<String, dynamic>>(
        '/crm/students/private-student/card',
        queryParameters: {'email': 'private@example.test'},
      );
      final request = adapter.requests.single;
      expect(
        request.headers['X-Request-Id'],
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
      final metrics = AppPerformance.snapshot
          .where((r) => r['operationId'] == request.headers['X-Operation-Id'])
          .toList();
      expect(metrics.where((r) => r['kind'] == 'operation'), hasLength(1));
      final http = metrics.singleWhere((r) => r['kind'] == 'http');
      expect(http, containsPair('serverMs', 12.5));
      expect(http, containsPair('dbQueryMs', 8.0));
      expect(http, containsPair('dbAcquireMs', 1.25));
      expect(jsonEncode(metrics), isNot(contains('private')));
      expect(jsonEncode(metrics), isNot(contains('Authorization')));
    },
  );

  test(
    'measures failed attempts and keeps command identity across connection retries',
    () async {
      final adapter = _Adapter((options, attempt) async {
        if (attempt == 1) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        }
        return ok();
      });
      await _client(adapter).post<Map<String, dynamic>>(
        '/crm/lessons/private/settle',
        data: {'private': 'secret'},
      );
      final ids = adapter.requests
          .map((r) => r.headers['X-Request-Id'])
          .toSet();
      expect(ids, hasLength(1));
      expect(
        adapter.requests.map((r) => r.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      final metrics = AppPerformance.snapshot
          .where((r) => r['requestId'] == ids.single)
          .toList();
      expect(metrics, hasLength(2));
      expect(metrics.first['errorType'], 'connectionTimeout');
      expect(metrics.last['statusCode'], 200);
      expect(metrics.map((r) => r['operationId']).toSet(), hasLength(1));
    },
  );

  test('server errors are measured and still reach the caller', () async {
    final adapter = _Adapter((_, _) async => ok(status: 503));
    await expectLater(
      _client(adapter).get<Map<String, dynamic>>('/private'),
      throwsA(isA<MagicApiException>()),
    );
    final id = adapter.requests.single.headers['X-Operation-Id'];
    final metrics = AppPerformance.snapshot
        .where((r) => r['operationId'] == id)
        .toList();
    expect(metrics.singleWhere((r) => r['kind'] == 'http')['statusCode'], 503);
    expect(
      metrics.singleWhere((r) => r['kind'] == 'operation')['outcome'],
      'error',
    );
  });

  test(
    'parallel operations remain isolated while nested requests share a context',
    () async {
      final adapter = _Adapter((_, _) async => ok());
      final api = _client(adapter);
      await Future.wait([
        AppPerformance.measure(AppOperation.schedule, () async {
          await Future<void>.delayed(Duration.zero);
          await api.get<Map<String, dynamic>>('/schedule-first');
          await api.get<Map<String, dynamic>>('/schedule-second');
        }),
        AppPerformance.measure(
          AppOperation.studentCard,
          () => api.get<Map<String, dynamic>>('/student'),
        ),
      ]);
      final schedule = adapter.requests
          .where((r) => r.path.contains('schedule'))
          .toList();
      expect(
        schedule.map((r) => r.headers['X-Operation-Id']).toSet(),
        hasLength(1),
      );
      expect(
        schedule.first.headers['X-Operation-Id'],
        isNot(
          adapter.requests
              .singleWhere((r) => r.path == 'student')
              .headers['X-Operation-Id'],
        ),
      );
      expect(AppPerformance.current, isNull);
    },
  );

  test('diagnostic memory stays bounded', () {
    for (var i = 0; i < 300; i++) {
      AppPerformance.record({'kind': 'test', 'durationMs': i});
    }
    expect(AppPerformance.snapshot, hasLength(AppPerformance.capacity));
    expect(AppPerformance.snapshot.first['durationMs'], 100);
  });
}
