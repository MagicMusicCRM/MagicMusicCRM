import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';

void main() {
  group('MagicNotificationsService', () {
    test('lists and marks notifications through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/notifications',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'notification-a',
                'type': 'admin_broadcast',
                'title': 'Сообщение от школы',
                'body': 'Важная новость',
                'data': {'route': 'notifications'},
                'createdBy': 'admin-a',
                'createdAt': '2026-06-13T12:00:00.000Z',
                'isRead': false,
                'readAt': null,
                'deliveredAt': null,
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/notifications/notification-a/read',
          statusCode: 201,
          body: {
            'id': 'notification-a',
            'type': 'admin_broadcast',
            'title': 'Сообщение от школы',
            'body': 'Важная новость',
            'data': {'route': 'notifications'},
            'createdBy': 'admin-a',
            'createdAt': '2026-06-13T12:00:00.000Z',
            'isRead': true,
            'readAt': '2026-06-13T12:01:00.000Z',
            'deliveredAt': null,
          },
        ),
        _FakeResponse(
          path: '/notifications/read-all',
          statusCode: 201,
          body: {'success': true},
        ),
      ]);
      final service = MagicNotificationsService(_client(adapter));

      final notifications = await service.list(unread: true, limit: 20);
      final updated = await service.markRead('notification-a');
      await service.markAllRead();

      expect(notifications.single['id'], 'notification-a');
      expect(notifications.single['is_read'], isFalse);
      expect(notifications.single['created_at'], '2026-06-13T12:00:00.000Z');
      expect(updated['is_read'], isTrue);
      expect(adapter.requests[0].queryParameters['unread'], true);
      expect(adapter.requests[0].queryParameters['limit'], 20);
    });

    test('sends admin broadcasts with role target and push channel', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/admin/notifications',
          statusCode: 201,
          body: {'notificationId': 'notification-a', 'recipientCount': 12},
        ),
      ]);
      final service = MagicNotificationsService(_client(adapter));

      final result = await service.adminSend(
        target: 'role',
        role: 'client',
        title: ' Сообщение от школы ',
        body: ' Важная новость ',
        data: const {'route': 'notifications'},
      );

      expect(result['recipientCount'], 12);
      expect(adapter.requests.single.body['target'], 'role');
      expect(adapter.requests.single.body['role'], 'client');
      expect(adapter.requests.single.body['title'], 'Сообщение от школы');
      expect(adapter.requests.single.body['body'], 'Важная новость');
      expect(adapter.requests.single.body['channels'], ['in_app', 'push']);
    });

    test('registers and deletes push devices through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/notifications/devices',
          statusCode: 201,
          body: {
            'id': 'device-a',
            'userId': 'user-a',
            'platform': 'android',
            'tokenHash': 'hash-a',
            'enabled': true,
            'lastSeenAt': '2026-06-13T12:00:00.000Z',
            'createdAt': '2026-06-13T12:00:00.000Z',
            'updatedAt': '2026-06-13T12:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/notifications/devices/device-a',
          statusCode: 200,
          body: {'success': true},
        ),
      ]);
      final service = MagicNotificationsService(_client(adapter));

      final device = await service.registerDevice(
        token: 'fcm-token-with-enough-length',
        platform: 'android',
      );
      await service.deleteDevice('device-a');

      expect(device['id'], 'device-a');
      expect(device['user_id'], 'user-a');
      expect(device['token_hash'], 'hash-a');
      expect(adapter.requests.first.method, 'POST');
      expect(
        adapter.requests.first.body['token'],
        'fcm-token-with-enough-length',
      );
      expect(adapter.requests.first.body['platform'], 'android');
      expect(adapter.requests.last.method, 'DELETE');
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
