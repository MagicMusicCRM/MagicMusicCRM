import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/compat/messenger_legacy_map_adapter.dart';

final magicMessengerServiceProvider = Provider<MagicMessengerService>((ref) {
  return MagicMessengerService(ref.watch(magicApiClientProvider));
});

class MagicMessengerService {
  final MagicApiClient _api;
  final MessengerLegacyMapAdapter _legacyMapAdapter;

  const MagicMessengerService(
    this._api, {
    MessengerLegacyMapAdapter legacyMapAdapter =
        const DefaultMessengerLegacyMapAdapter(),
  }) : _legacyMapAdapter = legacyMapAdapter;

  Future<List<Map<String, dynamic>>> listChats({
    int limit = 50,
    String? branchId,
    bool archived = false,
    String folder = 'all',
  }) async {
    final pageSize = limit.clamp(1, 100);
    final byId = <String, Map<String, dynamic>>{};
    String? cursor;
    final seenCursors = <String>{};

    do {
      final response = await _api.get<Map<String, dynamic>>(
        '/messenger/chats',
        queryParameters: {
          'limit': pageSize,
          if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
          if (archived) 'archived': true,
          if (folder != 'all') 'folder': folder,
          'cursor': ?cursor,
        },
      );
      for (final item in _items(response).map(_legacyChat)) {
        final id = item['id']?.toString();
        if (id != null && id.isNotEmpty) byId.putIfAbsent(id, () => item);
      }

      final next = response['nextCursor']?.toString().trim();
      if (next == null || next.isEmpty || !seenCursors.add(next)) break;
      cursor = next;
    } while (true);

    return byId.values.toList(growable: false);
  }

