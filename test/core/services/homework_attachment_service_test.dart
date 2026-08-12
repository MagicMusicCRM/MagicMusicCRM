import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/homework_attachment_service.dart';

void main() {
  test('uploads and binds a homework assignment file', () async {
    final adapter = _FakeAdapter([
      const _FakeResponse(
        method: 'POST',
        path: '/api/files',
        statusCode: 201,
        body: {
          'id': 'file-a',
          'originalName': 'гаммы.pdf',
          'mimeType': 'application/pdf',
          'sizeBytes': 14,
        },
      ),
      const _FakeResponse(
        method: 'POST',
        path: '/api/crm/homeworks/homework-a/attachments',
        statusCode: 201,
        body: {'id': 'attachment-a'},
      ),
    ]);

    final result = await HomeworkAttachmentService(_client(adapter))
        .uploadAndAttach(
          homeworkId: 'homework-a',
          bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 test')),
          fileName: 'гаммы.pdf',
          kind: 'assignment',
        );

    expect(result, {
      'id': 'attachment-a',
      'fileId': 'file-a',
      'fileName': 'гаммы.pdf',
      'mimeType': 'application/pdf',
      'sizeBytes': 14,
      'kind': 'assignment',
    });
    expect(adapter.requests[0].formFields, {
      'purpose': 'homework_attachment',
      'ownerType': 'homework',
      'ownerId': 'homework-a',
    });
    expect(adapter.requests[0].fileName, 'гаммы.pdf');
    expect(adapter.requests[1].json, {
      'fileId': 'file-a',
      'kind': 'assignment',
    });
  });

  test('soft-deletes a new file when binding fails', () async {
    final adapter = _FakeAdapter([
      const _FakeResponse(
        method: 'POST',
        path: '/api/files',
        statusCode: 201,
        body: {'id': 'file-orphan'},
      ),
      const _FakeResponse(
        method: 'POST',
        path: '/api/crm/homeworks/homework-a/attachments',
        statusCode: 422,
        body: {'message': 'Не удалось привязать файл'},
      ),
      const _FakeResponse(
        method: 'DELETE',
        path: '/api/files/file-orphan',
        statusCode: 200,
        body: {'id': 'file-orphan'},
      ),
    ]);

    await expectLater(
      HomeworkAttachmentService(_client(adapter)).uploadAndAttach(
        homeworkId: 'homework-a',
        bytes: Uint8List.fromList(utf8.encode('answer')),
        fileName: 'answer.txt',
        kind: 'submission',
      ),
      throwsA(anything),
    );

    expect(adapter.requests.map((request) => request.method), [
      'POST',
      'POST',
      'DELETE',
    ]);
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
  const _FakeResponse({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.body,
  });

  final String method;
  final String path;
  final int statusCode;
  final Object? body;
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.formFields,
    required this.json,
    this.fileName,
  });

  final String method;
  final Map<String, String> formFields;
  final Map<String, dynamic> json;
  final String? fileName;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._responses);

  final List<_FakeResponse> _responses;
  final List<_CapturedRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = _responses.removeAt(0);
    expect(options.method, response.method);
    expect(options.uri.path, response.path);
    final data = options.data;
    if (data is FormData) {
      requests.add(
        _CapturedRequest(
          method: options.method,
          formFields: Map<String, String>.fromEntries(data.fields),
          json: const {},
          fileName: data.files.single.value.filename,
        ),
      );
    } else {
      requests.add(
        _CapturedRequest(
          method: options.method,
          formFields: const {},
          json: data is Map
              ? data.map((key, value) => MapEntry(key.toString(), value))
              : const {},
        ),
      );
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
