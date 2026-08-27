import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';

import 'messenger_test_api.dart';

class _ChatInfoApi extends RecordingFakeApiClient {
  _ChatInfoApi() : super(profileRole: 'manager');

  final List<String> orderedGets = [];
  final List<Map<String, dynamic>> messageQueries = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    orderedGets.add(path);
    calls.add((method: 'GET', path: path, data: null));

    final chatMatch = RegExp(r'^/messenger/chats/([^/]+)$').firstMatch(path);
    if (chatMatch != null) {
      final chatId = chatMatch.group(1)!;
      return <String, dynamic>{
            'id': chatId,
            'type': 'direct',
            'firstName': chatId == 'direct-old' ? 'Старый' : 'Новый',
            'lastName': 'Контакт',
            'isMuted': false,
          }
          as T;
    }

    final membersMatch = RegExp(
      r'^/messenger/chats/([^/]+)/members$',
    ).firstMatch(path);
    if (membersMatch != null) {
      final chatId = membersMatch.group(1)!;
      return <String, dynamic>{
            'items': [
              {
                'profileId': 'profile-current',
                'userId': 'user-current',
                'firstName': 'Текущий',
                'lastName': 'Пользователь',
                'role': 'member',
                'userRole': 'manager',
                'isCurrentUser': true,
              },
              {
                'profileId': chatId == 'direct-old'
                    ? 'profile-old'
                    : 'profile-new',
                'userId': chatId == 'direct-old' ? 'user-old' : 'user-new',
                'firstName': chatId == 'direct-old' ? 'Старый' : 'Новый',
                'lastName': 'Участник',
                'role': 'member',
                'userRole': 'client',
                'email': '$chatId@example.com',
                'isCurrentUser': false,
              },
            ],
          }
          as T;
    }

    final messagesMatch = RegExp(
      r'^/messenger/chats/([^/]+)/messages$',
    ).firstMatch(path);
    if (messagesMatch != null) {
      messageQueries.add(
        Map<String, dynamic>.from(queryParameters ?? const {}),
      );
      final chatId = messagesMatch.group(1)!;
      return <String, dynamic>{'items': _messages(chatId)} as T;
    }