  Future<Map<String, dynamic>> ensureDirectChat(String targetUserId) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/chats/direct',
      data: {'type': 'direct', 'targetUserId': targetUserId},
    );
    return _legacyChat(response);
  }

  Future<Map<String, dynamic>> ensureAdministrationChat() async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/chats/direct',
      data: {'type': 'administration'},
    );
    return _legacyChat(response);
  }

  Future<Map<String, dynamic>> getChat(String chatId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/messenger/chats/$chatId',
    );
    return _legacyChat(response);
  }

  Future<void> setChatMute(String chatId, {required bool isMuted}) async {
    await _api.put<Map<String, dynamic>>(
      '/messenger/chats/$chatId/mute',
      data: {'isMuted': isMuted},
    );
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    required List<String> memberUserIds,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/groups',
      data: {'name': name.trim(), 'memberUserIds': memberUserIds},
    );
    return _legacyChat(response);
  }

  Future<Map<String, dynamic>> updateGroupMembers(
    String chatId, {
    List<String>? addUserIds,
    List<String>? removeUserIds,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/messenger/groups/$chatId/members',
      data: {'addUserIds': ?addUserIds, 'removeUserIds': ?removeUserIds},
    );
    return _legacyChat(response);
  }

  Future<Map<String, dynamic>> assignChat(
    String chatId, {
    String? userId,
  }) async {
    final data = <String, dynamic>{};
    if (userId != null) data['userId'] = userId;
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/chats/$chatId/assign',
      data: data,
    );
    return _legacyChat(response);
  }

  Future<Map<String, dynamic>> unassignChat(String chatId) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/chats/$chatId/unassign',
      data: <String, dynamic>{},
    );
    return _legacyChat(response);
  }

  Future<Map<String, dynamic>> archiveChat(String chatId) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/chats/$chatId/archive',
      data: <String, dynamic>{},
    );
    return _legacyChat(response);
  }

  Future<Map<String, dynamic>> unarchiveChat(String chatId) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/chats/$chatId/unarchive',
      data: <String, dynamic>{},
    );
    return _legacyChat(response);
  }

  Future<void> leaveGroup(String chatId) async {
    await _api.post<Map<String, dynamic>>(
      '/messenger/groups/$chatId/leave',
      data: <String, dynamic>{},
    );
  }

  Future<List<Map<String, dynamic>>> listChatMembers(String chatId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/messenger/chats/$chatId/members',
    );
    return _items(response).map(_legacyChatMember).toList();
  }

  Future<List<Map<String, dynamic>>> listMessages(
    String chatId, {
    int limit = 100,
    String? before,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (before != null) queryParameters['before'] = before;

    final response = await _api.get<Map<String, dynamic>>(
      '/messenger/chats/$chatId/messages',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyMessage).toList();
  }

  Future<Map<String, dynamic>> sendMessage(
    String chatId, {
    required String content,
    String? replyToId,
    String? attachmentFileId,
    String? forwardedFromId,
    String messageType = 'text',
    int? voiceDurationMs,
  }) async {
    final data = <String, dynamic>{'messageType': messageType};
    if (content.trim().isNotEmpty) data['content'] = content.trim();
    if (replyToId != null) data['replyToId'] = replyToId;
    if (forwardedFromId != null) data['forwardedFromId'] = forwardedFromId;
    if (attachmentFileId != null) {
      data['attachmentFileId'] = attachmentFileId;
    }
    if (voiceDurationMs != null) data['voiceDurationMs'] = voiceDurationMs;

    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/chats/$chatId/messages',
      data: data,
    );
    return _legacyMessage(response);
  }

  Future<Map<String, dynamic>> deleteMessage(
    String messageId, {
    String mode = 'own',
  }) async {
    final response = await _api.delete<Map<String, dynamic>>(
      '/messenger/messages/$messageId',
      data: {'mode': mode},
    );
    return _legacyMessage(response);
  }

  Future<Map<String, dynamic>> updateMessage(
    String messageId, {
    required String content,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/messenger/messages/$messageId',
      data: {'content': content.trim()},
    );
    return _legacyMessage(response);
  }

  Future<Map<String, dynamic>> pinMessage(String messageId) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/messages/$messageId/pin',
    );
    return _legacyMessage(response);
  }

  Future<Map<String, dynamic>> unpinMessage(String messageId) async {
    final response = await _api.delete<Map<String, dynamic>>(
      '/messenger/messages/$messageId/pin',
    );
    return _legacyMessage(response);
  }

  Future<Map<String, dynamic>> setReaction({
    required String messageId,
    required String emoji,
  }) async {
    return _api.put<Map<String, dynamic>>(
      '/messenger/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}',
    );
  }

  Future<Map<String, dynamic>> removeReaction({
    required String messageId,
    required String emoji,
  }) async {
    return _api.delete<Map<String, dynamic>>(
      '/messenger/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}',
    );
  }

  Future<void> markRead(String chatId, {String? lastReadMessageId}) async {
    await _api.post<Map<String, dynamic>>(
      '/messenger/chats/$chatId/read',
      data: {'lastReadMessageId': ?lastReadMessageId},
    );
  }

  Future<List<Map<String, dynamic>>> listChannels() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/messenger/channels',
    );
    return _items(response).map(_legacyChannel).toList();
  }

  Future<Map<String, dynamic>> createChannel({
    required String title,
    String? description,
    List<Map<String, dynamic>> permissions = const [],
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/channels',
      data: {
        'title': title.trim(),
        if (description != null) 'description': description.trim(),
        'permissions': permissions,
      },
    );
    return _legacyChannel(response);
  }

  Future<Map<String, dynamic>> updateChannel(
    String channelId, {
    required String title,
    String? description,
    List<Map<String, dynamic>>? permissions,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/messenger/channels/$channelId',
      data: {
        'title': title.trim(),
        if (description != null) 'description': description.trim(),
        'permissions': ?permissions,
      },
    );
    return _legacyChannel(response);
  }

  Future<Map<String, dynamic>> getChannelAccess(String channelId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/messenger/channels/$channelId/access',
    );
    return {
      'channel_id': response['channelId'],
      'can_read': response['canRead'] == true,
      'can_write': response['canWrite'] == true,
    };
  }

  Future<List<Map<String, dynamic>>> listChannelPermissions(
    String channelId,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/messenger/channels/$channelId/permissions',
    );
    return _items(response).map(_legacyChannelPermission).toList();
  }

  Future<List<Map<String, dynamic>>> listChannelPosts(
    String channelId, {
    int limit = 100,
    String? before,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (before != null) queryParameters['before'] = before;

    final response = await _api.get<Map<String, dynamic>>(
      '/messenger/channels/$channelId/posts',
      queryParameters: queryParameters,
    );
    return _items(response).map(_legacyChannelPost).toList();
  }

  Future<Map<String, dynamic>> createChannelPost(
    String channelId, {
    required String content,
    String? attachmentFileId,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/messenger/channels/$channelId/posts',
      data: {'content': content.trim(), 'attachmentFileId': ?attachmentFileId},
    );
    return _legacyChannelPost(response);
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
    final items = response['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  /// Convert a camelCase `toChatSummaryDto` delivered via the realtime
  /// `chat.created` event into the same snake_case shape that `_legacyChat`
  /// produces from REST responses.  The summary has no `partner` sub-object;
  /// display-name and title fall back to the same rules as `_legacyChat`.
  Map<String, dynamic> legacyChatFromSummary(Map<String, dynamic> summary) {
    // The summary uses the same camelCase field names as the REST response, so
    // we can delegate directly to the private mapper.
    return _legacyChat(summary);
  }

  Map<String, dynamic> legacyChannelFromSummary(Map<String, dynamic> summary) =>
      _legacyChannel(summary);

  Map<String, dynamic> _legacyChat(Map<String, dynamic> item) =>
      _legacyMapAdapter.chat(item);

  Map<String, dynamic> _legacyMessage(Map<String, dynamic> item) =>
      _legacyMapAdapter.message(item);

  Map<String, dynamic> _legacyChatMember(Map<String, dynamic> item) =>
      _legacyMapAdapter.chatMember(item);

  Map<String, dynamic> _legacyChannel(Map<String, dynamic> item) =>
      _legacyMapAdapter.channel(item);

  Map<String, dynamic> _legacyChannelPermission(Map<String, dynamic> item) =>
      _legacyMapAdapter.channelPermission(item);

  Map<String, dynamic> _legacyChannelPost(Map<String, dynamic> item) =>
      _legacyMapAdapter.channelPost(item);
}
