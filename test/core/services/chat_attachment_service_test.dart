import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';

void main() {
  test(
    'uploads chat attachments through v3 File API multipart contract',
    () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/api/files',
          statusCode: 201,
          body: {
            'id': 'file-a',
            'purpose': 'chat_attachment',
            'ownerType': 'chat',
            'ownerId': 'chat-a',
          },
        ),
      ]);
      final service = ChatAttachmentService(_client(adapter));

      final id = await service.uploadFile(
        bytes: Uint8List.fromList(utf8.encode('hello')),
        originalFileName: 'note.txt',
        senderId: 'user-a',
        chatId: 'chat-a',
      );

      expect(id, 'file-a');
      expect(adapter.requests.single.formFields['purpose'], 'chat_attachment');
      expect(adapter.requests.single.formFields['ownerType'], 'chat');
      expect(adapter.requests.single.formFields['ownerId'], 'chat-a');
      expect(adapter.requests.single.fileName, 'note.txt');
    },
  );

  test('uploads voice messages with chat_voice purpose', () async {
    final adapter = _FakeAdapter([
      _FakeResponse(
        path: '/api/files',
        statusCode: 201,
        body: {'id': 'voice-file-a'},
      ),
    ]);
    final service = ChatAttachmentService(_client(adapter));

    final id = await service.uploadVoice(
      bytes: Uint8List.fromList([1, 2, 3]),
      senderId: 'user-a',
      chatId: 'chat-a',
      extension: '.webm',
    );

    expect(id, 'voice-file-a');
    expect(adapter.requests.single.formFields['purpose'], 'chat_voice');
    expect(adapter.requests.single.formFields['ownerType'], 'chat');
    expect(adapter.requests.single.formFields['ownerId'], 'chat-a');
    expect(adapter.requests.single.contentType, 'audio/webm');
  });

  test('resolves v3 file ids through signed download tokens', () async {
    final adapter = _FakeAdapter([
      _FakeResponse(
        path: '/api/files/file-a/download-token',
        statusCode: 201,
        body: {'token': 'download-token-a'},
      ),
    ]);
    final service = ChatAttachmentService(_client(adapter));

    final url = await service.resolveUrl('file-a');

    expect(
      url,
      'https://api.phantom-net.ru/api/files/download/download-token-a',
    );
  });

  test('deduplicates concurrent signed download token requests', () async {
    final adapter = _FakeAdapter([
      _FakeResponse(
        path: '/api/files/file-a/download-token',
        statusCode: 201,
        body: {'token': 'download-token-a'},
      ),
    ]);
    final service = ChatAttachmentService(_client(adapter));

    final urls = await Future.wait([
      service.resolveUrl('file-a'),
      service.resolveUrl('file-a'),
    ]);

    expect(urls, [
      'https://api.phantom-net.ru/api/files/download/download-token-a',
      'https://api.phantom-net.ru/api/files/download/download-token-a',
    ]);
    expect(adapter.requests, hasLength(1));
  });

  test(
    'does not try to sign legacy storage references through Supabase SDK',
    () async {
      final service = ChatAttachmentService(_client(_FakeAdapter(const [])));
      final url = await service.resolveUrl(
        'storage://chat-attachments/user-a/file.png',
      );

      expect(url, isNull);
    },
  );

  test(
    'passes through ordinary external HTTPS URLs without Supabase rewrite',
    () async {
      final service = ChatAttachmentService(_client(_FakeAdapter(const [])));
      final url = await service.resolveUrl(
        'https://cdn.example.com/uploads/file.png?sig=abc',
      );

      expect(url, 'https://cdn.example.com/uploads/file.png?sig=abc');
    },
  );

  test('sanitizes download file names before saving locally', () {
    expect(
      ChatAttachmentService.safeDownloadFileName('../secret/report.pdf'),
      'report.pdf',
    );
    expect(
      ChatAttachmentService.safeDownloadFileName(r'C:\temp\audio?.mp3'),
      'audio_.mp3',
    );
    expect(ChatAttachmentService.safeDownloadFileName('  '), 'download');
    expect(ChatAttachmentService.safeDownloadFileName('..'), 'download');
    expect(
      ChatAttachmentService.safeDownloadFileName('bad<name>|file.txt'),
      'bad_name__file.txt',
    );
    expect(
      ChatAttachmentService.safeDownloadFileName('${'a' * 160}.txt').length,
      120,
    );
  });
}

MagicApiClient _client(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.phantom-net.ru/api',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return MagicApiClient(
    baseUrl: 'https://api.phantom-net.ru/api',
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
  final Map<String, String> formFields;
  final String? fileName;
  final String? contentType;

  const _CapturedRequest({
    required this.formFields,
    this.fileName,
    this.contentType,
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
    final data = options.data;
    if (data is FormData) {
      requests.add(
        _CapturedRequest(
          formFields: Map<String, String>.fromEntries(data.fields),
          fileName: data.files.single.value.filename,
          contentType: data.files.single.value.contentType?.mimeType,
        ),
      );
    } else {
      requests.add(const _CapturedRequest(formFields: {}));
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
