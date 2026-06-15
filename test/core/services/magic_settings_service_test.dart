import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';

void main() {
  tearDown(() {
    MagicSettingsService.debugApiClientOverride = null;
  });

  test('reads and updates admin chat avatar through v3 settings API', () async {
    final adapter = _FakeAdapter([
      _FakeResponse(
        path: '/settings/admin-chat-avatar',
        statusCode: 200,
        body: {
          'key': 'admin_chat_avatar_url',
          'value': 'storage://avatars/admin/avatar.png',
          'updatedAt': '2026-06-12T00:00:00.000Z',
        },
      ),
      _FakeResponse(
        path: '/admin/settings/admin-chat-avatar',
        statusCode: 200,
        body: {
          'key': 'admin_chat_avatar_url',
          'value': 'storage://avatars/admin/avatar-2.png',
          'updatedAt': '2026-06-12T00:00:00.000Z',
        },
      ),
    ]);
    MagicSettingsService.debugApiClientOverride = _client(adapter);

    final avatar = await MagicSettingsService.getAdminChatAvatar();
    await MagicSettingsService.updateAdminChatAvatar(
      'storage://avatars/admin/avatar-2.png',
    );

    expect(avatar, 'storage://avatars/admin/avatar.png');
    expect(adapter.requests[0].method, 'GET');
    expect(adapter.requests[1].method, 'PATCH');
    expect(
      adapter.requests[1].body['url'],
      'storage://avatars/admin/avatar-2.png',
    );
  });

  test(
    'reads and updates CRM custom field schema through v3 settings API',
    () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/settings/crm-custom-fields',
          statusCode: 200,
          body: {
            'key': 'crm_custom_fields',
            'fields': [
              {
                'entity': 'students',
                'key': 'parentName',
                'label': 'Имя родителя',
                'type': 'text',
                'required': true,
                'hint': 'Контакт для связи',
              },
            ],
            'updatedAt': '2026-06-13T00:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/admin/settings/crm-custom-fields',
          statusCode: 200,
          body: {
            'key': 'crm_custom_fields',
            'fields': [
              {
                'entity': 'students',
                'key': 'parentName',
                'label': 'Имя родителя',
                'type': 'text',
                'required': false,
              },
              {
                'entity': 'leads',
                'key': 'discipline',
                'label': 'Направление',
                'type': 'select',
                'required': false,
                'options': ['Вокал', 'Гитара'],
              },
            ],
            'updatedAt': '2026-06-13T00:00:00.000Z',
          },
        ),
      ]);
      MagicSettingsService.debugApiClientOverride = _client(adapter);

      final fields = await MagicSettingsService.getCrmCustomFields();
      final saved = await MagicSettingsService.updateCrmCustomFields([
        const CrmCustomFieldDefinition(
          entity: 'students',
          key: 'parentName',
          label: 'Имя родителя',
          type: 'text',
        ),
        const CrmCustomFieldDefinition(
          entity: 'leads',
          key: 'discipline',
          label: 'Направление',
          type: 'select',
          options: ['Вокал', 'Гитара'],
        ),
      ]);

      expect(fields.single.required, isTrue);
      expect(saved, hasLength(2));
      expect(adapter.requests[0].method, 'GET');
      expect(adapter.requests[1].method, 'PATCH');
      expect(adapter.requests[1].body['fields'], [
        {
          'entity': 'students',
          'key': 'parentName',
          'label': 'Имя родителя',
          'type': 'text',
          'required': false,
        },
        {
          'entity': 'leads',
          'key': 'discipline',
          'label': 'Направление',
          'type': 'select',
          'required': false,
          'options': ['Вокал', 'Гитара'],
        },
      ]);
    },
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
  final Map<String, dynamic> body;

  const _CapturedRequest({required this.method, required this.body});
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
    requests.add(_CapturedRequest(method: options.method, body: requestBody));
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
