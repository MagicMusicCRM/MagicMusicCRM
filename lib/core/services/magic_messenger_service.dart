import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

final magicMessengerServiceProvider = Provider<MagicMessengerService>((ref) {
  return MagicMessengerService(ref.watch(magicApiClientProvider));
});

class MagicMessengerService {
  final MagicApiClient _api;

  const MagicMessengerService(this._api);

  Future<List<Map<String, dynamic>>> listChats({int limit = 50}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/messenger/chats',
      queryParameters: {'limit': limit},
    );
    return _items(response).map(_legacyChat).toList();
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
  }) async {
    final data = <String, dynamic>{'messageType': messageType};
    if (content.trim().isNotEmpty) data['content'] = content.trim();
    if (replyToId != null) data['replyToId'] = replyToId;
    if (forwardedFromId != null) data['forwardedFromId'] = forwardedFromId;
    if (attachmentFileId != null) {
      data['attachmentFileId'] = attachmentFileId;
    }

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
    List<Map<String, dynamic>> permissions = const [],
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/messenger/channels/$channelId',
      data: {
        'title': title.trim(),
        if (description != null) 'description': description.trim(),
        'permissions': permissions,
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

  Map<String, dynamic> _legacyChat(Map<String, dynamic> item) {
    final rawType = item['type']?.toString() ?? 'direct';
    final type = rawType == 'administration' ? 'direct' : rawType;
    final rawTitle = item['title']?.toString();
    final partner = item['partner'];
    final partnerMap = partner is Map<String, dynamic>
        ? partner
        : const <String, dynamic>{};
    final partnerFirstName = partnerMap['firstName']?.toString();
    final partnerLastName = partnerMap['lastName']?.toString();
    final partnerEmail = partnerMap['email']?.toString();
    final partnerDisplayName = [
      if (partnerFirstName?.trim().isNotEmpty == true) partnerFirstName!.trim(),
      if (partnerLastName?.trim().isNotEmpty == true) partnerLastName!.trim(),
    ].join(' ').trim();
    final hasPartnerName =
        partnerDisplayName.isNotEmpty ||
        partnerEmail?.trim().isNotEmpty == true;
    final title = rawType == 'administration' && !hasPartnerName
        ? 'Администрация'
        : rawTitle;
    final displayName = type == 'group'
        ? (title?.trim().isNotEmpty == true ? title! : 'Группа')
        : hasPartnerName
        ? (partnerDisplayName.isNotEmpty ? partnerDisplayName : partnerEmail!)
        : rawType == 'administration'
        ? 'Администрация'
        : title?.trim().isNotEmpty == true
        ? title!
        : 'Личный чат';
    final lastContent = item['lastMessageContent'];
    final lastCreatedAt = item['lastMessageCreatedAt'];
    return {
      'id': item['id'],
      'type': type,
      'raw_type': rawType,
      'title': title,
      'created_by': item['createdBy'],
      'last_message_id': item['lastMessageId'],
      'partner_id': item['partnerId'],
      'partner': partnerMap.isEmpty ? null : partnerMap,
      'last_message_content': lastContent,
      'last_message_created_at': lastCreatedAt,
      'unread_count': item['unreadCount'] ?? 0,
      'is_muted': item['isMuted'] == true,
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
      '_item_type': type,
      '_partner_id': item['partnerId'],
      '_partner_data': partnerMap.isEmpty
          ? null
          : {
              'id': partnerMap['id'],
              'email': partnerEmail,
              'first_name': partnerFirstName,
              'last_name': partnerLastName,
              'avatar_file_id': partnerMap['avatarFileId'],
            },
      '_avatar_url': partnerMap['avatarFileId'],
      '_display_name': displayName,
      '_last_message': lastContent == null
          ? null
          : {
              'id': item['lastMessageId'],
              'content': lastContent,
              'created_at': lastCreatedAt,
            },
      '_last_message_time': lastCreatedAt,
    };
  }

  Map<String, dynamic> _legacyMessage(Map<String, dynamic> item) {
    final sender = item['sender'];
    final senderMap = sender is Map<String, dynamic>
        ? sender
        : const <String, dynamic>{};
    final attachment = item['attachment'];
    final attachmentMap = attachment is Map<String, dynamic>
        ? attachment
        : const <String, dynamic>{};
    final rawRead = item['isRead'] ?? item['is_read'] ?? item['read'];
    final isRead = rawRead == true;
    return {
      'id': item['id'],
      'chat_id': item['chatId'],
      'sender_id': item['senderId'],
      'content': item['content'],
      'message_type': item['messageType'],
      'attachment_file_id': item['attachmentFileId'],
      'attachment_name':
          item['attachmentName'] ??
          item['attachmentFileName'] ??
          item['fileName'] ??
          attachmentMap['originalFileName'] ??
          attachmentMap['fileName'] ??
          attachmentMap['name'],
      'attachment_size':
          item['attachmentSize'] ??
          item['attachmentFileSize'] ??
          item['fileSize'] ??
          attachmentMap['sizeBytes'] ??
          attachmentMap['size'],
      'attachment_mime_type':
          item['attachmentMimeType'] ??
          item['attachmentContentType'] ??
          item['mimeType'] ??
          attachmentMap['mimeType'] ??
          attachmentMap['contentType'],
      'voice_duration_ms':
          item['voiceDurationMs'] ??
          item['voiceDurationMillis'] ??
          attachmentMap['voiceDurationMs'] ??
          attachmentMap['durationMs'],
      'reply_to_id': item['replyToId'],
      'forwarded_from_id': item['forwardedFromId'],
      'pinned_by': item['pinnedBy'],
      'pinned_at': item['pinnedAt'],
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
      'deleted_at': item['deletedAt'],
      'is_read': isRead,
      'profiles': {
        'id': senderMap['id'],
        'first_name': senderMap['firstName'],
        'last_name': senderMap['lastName'],
      },
    };
  }

  Map<String, dynamic> _legacyChatMember(Map<String, dynamic> item) {
    final firstName = item['firstName']?.toString();
    final lastName = item['lastName']?.toString();
    final email = item['email']?.toString();
    final displayName = [
      if (firstName != null && firstName.trim().isNotEmpty) firstName.trim(),
      if (lastName != null && lastName.trim().isNotEmpty) lastName.trim(),
    ].join(' ').trim();
    return {
      'profile_id': item['profileId'],
      'user_id': item['userId'],
      'id': item['userId'],
      'email': email,
      'role': item['role'],
      'first_name': firstName,
      'last_name': lastName,
      'phone': item['phone'],
      'avatar_file_id': item['avatarFileId'],
      'joined_at': item['joinedAt'],
      'is_current_user': item['isCurrentUser'] == true,
      '_display_name': displayName.isNotEmpty
          ? displayName
          : (email?.trim().isNotEmpty == true ? email : 'Участник'),
    };
  }

  Map<String, dynamic> _legacyChannel(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'title': item['title'],
      'name': item['title'],
      'description': item['description'],
      'created_by': item['createdBy'],
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
      '_item_type': 'channel',
      '_display_name': item['title'],
    };
  }

  Map<String, dynamic> _legacyChannelPermission(Map<String, dynamic> item) {
    final user = item['user'];
    final userMap = user is Map<String, dynamic>
        ? user
        : const <String, dynamic>{};
    final firstName = userMap['firstName']?.toString();
    final lastName = userMap['lastName']?.toString();
    final email = userMap['email']?.toString();
    final displayName = [
      if (firstName != null && firstName.trim().isNotEmpty) firstName.trim(),
      if (lastName != null && lastName.trim().isNotEmpty) lastName.trim(),
    ].join(' ').trim();
    final role = item['role']?.toString();
    return {
      'id': item['id'],
      'channel_id': item['channelId'],
      'user_id': item['userId'],
      'role': role,
      'can_read': item['canRead'] == true,
      'can_write': item['canWrite'] == true,
      'profiles': userMap.isEmpty
          ? null
          : {
              'id': userMap['id'],
              'email': email,
              'first_name': firstName,
              'last_name': lastName,
            },
      '_display_name': displayName.isNotEmpty
          ? displayName
          : (email?.trim().isNotEmpty == true ? email : _roleDisplayName(role)),
    };
  }

  String _roleDisplayName(String? role) {
    return role == 'admin'
        ? 'Администраторы'
        : role == 'manager'
        ? 'Управляющие'
        : role == 'teacher'
        ? 'Преподаватели'
        : role == 'client'
        ? 'Клиенты'
        : 'Правило доступа';
  }

  Map<String, dynamic> _legacyChannelPost(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'channel_id': item['channelId'],
      'author_id': item['authorId'],
      'sender_id': item['authorId'],
      'content': item['content'],
      'attachment_file_id': item['attachmentFileId'],
      'message_type': item['attachmentFileId'] == null ? 'text' : 'file',
      'published_at': item['publishedAt'],
      'created_at': item['publishedAt'],
      'updated_at': item['updatedAt'],
      'is_read': true,
    };
  }
}
