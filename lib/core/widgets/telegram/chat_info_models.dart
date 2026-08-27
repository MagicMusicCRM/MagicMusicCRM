class ChatInfoRequest {
  const ChatInfoRequest({
    required this.chatType,
    required this.chatId,
    required this.userRole,
  });

  final String chatType;
  final String chatId;
  final String userRole;

  @override
  bool operator ==(Object other) {
    return other is ChatInfoRequest &&
        other.chatType == chatType &&
        other.chatId == chatId &&
        other.userRole == userRole;
  }

  @override
  int get hashCode => Object.hash(chatType, chatId, userRole);
}

class ChatHistoryBuckets {
  const ChatHistoryBuckets({
    required this.media,
    required this.files,
    required this.links,
  });

  const ChatHistoryBuckets.empty()
    : media = const [],
      files = const [],
      links = const [];

  factory ChatHistoryBuckets.fromMessages(
    Iterable<Map<String, dynamic>> messages,
  ) {
    final media = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];
    final links = <Map<String, dynamic>>[];

    for (final message in messages) {
      links.addAll(_historyLinks(message));
      if (!_hasHistoryAttachment(message)) continue;
      if (_isHistoryImage(message)) {
        media.add(message);
      } else if (message['message_type']?.toString().toLowerCase() != 'voice') {
        files.add(message);
      }
    }

    return ChatHistoryBuckets(media: media, files: files, links: links);
  }

  final List<Map<String, dynamic>> media;
  final List<Map<String, dynamic>> files;
  final List<Map<String, dynamic>> links;
}

class ChatInfoSnapshot {
  const ChatInfoSnapshot({
    required this.loading,
    required this.data,
    required this.members,
    required this.history,
    required this.notes,
    required this.isMuted,
  });

  factory ChatInfoSnapshot.initial(bool isMuted) => ChatInfoSnapshot(
    loading: true,
    data: null,
    members: const [],
    history: const ChatHistoryBuckets.empty(),
    notes: const [],
    isMuted: isMuted,
  );

  final bool loading;
  final Map<String, dynamic>? data;
  final List<Map<String, dynamic>> members;
  final ChatHistoryBuckets history;
  final List<Map<String, dynamic>> notes;
  final bool isMuted;

  ChatInfoSnapshot copyWith({
    bool? loading,
    Map<String, dynamic>? data,
    bool clearData = false,
    List<Map<String, dynamic>>? members,
    ChatHistoryBuckets? history,
    List<Map<String, dynamic>>? notes,
    bool? isMuted,
  }) {
    return ChatInfoSnapshot(
      loading: loading ?? this.loading,
      data: clearData ? null : (data ?? this.data),
      members: members ?? this.members,
      history: history ?? this.history,
      notes: notes ?? this.notes,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

class ChatInfoAccessPolicy {
  const ChatInfoAccessPolicy({
    required this.request,
    required this.isSystemGroup,
  });

  final ChatInfoRequest request;
  final bool isSystemGroup;

  bool get isManagerTier => const {
    'admin',
    'manager',
    'director',
    'system_admin',
  }.contains(request.userRole);

  bool get hasNotes => request.chatType == 'direct' && isManagerTier;
  bool get canEditChannel => request.chatType == 'channel' && isManagerTier;
  bool get canManageGroup =>
      request.chatType == 'group' && isManagerTier && !isSystemGroup;

  bool canOpenMember(String? userId) =>
      isManagerTier && userId != null && userId.isNotEmpty;

  bool canRemoveMember(Map<String, dynamic> member) =>
      canManageGroup && member['is_current_user'] != true;
}

class ChatInfoViewModel {
  const ChatInfoViewModel({
    required this.request,
    required this.snapshot,
    required this.access,
    required this.conversationPartner,
  });

  final ChatInfoRequest request;
  final ChatInfoSnapshot snapshot;
  final ChatInfoAccessPolicy access;
  final Map<String, dynamic>? conversationPartner;

  String get name {
    if (request.chatType == 'direct') {
      final partnerName = conversationPartner?['_display_name']?.toString();
      final fallback =
          '${snapshot.data?['first_name'] ?? ''} ${snapshot.data?['last_name'] ?? ''}'
              .trim();
      final value = partnerName ?? fallback;
      return value.isEmpty ? 'Без имени' : value;
    }
    return (snapshot.data?['name'] ??
                snapshot.data?['title'] ??
                snapshot.data?['_display_name'])
            ?.toString() ??
        'Без названия';
  }

  String get description {
    if (request.chatType == 'direct') {
      final role =
          conversationPartner?['role'] ?? snapshot.data?['role'] ?? 'client';
      return chatInfoRoleLabel(role.toString());
    }
    return snapshot.data?['description']?.toString() ?? 'Нет описания';
  }

  String get subtitle {
    if (request.chatType == 'direct') {
      final email = conversationPartner?['email']?.toString();
      return email == null || email.isEmpty ? 'Личный чат' : email;
    }
    return snapshot.members.isNotEmpty
        ? '${snapshot.members.length} участников'
        : 'Канал';
  }

  String? get avatarUrl =>
      conversationPartner?['avatar_file_id']?.toString() ??
      conversationPartner?['avatar_url']?.toString() ??
      snapshot.data?['avatar_url']?.toString();
}

abstract interface class ChatInfoActions {
  void close();
  void openCurrentChat();
  Future<void> toggleMute();
  Future<void> editChannel();
  Future<void> leaveGroup();
  Future<void> addMembers();
  Future<void> removeMember(Map<String, dynamic> member);
  Future<void> showAllMembers();
  Future<void> openMemberChat(String? userId);
  Future<void> addNote();
}

String chatInfoRoleLabel(String role) {
  return switch (role) {
    'system_admin' => 'Администратор системы',
    'admin' => 'Администратор',
    'manager' => 'Управляющий',
    'director' => 'Директор',
    'teacher' => 'Преподаватель',
    _ => 'Клиент',
  };
}

int chatInfoTabCount(String chatType, String userRole) {
  final access = ChatInfoAccessPolicy(
    request: ChatInfoRequest(
      chatType: chatType,
      chatId: '',
      userRole: userRole,
    ),
    isSystemGroup: false,
  );
  return access.hasNotes ? 4 : 3;
}

List<Map<String, dynamic>> immutableChatInfoItems(
  Iterable<Map<String, dynamic>> items,
) => List<Map<String, dynamic>>.unmodifiable(items);

Iterable<Map<String, dynamic>> _historyLinks(Map<String, dynamic> message) {
  final content = message['content']?.toString() ?? '';
  return RegExp(r'(https?:\/\/[^\s]+)')
      .allMatches(content)
      .map((match) => match.group(0))
      .whereType<String>()
      .map((link) => {'link': link, 'message': message});
}

bool _hasHistoryAttachment(Map<String, dynamic> message) {
  final value =
      message['attachment_url']?.toString() ??
      message['attachment_file_id']?.toString();
  return value != null && value.isNotEmpty;
}

bool _isHistoryImage(Map<String, dynamic> message) {
  final type = message['message_type']?.toString().toLowerCase();
  final name =
      message['attachment_name']?.toString() ??
      message['attachment_file_id']?.toString() ??
      '';
  final mimeType =
      message['attachment_mime_type']?.toString().toLowerCase() ?? '';
  return mimeType.startsWith('image/') ||
      type == 'image' ||
      type == 'photo' ||
      const [
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.gif',
      ].any((extension) => name.toLowerCase().endsWith(extension));
}
