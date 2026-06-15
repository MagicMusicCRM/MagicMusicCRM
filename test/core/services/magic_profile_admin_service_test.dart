import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';

void main() {
  group('MagicProfileAdminService', () {
    test('lists profiles with legacy keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/admin/profiles',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'profile-a',
                'userId': 'user-a',
                'email': 'anna@example.com',
                'role': 'client',
                'firstName': 'Анна',
                'lastName': 'Иванова',
                'phone': '+79990000000',
                'dob': '2000-01-01',
                'createdAt': '2026-06-12T00:00:00.000Z',
                'updatedAt': '2026-06-12T00:00:00.000Z',
              },
            ],
            'total': 1,
          },
        ),
      ]);
      final service = MagicProfileAdminService(_client(adapter));

      final profiles = await service.listProfiles(q: 'Анна', limit: 10);

      expect(profiles.single['id'], 'profile-a');
      expect(profiles.single['user_id'], 'user-a');
      expect(profiles.single['first_name'], 'Анна');
      expect(profiles.single['created_at'], '2026-06-12T00:00:00.000Z');
      expect(adapter.requests.single.queryParameters['q'], 'Анна');
      expect(adapter.requests.single.queryParameters['limit'], 10);
    });

    test('updates role through admin endpoint', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/admin/profiles/profile-a/role',
          statusCode: 200,
          body: {
            'id': 'profile-a',
            'userId': 'user-a',
            'email': 'anna@example.com',
            'role': 'teacher',
            'firstName': 'Анна',
            'lastName': 'Иванова',
            'phone': null,
          },
        ),
      ]);
      final service = MagicProfileAdminService(_client(adapter));

      final profile = await service.updateRole(
        profileId: 'profile-a',
        role: 'teacher',
      );

      expect(profile['role'], 'teacher');
      expect(adapter.requests.single.body['role'], 'teacher');
    });

    test('lists profile notes with legacy keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/admin/profiles/profile-a/notes',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'note-a',
                'profileId': 'profile-a',
                'authorId': 'manager-a',
                'body': 'Позвонить перед занятием',
                'createdAt': '2026-06-13T10:00:00.000Z',
                'author': {
                  'id': 'manager-a',
                  'email': 'manager@example.com',
                  'firstName': 'Мария',
                  'lastName': 'Петрова',
                },
              },
            ],
          },
        ),
      ]);
      final service = MagicProfileAdminService(_client(adapter));

      final notes = await service.listProfileNotes('profile-a');

      expect(notes.single['id'], 'note-a');
      expect(notes.single['profile_id'], 'profile-a');
      expect(notes.single['content'], 'Позвонить перед занятием');
      expect(notes.single['author']['first_name'], 'Мария');
    });

    test('creates profile note through admin endpoint', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/admin/profiles/profile-a/notes',
          statusCode: 201,
          body: {
            'id': 'note-a',
            'profileId': 'profile-a',
            'authorId': 'manager-a',
            'body': 'Новая заметка',
            'createdAt': '2026-06-13T10:00:00.000Z',
            'author': null,
          },
        ),
      ]);
      final service = MagicProfileAdminService(_client(adapter));

      final note = await service.createProfileNote(
        profileId: 'profile-a',
        body: 'Новая заметка',
      );

      expect(note['body'], 'Новая заметка');
      expect(adapter.requests.single.body['body'], 'Новая заметка');
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
  final Map<String, dynamic> queryParameters;
  final Map<String, dynamic> body;

  const _CapturedRequest({required this.queryParameters, required this.body});
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
