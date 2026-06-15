import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/hollihop_service.dart';
import 'package:magic_music_crm/core/services/magic_crm_reference_cache.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

void main() {
  group('MagicCrmReferenceCache', () {
    test('serves fresh CRM reference hits from memory', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/branches',
          body: {
            'items': [
              {'id': 'branch-a', 'name': 'Сокол'},
            ],
          },
        ),
      ]);
      final cache = _cache(adapter);

      final first = await cache.branches();
      final second = await cache.branches();

      expect(first.single['name'], 'Сокол');
      expect(second.single['id'], 'branch-a');
      expect(adapter.requests, ['/crm/branches']);
    });

    test('returns stale values while refreshing in the background', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/branches',
          body: {
            'items': [
              {'id': 'branch-a', 'name': 'Сокол'},
            ],
          },
        ),
        _FakeResponse(
          path: '/crm/branches',
          body: {
            'items': [
              {'id': 'branch-b', 'name': 'Спортивная'},
            ],
          },
        ),
      ]);
      final cache = _cache(adapter, ttl: const Duration(microseconds: -1));

      final fresh = await cache.branches();
      final stale = await cache.branches();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final refreshed = await cache.branches();

      expect(fresh.single['name'], 'Сокол');
      expect(stale.single['name'], 'Сокол');
      expect(refreshed.single['name'], 'Спортивная');
      expect(adapter.requests, ['/crm/branches', '/crm/branches']);
    });

    test('caches HolliHop string dictionaries including categories', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/hollihop/disciplines',
          body: {
            'items': ['Вокал'],
          },
        ),
        _FakeResponse(
          path: '/crm/hollihop/levels',
          body: {
            'items': ['Начальный'],
          },
        ),
        _FakeResponse(
          path: '/crm/hollihop/categories',
          body: {
            'items': ['Взрослые'],
          },
        ),
      ]);
      final cache = _cache(adapter);

      expect(await cache.disciplines(), ['Вокал']);
      expect(await cache.levels(), ['Начальный']);
      expect(await cache.categories(), ['Взрослые']);
      expect(await cache.categories(), ['Взрослые']);
      expect(adapter.requests, [
        '/crm/hollihop/disciplines',
        '/crm/hollihop/levels',
        '/crm/hollihop/categories',
      ]);
    });
  });
}

MagicCrmReferenceCache _cache(_FakeAdapter adapter, {Duration? ttl}) {
  final client = _client(adapter);
  return MagicCrmReferenceCache(
    crm: MagicCrmService(client),
    hollihop: HolliHopService(client),
    ttl: ttl ?? const Duration(minutes: 10),
  );
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
  final Object? body;

  const _FakeResponse({required this.path, required this.body});
}

class _FakeAdapter implements HttpClientAdapter {
  final List<_FakeResponse> _responses;
  final List<String> requests = [];

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
    requests.add(options.uri.path);
    expect(options.uri.path, response.path);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
