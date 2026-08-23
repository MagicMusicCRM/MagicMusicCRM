/// Compatibility boundary for presentation consumers that still expect
/// historical snake_case messenger maps. Remove when all consumers read typed
/// messenger models directly.
abstract interface class MessengerLegacyMapAdapter {
  Map<String, dynamic> chat(Map<String, dynamic> source);
  Map<String, dynamic> message(Map<String, dynamic> source);
  Map<String, dynamic> chatMember(Map<String, dynamic> source);
  Map<String, dynamic> channel(Map<String, dynamic> source);
  Map<String, dynamic> channelPermission(Map<String, dynamic> source);
  Map<String, dynamic> channelPost(Map<String, dynamic> source);
}

class DefaultMessengerLegacyMapAdapter implements MessengerLegacyMapAdapter {
  const DefaultMessengerLegacyMapAdapter();

  @override
  Map<String, dynamic> chat(Map<String, dynamic> item) {
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
    final partnerRole = partnerMap['role']?.toString();
    final administrationPartnerIsStaff =
        rawType == 'administration' &&
        const {
          'admin',
          'manager',
          'director',
          'system_admin',
        }.contains(partnerRole);
    final title =
        rawType == 'administration' &&
            (!hasPartnerName || administrationPartnerIsStaff)
        ? 'Администрация'
        : rawTitle;
    final displayName = type == 'group'
        ? (title?.trim().isNotEmpty == true ? title! : 'Группа')
        : administrationPartnerIsStaff
        ? 'Администрация'
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
      'slug': item['slug'],
      'is_system': item['isSystem'] == true,
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
      'folder': item['folder'],
      'assigned_to': item['assignedTo'],
      'archived': item['archived'] == true,
      'owner_name': item['ownerName'],
      'branch_id': item['branchId'],
      'branch_name': item['branchName'],
    };
  }

  @override
  Map<String, dynamic> message(Map<String, dynamic> item) {
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
      'reactions': item['reactions'],
      'profiles': {
        'id': senderMap['id'],
        'email': senderMap['email'],
        'first_name': senderMap['firstName'],
        'last_name': senderMap['lastName'],
        'role': senderMap['role'],
        'avatar_file_id': senderMap['avatarFileId'],
      },
    };
  }

  @override
  Map<String, dynamic> chatMember(Map<String, dynamic> item) {
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
      'user_role': item['userRole'],
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

  @override
  Map<String, dynamic> channel(Map<String, dynamic> item) => {
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

  @override
  Map<String, dynamic> channelPermission(Map<String, dynamic> item) {
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

  String _roleDisplayName(String? role) => role == 'admin'
      ? 'Администраторы'
      : role == 'manager'
      ? 'Управляющие'
      : role == 'director'
      ? 'Директора'
      : role == 'teacher'
      ? 'Преподаватели'
      : role == 'client'
      ? 'Клиенты'
      : 'Правило доступа';

  @override
  Map<String, dynamic> channelPost(Map<String, dynamic> item) => {
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