    final notesMatch = RegExp(
      r'^/admin/profiles/([^/]+)/notes$',
    ).firstMatch(path);
    if (notesMatch != null) {
      final profileId = notesMatch.group(1)!;
      return <String, dynamic>{
            'items': [
              {
                'id': 'note-$profileId',
                'profileId': profileId,
                'body': profileId == 'profile-old'
                    ? 'Старая заметка'
                    : 'Новая заметка',
                'createdAt': '2026-08-26T10:00:00Z',
              },
            ],
          }
          as T;
    }

    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  List<Map<String, dynamic>> _messages(String chatId) {
    final prefix = chatId == 'direct-old' ? 'old' : 'new';
    return [
      {
        'id': '$prefix-link',
        'chatId': chatId,
        'content': 'Открыть https://$prefix.example.test',
        'messageType': 'text',
      },
      {
        'id': '$prefix-voice',
        'chatId': chatId,
        'content': '',
        'messageType': 'voice',
        'attachmentFileId': '$prefix-voice-file',
        'attachmentName': '$prefix-voice.m4a',
        'attachmentMimeType': 'audio/mp4',
      },
      {
        'id': '$prefix-pdf',
        'chatId': chatId,
        'content': '',
        'messageType': 'file',
        'attachmentFileId': '$prefix-pdf-file',
        'attachmentName': '$prefix-document.pdf',
        'attachmentMimeType': 'application/pdf',
      },
      {
        'id': '$prefix-image',
        'chatId': chatId,
        'content': '',
        'messageType': 'file',
        'attachmentFileId': '$prefix-image-file',
        'attachmentName': '$prefix-photo.jpg',
        'attachmentMimeType': 'image/jpeg',
      },
    ];
  }
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required _ChatInfoApi api,
  required String role,
  String chatId = 'direct-old',
  Future<void> Function(bool)? onMute,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: ChatInfoDialog(
          chatType: 'direct',
          chatId: chatId,
          userRole: role,
          onMute: onMute,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('manager direct chat loads notes and classifies history', (
    tester,
  ) async {
    final api = _ChatInfoApi();
    await _pumpDialog(tester, api: api, role: 'manager');

    expect(find.byType(Tab), findsNWidgets(4));
    expect(api.messageQueries, [
      {'limit': 100},
    ]);
    expect(api.orderedGets.take(4), [
      '/messenger/chats/direct-old',
      '/messenger/chats/direct-old/members',
      '/admin/profiles/profile-old/notes',
      '/messenger/chats/direct-old/messages',
    ]);

    final buckets = ChatHistoryBuckets.fromMessages(
      api._messages('direct-old').map(_legacyMessageForBuckets),
    );
    expect(buckets.media, hasLength(1));
    expect(buckets.files, hasLength(1));
    expect(buckets.links, hasLength(1));
  });

  testWidgets('teacher direct chat has no notes surface or notes request', (
    tester,
  ) async {
    final api = _ChatInfoApi();
    await _pumpDialog(tester, api: api, role: 'teacher');

    expect(find.byType(Tab), findsNWidgets(3));
    expect(find.text('Заметки'), findsNothing);
    expect(api.orderedGets.where((path) => path.endsWith('/notes')), isEmpty);
  });

  testWidgets('failed mute restores the previous state and reports the error', (
    tester,
  ) async {
    final api = _ChatInfoApi();
    await _pumpDialog(
      tester,
      api: api,
      role: 'teacher',
      onMute: (_) async => throw StateError('mute failed'),
    );

    await tester.tap(find.text('Заглушить'));
    await tester.pump();

    expect(find.text('Заглушить'), findsOneWidget);
    expect(find.text('Не удалось изменить уведомления чата'), findsOneWidget);
  });

  testWidgets('chat identity change clears stale members history and notes', (
    tester,
  ) async {
    final api = _ChatInfoApi();
    final chatId = ValueNotifier<String>('direct-old');
    addTearDown(chatId.dispose);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: chatId,
            builder: (_, value, __) => ChatInfoDialog(
              chatType: 'direct',
              chatId: value,
              userRole: 'manager',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Старый Участник'), findsOneWidget);
    await tester.tap(find.text('Заметки'));
    await tester.pumpAndSettle();
    expect(find.text('Старая заметка'), findsOneWidget);

    chatId.value = 'direct-new';
    await tester.pump();
    expect(find.text('Старый Участник'), findsNothing);
    expect(find.text('Старая заметка'), findsNothing);
    expect(find.text('old-document.pdf'), findsNothing);
    expect(find.text('https://old.example.test'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Новый Участник'), findsOneWidget);
    expect(find.text('Новая заметка'), findsOneWidget);
  });

  test('history buckets keep images files links and exclude voice files', () {
    final buckets = ChatHistoryBuckets.fromMessages([
      {
        'message_type': 'image',
        'attachment_file_id': 'image-file',
        'attachment_name': 'photo.bin',
        'attachment_mime_type': 'application/octet-stream',
      },
      {
        'message_type': 'file',
        'attachment_file_id': 'pdf-file',
        'attachment_name': 'contract.pdf',
        'attachment_mime_type': 'application/pdf',
      },
      {
        'message_type': 'voice',
        'attachment_file_id': 'voice-file',
        'attachment_name': 'voice.m4a',
        'attachment_mime_type': 'audio/mp4',
      },
      {'message_type': 'text', 'content': 'Open https://example.test/path'},
    ]);

    expect(buckets.media, hasLength(1));
    expect(buckets.files, hasLength(1));
    expect(buckets.links, hasLength(1));
    expect(
      buckets.files.any((message) => message['message_type'] == 'voice'),
      isFalse,
    );
  });
}

Map<String, dynamic> _legacyMessageForBuckets(Map<String, dynamic> message) {
  return {
    'message_type': message['messageType'],
    'content': message['content'],
    'attachment_file_id': message['attachmentFileId'],
    'attachment_name': message['attachmentName'],
    'attachment_mime_type': message['attachmentMimeType'],
  };
}
