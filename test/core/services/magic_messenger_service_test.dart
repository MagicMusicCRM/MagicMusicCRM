import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';

void main() {
  group('MagicMessengerService', () {
    test('creates direct chat and maps chat summary to legacy keys', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/chats/direct',
          statusCode: 201,
          body: {
            'id': 'chat-a',
            'type': 'direct',
            'title': null,
            'createdBy': 'teacher-a',
            'lastMessageId': null,
            'lastMessageContent': null,
            'lastMessageCreatedAt': null,
            'partnerId': 'student-user-a',
            'unreadCount': 2,
            'isMuted': true,
            'createdAt': '2026-06-12T10:00:00.000Z',
            'updatedAt': '2026-06-12T10:00:00.000Z',
          },
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      final chat = await service.ensureDirectChat('student-user-a');

      expect(chat['id'], 'chat-a');
      expect(chat['created_by'], 'teacher-a');
      expect(chat['_partner_id'], 'student-user-a');
      expect(chat['unread_count'], 2);
      expect(chat['is_muted'], true);
      expect(adapter.requests.single.body['type'], 'direct');
      expect(adapter.requests.single.body['targetUserId'], 'student-user-a');
    });

    test('updates chat mute preference through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/chats/chat-a/mute',
          statusCode: 200,
          body: {'success': true, 'isMuted': true},
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      await service.setChatMute('chat-a', isMuted: true);

      expect(adapter.requests.single.method, 'PUT');
      expect(adapter.requests.single.body['isMuted'], true);
    });

    test(
      'maps administration chat title to Russian even for legacy backend rows',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/chats/direct',
            statusCode: 201,
            body: {
              'id': 'admin-chat-a',
              'type': 'administration',
              'title': 'Administration',
              'createdBy': 'client-a',
              'lastMessageId': null,
              'lastMessageContent': null,
              'lastMessageCreatedAt': null,
              'unreadCount': 0,
              'createdAt': '2026-06-12T10:00:00.000Z',
              'updatedAt': '2026-06-12T10:00:00.000Z',
            },
          ),
        ]);
        final service = MagicMessengerService(_client(adapter));

        final chat = await service.ensureAdministrationChat();

        expect(chat['title'], 'Администрация');
        expect(chat['_display_name'], 'Администрация');
        expect(adapter.requests.single.body['type'], 'administration');
      },
    );

    test(
      'keeps staff identity hidden behind Administration for clients',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/chats/direct',
            statusCode: 201,
            body: {
              'id': 'admin-chat-a',
              'type': 'administration',
              'title': 'Administration',
              'partnerId': 'manager-a',
              'partner': {
                'id': 'manager-a',
                'firstName': 'Управляющий',
                'lastName': 'Тестов',
                'email': 'manager@example.com',
                'role': 'manager',
              },
              'unreadCount': 0,
            },
          ),
        ]);
        final service = MagicMessengerService(_client(adapter));

        final chat = await service.ensureAdministrationChat();

        expect(chat['title'], 'Администрация');
        expect(chat['_display_name'], 'Администрация');
      },
    );

    test(
      'lists messages and maps sender profile fields to legacy shape',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/chats/chat-a/messages',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'msg-a',
                  'chatId': 'chat-a',
                  'senderId': 'student-user-a',
                  'sender': {
                    'id': 'student-user-a',
                    'email': 'anna@example.com',
                    'firstName': 'Анна',
                    'lastName': 'Иванова',
                    'role': 'client',
                    'avatarFileId': 'avatar-student-a',
                  },
                  'content': 'Здравствуйте',
                  'messageType': 'text',
                  'isRead': true,
                  'attachmentFileId': 'file-a',
                  'attachment': {
                    'originalFileName': 'photo.png',
                    'sizeBytes': 2048,
                    'mimeType': 'image/png',
                    'voiceDurationMs': 1500,
                  },
                  'createdAt': '2026-06-12T10:00:00.000Z',
                  'updatedAt': '2026-06-12T10:00:00.000Z',
                  'deletedAt': null,
                },
              ],
            },
          ),
        ]);
        final service = MagicMessengerService(_client(adapter));

        final messages = await service.listMessages('chat-a', limit: 25);

        expect(messages.single['chat_id'], 'chat-a');
        expect(messages.single['sender_id'], 'student-user-a');
        expect(messages.single['profiles']['email'], 'anna@example.com');
        expect(messages.single['profiles']['first_name'], 'Анна');
        expect(messages.single['profiles']['role'], 'client');
        expect(
          messages.single['profiles']['avatar_file_id'],
          'avatar-student-a',
        );
        expect(messages.single['is_read'], isTrue);
        expect(messages.single['attachment_file_id'], 'file-a');
        expect(messages.single['attachment_name'], 'photo.png');
        expect(messages.single['attachment_size'], 2048);
        expect(messages.single['attachment_mime_type'], 'image/png');
        expect(messages.single['voice_duration_ms'], 1500);
        expect(adapter.requests.single.queryParameters['limit'], 25);
      },
    );

    test('sends text message and marks chat as read', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/chats/chat-a/messages',
          statusCode: 201,
          body: {
            'id': 'msg-b',
            'chatId': 'chat-a',
            'senderId': 'teacher-a',
            'sender': null,
            'content': 'Добрый день',
            'messageType': 'text',
            'createdAt': '2026-06-12T10:01:00.000Z',
            'updatedAt': '2026-06-12T10:01:00.000Z',
            'deletedAt': null,
          },
        ),
        _FakeResponse(
          path: '/messenger/chats/chat-a/read',
          statusCode: 201,
          body: {'success': true},
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      final message = await service.sendMessage(
        'chat-a',
        content: '  Добрый день  ',
      );
      await service.markRead('chat-a', lastReadMessageId: 'msg-b');

      expect(message['content'], 'Добрый день');
      expect(adapter.requests.first.body['content'], 'Добрый день');
      expect(adapter.requests.first.body['messageType'], 'text');
      expect(adapter.requests.last.body['lastReadMessageId'], 'msg-b');
    });

    test('sends a reply with the selected source message id', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/chats/chat-a/messages',
          statusCode: 201,
          body: {
            'id': 'msg-reply',
            'chatId': 'chat-a',
            'senderId': 'teacher-a',
            'content': 'Ответ',
            'messageType': 'text',
            'replyToId': 'msg-source',
            'createdAt': '2026-06-12T10:01:00.000Z',
            'updatedAt': '2026-06-12T10:01:00.000Z',
            'deletedAt': null,
          },
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      final message = await service.sendMessage(
        'chat-a',
        content: 'Ответ',
        replyToId: 'msg-source',
      );

      expect(adapter.requests.single.body['replyToId'], 'msg-source');
      expect(message['reply_to_id'], 'msg-source');
    });

    test(
      'keeps voice message type when sending file object attachment',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/chats/chat-a/messages',
            statusCode: 201,
            body: {
              'id': 'msg-voice',
              'chatId': 'chat-a',
              'senderId': 'teacher-a',
              'sender': null,
              'content': 'Голосовое сообщение',
              'messageType': 'voice',
              'attachmentFileId': 'file-a',
              'voiceDurationMs': 1500,
              'createdAt': '2026-06-12T10:01:00.000Z',
              'updatedAt': '2026-06-12T10:01:00.000Z',
              'deletedAt': null,
            },
          ),
        ]);
        final service = MagicMessengerService(_client(adapter));

        final message = await service.sendMessage(
          'chat-a',
          content: 'Голосовое сообщение',
          messageType: 'voice',
          attachmentFileId: 'file-a',
          voiceDurationMs: 1500,
        );

        expect(message['message_type'], 'voice');
        expect(message['attachment_file_id'], 'file-a');
        expect(message['voice_duration_ms'], 1500);
        expect(adapter.requests.single.body['messageType'], 'voice');
        expect(adapter.requests.single.body['attachmentFileId'], 'file-a');
        expect(adapter.requests.single.body['voiceDurationMs'], 1500);
      },
    );

    test('uses v3 edit, moderation, pin and reaction endpoints', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/chats/chat-a/messages',
          statusCode: 201,
          body: {
            'id': 'msg-c',
            'chatId': 'chat-a',
            'senderId': 'teacher-a',
            'sender': null,
            'content': 'Forwarded',
            'messageType': 'text',
            'forwardedFromId': 'student-a',
            'createdAt': '2026-06-12T10:01:00.000Z',
            'updatedAt': '2026-06-12T10:01:00.000Z',
            'deletedAt': null,
          },
        ),
        _FakeResponse(
          path: '/messenger/messages/msg-c',
          statusCode: 200,
          body: {
            'id': 'msg-c',
            'chatId': 'chat-a',
            'senderId': 'teacher-a',
            'sender': null,
            'content': 'Updated',
            'messageType': 'text',
            'createdAt': '2026-06-12T10:01:00.000Z',
            'updatedAt': '2026-06-12T10:01:30.000Z',
            'deletedAt': null,
          },
        ),
        _FakeResponse(
          path: '/messenger/messages/msg-c/pin',
          statusCode: 201,
          body: {
            'id': 'msg-c',
            'chatId': 'chat-a',
            'senderId': 'teacher-a',
            'sender': null,
            'content': 'Forwarded',
            'messageType': 'text',
            'pinnedAt': '2026-06-12T10:02:00.000Z',
            'createdAt': '2026-06-12T10:01:00.000Z',
            'updatedAt': '2026-06-12T10:02:00.000Z',
            'deletedAt': null,
          },
        ),
        _FakeResponse(
          path: '/messenger/messages/msg-c/pin',
          statusCode: 200,
          body: {
            'id': 'msg-c',
            'chatId': 'chat-a',
            'senderId': 'teacher-a',
            'sender': null,
            'content': 'Forwarded',
            'messageType': 'text',
            'pinnedAt': null,
            'createdAt': '2026-06-12T10:01:00.000Z',
            'updatedAt': '2026-06-12T10:03:00.000Z',
            'deletedAt': null,
          },
        ),
        _FakeResponse(
          path: '/messenger/messages/msg-c/reactions/%F0%9F%91%8D',
          statusCode: 200,
          body: {
            'messageId': 'msg-c',
            'reactions': [
              {'emoji': '👍', 'count': 1},
            ],
          },
        ),
        _FakeResponse(
          path: '/messenger/messages/msg-c/reactions/%F0%9F%91%8D',
          statusCode: 200,
          body: {'messageId': 'msg-c', 'reactions': []},
        ),
        _FakeResponse(
          path: '/messenger/messages/msg-c',
          statusCode: 200,
          body: {
            'id': 'msg-c',
            'chatId': 'chat-a',
            'senderId': 'teacher-a',
            'sender': null,
            'content': null,
            'messageType': 'text',
            'createdAt': '2026-06-12T10:01:00.000Z',
            'updatedAt': '2026-06-12T10:04:00.000Z',
            'deletedAt': '2026-06-12T10:04:00.000Z',
          },
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      await service.sendMessage(
        'chat-a',
        content: 'Forwarded',
        forwardedFromId: 'student-a',
      );
      final updated = await service.updateMessage(
        'msg-c',
        content: ' Updated ',
      );
      final pinned = await service.pinMessage('msg-c');
      final unpinned = await service.unpinMessage('msg-c');
      final setReaction = await service.setReaction(
        messageId: 'msg-c',
        emoji: '👍',
      );
      final removedReaction = await service.removeReaction(
        messageId: 'msg-c',
        emoji: '👍',
      );
      final deleted = await service.deleteMessage('msg-c', mode: 'moderated');

      expect(adapter.requests[0].body['forwardedFromId'], 'student-a');
      expect(updated['content'], 'Updated');
      expect(adapter.requests[1].method, 'PATCH');
      expect(adapter.requests[1].body['content'], 'Updated');
      expect(pinned['pinned_at'], isNotNull);
      expect(unpinned['pinned_at'], isNull);
      expect(setReaction['reactions'], isNotEmpty);
      expect(removedReaction['reactions'], isEmpty);
      expect(adapter.requests.last.body['mode'], 'moderated');
      expect(deleted['deleted_at'], isNotNull);
    });

    test('creates groups and updates members through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/groups',
          statusCode: 201,
          body: {
            'id': 'group-chat-a',
            'type': 'group',
            'title': 'Группа A',
            'createdBy': 'admin-a',
            'lastMessageId': null,
            'lastMessageContent': null,
            'lastMessageCreatedAt': null,
            'unreadCount': 0,
            'createdAt': '2026-06-12T10:00:00.000Z',
            'updatedAt': '2026-06-12T10:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/messenger/groups/group-chat-a/members',
          statusCode: 200,
          body: {
            'id': 'group-chat-a',
            'type': 'group',
            'title': 'Группа A',
            'createdBy': 'admin-a',
            'lastMessageId': null,
            'lastMessageContent': null,
            'lastMessageCreatedAt': null,
            'unreadCount': 0,
            'createdAt': '2026-06-12T10:00:00.000Z',
            'updatedAt': '2026-06-12T10:01:00.000Z',
          },
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      final group = await service.createGroup(
        name: ' Группа A ',
        memberUserIds: ['user-a', 'user-b'],
      );
      await service.updateGroupMembers(
        'group-chat-a',
        addUserIds: ['user-c'],
        removeUserIds: ['user-b'],
      );

      expect(group['type'], 'group');
      expect(adapter.requests.first.body['name'], 'Группа A');
      expect(adapter.requests.first.body['memberUserIds'], [
        'user-a',
        'user-b',
      ]);
      expect(adapter.requests.last.body['addUserIds'], ['user-c']);
      expect(adapter.requests.last.body['removeUserIds'], ['user-b']);
    });

    test('lists group members through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/chats/group-chat-a/members',
          statusCode: 200,
          body: {
            'items': [
              {
                'profileId': 'profile-a',
                'userId': 'user-a',
                'email': 'anna@example.com',
                'role': 'admin',
                'userRole': 'manager',
                'firstName': 'Анна',
                'lastName': 'Иванова',
                'avatarFileId': 'avatar-a',
                'joinedAt': '2026-06-13T10:00:00.000Z',
                'isCurrentUser': true,
              },
            ],
          },
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      final members = await service.listChatMembers('group-chat-a');

      expect(members.single['profile_id'], 'profile-a');
      expect(members.single['user_id'], 'user-a');
      expect(members.single['role'], 'admin');
      expect(members.single['user_role'], 'manager');
      expect(members.single['_display_name'], 'Анна Иванова');
      expect(members.single['avatar_file_id'], 'avatar-a');
      expect(members.single['is_current_user'], isTrue);
      expect(adapter.requests.single.method, 'GET');
    });

    test('lists channels and channel posts through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/channels',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'channel-a',
                'title': 'Объявления',
                'description': 'Новости школы',
                'createdBy': 'admin-a',
                'createdAt': '2026-06-12T10:00:00.000Z',
                'updatedAt': '2026-06-12T10:00:00.000Z',
              },
            ],
          },
        ),
        _FakeResponse(
          path: '/messenger/channels/channel-a/posts',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'post-a',
                'channelId': 'channel-a',
                'authorId': 'admin-a',
                'content': 'Новость',
                'attachmentFileId': null,
                'publishedAt': '2026-06-12T10:01:00.000Z',
                'updatedAt': '2026-06-12T10:01:00.000Z',
              },
            ],
          },
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      final channels = await service.listChannels();
      final posts = await service.listChannelPosts('channel-a', limit: 25);

      expect(channels.single['name'], 'Объявления');
      expect(channels.single['_item_type'], 'channel');
      expect(posts.single['channel_id'], 'channel-a');
      expect(posts.single['sender_id'], 'admin-a');
      expect(adapter.requests.last.queryParameters['limit'], 25);
    });

    test('creates and updates channels through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/channels',
          statusCode: 201,
          body: {
            'id': 'channel-a',
            'title': 'Объявления',
            'description': null,
            'createdBy': 'admin-a',
            'createdAt': '2026-06-12T10:00:00.000Z',
            'updatedAt': '2026-06-12T10:00:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/messenger/channels/channel-a',
          statusCode: 200,
          body: {
            'id': 'channel-a',
            'title': 'Важное',
            'description': 'Только важные объявления',
            'createdBy': 'admin-a',
            'createdAt': '2026-06-12T10:00:00.000Z',
            'updatedAt': '2026-06-12T10:02:00.000Z',
          },
        ),
        _FakeResponse(
          path: '/messenger/channels/channel-a/posts',
          statusCode: 201,
          body: {
            'id': 'post-a',
            'channelId': 'channel-a',
            'authorId': 'admin-a',
            'content': 'Пост',
            'attachmentFileId': null,
            'publishedAt': '2026-06-12T10:03:00.000Z',
            'updatedAt': '2026-06-12T10:03:00.000Z',
          },
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      await service.createChannel(title: ' Объявления ');
      await service.updateChannel(
        'channel-a',
        title: 'Важное',
        description: 'Только важные объявления',
      );
      await service.createChannelPost('channel-a', content: ' Пост ');

      expect(adapter.requests[0].body['title'], 'Объявления');
      expect(
        adapter.requests[1].body['description'],
        'Только важные объявления',
      );
      expect(adapter.requests[1].body.containsKey('permissions'), isFalse);
      expect(adapter.requests[2].body['content'], 'Пост');
    });

    test('assignChat self-claim posts to assign with empty body', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/chats/c1/assign',
          statusCode: 200,
          body: {'id': 'c1', 'type': 'administration'},
        ),
      ]);
      final svc = MagicMessengerService(_client(adapter));
      await svc.assignChat('c1');
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.body['userId'], isNull);
    });

    test('assignChat with userId posts the target', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/chats/c1/assign',
          statusCode: 200,
          body: {'id': 'c1'},
        ),
      ]);
      final svc = MagicMessengerService(_client(adapter));
      await svc.assignChat('c1', userId: 'staff-9');
      expect(adapter.requests.single.body['userId'], 'staff-9');
    });

    test(
      'archiveChat / unarchiveChat / unassignChat hit the right routes',
      () async {
        // _FakeAdapter.fetch already asserts options.uri.path == response.path,
        // so providing them in order is sufficient to verify routing.
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/chats/c1/archive',
            statusCode: 200,
            body: {'id': 'c1'},
          ),
          _FakeResponse(
            path: '/messenger/chats/c1/unarchive',
            statusCode: 200,
            body: {'id': 'c1'},
          ),
          _FakeResponse(
            path: '/messenger/chats/c1/unassign',
            statusCode: 200,
            body: {'id': 'c1'},
          ),
        ]);
        final svc = MagicMessengerService(_client(adapter));
        await svc.archiveChat('c1');
        await svc.unarchiveChat('c1');
        await svc.unassignChat('c1');
        expect(adapter.requests.length, 3);
        expect(adapter.requests.every((r) => r.method == 'POST'), isTrue);
      },
    );

    test('leaveGroup posts to groups/:id/leave', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/groups/g1/leave',
          statusCode: 200,
          body: {'success': true},
        ),
      ]);
      final svc = MagicMessengerService(_client(adapter));
      await svc.leaveGroup('g1');
      expect(adapter.requests.single.method, 'POST');
    });

    test(
      '_legacyChat surfaces folder, assignedTo, archived, ownerName',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/chats',
            statusCode: 200,
            body: {
              'items': [
                {
                  'id': 'c1',
                  'type': 'administration',
                  'title': 'Администрация',
                  'unreadCount': 2,
                  'isMuted': false,
                  'ownerName': 'Иван Петров',
                  'folder': 'students',
                  'archived': false,
                  'assignedTo': {'id': 'staff-9', 'name': 'Анна'},
                },
              ],
            },
          ),
        ]);
        final svc = MagicMessengerService(_client(adapter));
        final chats = await svc.listChats();
        final c = chats.single;
        expect(c['folder'], 'students');
        expect(c['archived'], false);
        expect(c['owner_name'], 'Иван Петров');
        expect((c['assigned_to'] as Map)['name'], 'Анна');
      },
    );

    test(
      'listChats follows keyset pages, preserves filters, and deduplicates ids',
      () async {
        final adapter = _FakeAdapter([
          _FakeResponse(
            path: '/messenger/chats',
            statusCode: 200,
            body: {
              'items': [
                {'id': 'c1', 'type': 'administration', 'folder': 'students'},
                {'id': 'c2', 'type': 'administration', 'folder': 'students'},
              ],
              'nextCursor': 'cursor-page-2',
            },
          ),
          _FakeResponse(
            path: '/messenger/chats',
            statusCode: 200,
            body: {
              'items': [
                {'id': 'c2', 'type': 'administration', 'folder': 'students'},
                {'id': 'c3', 'type': 'administration', 'folder': 'students'},
              ],
              'nextCursor': null,
            },
          ),
        ]);
        final service = MagicMessengerService(_client(adapter));

        final chats = await service.listChats(
          limit: 500,
          branchId: 'branch-a',
          archived: true,
          folder: 'students',
        );

        expect(chats.map((chat) => chat['id']), ['c1', 'c2', 'c3']);
        expect(adapter.requests, hasLength(2));
        expect(adapter.requests.first.queryParameters['limit'], 100);
        expect(adapter.requests.first.queryParameters['branchId'], 'branch-a');
        expect(adapter.requests.first.queryParameters['archived'], isTrue);
        expect(adapter.requests.first.queryParameters['folder'], 'students');
        expect(adapter.requests[1].queryParameters['cursor'], 'cursor-page-2');
        expect(adapter.requests[1].queryParameters['folder'], 'students');
      },
    );

    test(
      'legacyChatFromSummary maps camelCase realtime summary to legacy keys',
      () {
        final adapter = _FakeAdapter([]);
        final svc = MagicMessengerService(_client(adapter));
        final summary = <String, dynamic>{
          'id': 'chat-rt-1',
          'type': 'administration',
          'title': 'Администрация',
          'unreadCount': 3,
          'isMuted': false,
          'ownerName': 'Мария Смирнова',
          'folder': 'leads',
          'archived': false,
          'assignedTo': {'id': 'staff-7', 'name': 'Олег'},
        };

        final result = svc.legacyChatFromSummary(summary);

        expect(result['id'], 'chat-rt-1');
        expect(result['type'], 'direct'); // administration → direct
        expect(result['raw_type'], 'administration');
        expect(result['folder'], 'leads');
        expect(result['archived'], false);
        expect(result['owner_name'], 'Мария Смирнова');
        expect((result['assigned_to'] as Map)['name'], 'Олег');
      },
    );

    test('reads channel access and permission rules through v3 API', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/messenger/channels/channel-a/access',
          statusCode: 200,
          body: {'channelId': 'channel-a', 'canRead': true, 'canWrite': false},
        ),
        _FakeResponse(
          path: '/messenger/channels/channel-a/permissions',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'permission-a',
                'userId': 'teacher-a',
                'role': null,
                'canRead': true,
                'canWrite': true,
                'user': {
                  'id': 'teacher-a',
                  'email': 'teacher@example.com',
                  'firstName': 'Анна',
                  'lastName': 'Иванова',
                },
              },
              {
                'id': 'permission-b',
                'userId': null,
                'role': 'client',
                'canRead': true,
                'canWrite': false,
                'user': null,
              },
            ],
          },
        ),
      ]);
      final service = MagicMessengerService(_client(adapter));

      final access = await service.getChannelAccess('channel-a');
      final permissions = await service.listChannelPermissions('channel-a');

      expect(access['can_read'], isTrue);
      expect(access['can_write'], isFalse);
      expect(permissions.first['user_id'], 'teacher-a');
      expect(permissions.first['_display_name'], 'Анна Иванова');
      expect(permissions.last['role'], 'client');
      expect(permissions.last['_display_name'], 'Клиенты');
      expect(adapter.requests.first.method, 'GET');
      expect(adapter.requests.last.method, 'GET');
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
