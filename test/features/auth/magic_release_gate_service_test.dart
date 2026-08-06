import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_release_gate_service.dart';

void main() {
  group('MagicReleaseGateService', () {
    test(
      'loads release gate status through a single v3 gate request',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/legal/gate',
            statusCode: 200,
            body: {
              'role': 'manager',
              'profileComplete': true,
              'legalAccepted': true,
              'deletionPending': false,
            },
          ),
        ]);
        final service = _service(adapter);

        final status = await service.getGateStatus();

        expect(status.role, 'manager');
        expect(status.profileComplete, isTrue);
        expect(status.legalAccepted, isTrue);
        expect(status.deletionPending, isFalse);
        expect(adapter.requests.single.method, 'GET');
      },
    );

    test('completes onboarding with trimmed required profile fields', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(path: '/profile/me', statusCode: 200, body: const {}),
      ]);
      final service = _service(adapter);

      await service.completeOnboarding(
        firstName: '  Анна ',
        lastName: '  Иванова ',
        phone: ' +79991234567 ',
      );

      expect(adapter.requests.single.method, 'PATCH');
      expect(adapter.requests.single.body, {
        'firstName': 'Анна',
        'lastName': 'Иванова',
        'phone': '+79991234567',
      });
    });

    test('loads current legal documents and accepts their exact ids', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/legal/documents/current',
          statusCode: 200,
          body: [
            {
              'id': 'terms-v1',
              'type': 'terms_of_use',
              'version': '1',
              'title': 'Условия',
              'contentHash': 'terms-hash',
            },
            {
              'id': 'privacy-v2',
              'type': 'privacy_policy',
              'version': '2',
              'title': 'Политика',
              'contentHash': 'privacy-hash',
            },
          ],
        ),
        _FakeResponse(
          path: '/legal/documents/current',
          statusCode: 200,
          body: [
            {'id': 'terms-v1'},
            {'id': 'privacy-v2'},
          ],
        ),
        _FakeResponse(
          path: '/legal/consents/current',
          statusCode: 200,
          body: const {},
        ),
      ]);
      final service = _service(adapter);

      final documents = await service.getCurrentLegalDocuments();
      await service.acceptCurrentLegalDocuments();

      expect(documents.map((document) => document.id), [
        'terms-v1',
        'privacy-v2',
      ]);
      expect(
        documents.first.publicUrl,
        'https://magicmusiccrm-legal.vercel.app/terms/',
      );
      expect(adapter.requests.last.method, 'POST');
      expect(adapter.requests.last.body, {
        'documentIds': ['terms-v1', 'privacy-v2'],
      });
    });

    test('requests account deletion with required acknowledgement', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/profile/deletion-request',
          statusCode: 201,
          body: {'id': 'request-a'},
        ),
      ]);
      final service = _service(adapter);

      final id = await service.requestAccountDeletion(
        reason: '  Больше не пользуюсь приложением  ',
      );

      expect(id, 'request-a');
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.body, {
        'acknowledgement': true,
        'reason': 'Больше не пользуюсь приложением',
      });
    });

    test('omits empty account deletion reason', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/profile/deletion-request',
          statusCode: 201,
          body: {'id': 'request-b'},
        ),
      ]);
      final service = _service(adapter);

      await service.requestAccountDeletion(reason: '   ');

      expect(adapter.requests.single.body, {'acknowledgement': true});
    });

    test('maps pending deletion request from v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/profile/deletion-request',
          statusCode: 200,
          body: {
            'id': 'request-c',
            'status': 'processing',
            'reason': 'Удаление',
            'requestedAt': '2026-06-13T10:00:00.000Z',
          },
        ),
      ]);
      final service = _service(adapter);

      final request = await service.getPendingDeletionRequest();

      expect(request?.id, 'request-c');
      expect(request?.status, 'processing');
      expect(request?.reason, 'Удаление');
      expect(
        request?.requestedAt.toUtc().toIso8601String(),
        startsWith('2026-06-13T10:00:00.000'),
      );
      expect(adapter.requests.single.method, 'GET');
    });

    test(
      'ensures administration chat thread through v3 messenger API',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/chats/direct',
            statusCode: 201,
            body: {'id': 'chat-administration'},
          ),
        ]);
        final service = _service(adapter);

        final chatId = await service.ensureAdminChatThread();

        expect(chatId, 'chat-administration');
        expect(adapter.requests.single.method, 'POST');
        expect(adapter.requests.single.body, {'type': 'administration'});
      },
    );
  });
}

MagicReleaseGateService _service(_FakeAdapter adapter) {
  final api = _client(adapter);
  return MagicReleaseGateService(api);
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
