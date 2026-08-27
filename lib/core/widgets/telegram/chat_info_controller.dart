import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';

class ChatInfoController extends ChangeNotifier {
  ChatInfoController({
    required ChatInfoRequest request,
    required bool initialIsMuted,
    required MagicMessengerService messenger,
    required MagicProfileAdminService profiles,
    required MagicSettingsService settings,
  }) : _request = request,
       _messenger = messenger,
       _profiles = profiles,
       _settings = settings,
       _initialIsMuted = initialIsMuted,
       _snapshot = ChatInfoSnapshot.initial(initialIsMuted);

  final MagicMessengerService _messenger;
  final MagicProfileAdminService _profiles;
  final MagicSettingsService _settings;
  ChatInfoRequest _request;
  bool _initialIsMuted;
  ChatInfoSnapshot _snapshot;
  int _loadGeneration = 0;

  ChatInfoRequest get request => _request;
  ChatInfoSnapshot get snapshot => _snapshot;
  ChatInfoViewModel get viewModel => ChatInfoViewModel(
    request: _request,
    snapshot: _snapshot,
    access: access,
    conversationPartner: conversationPartner,
  );
  ChatInfoAccessPolicy get access => ChatInfoAccessPolicy(
    request: _request,
    isSystemGroup: _snapshot.data?['is_system'] == true,
  );

  Map<String, dynamic>? get conversationPartner {
    if (_snapshot.members.isEmpty) return null;
    return _snapshot.members.firstWhere(
      (member) => member['is_current_user'] != true,
      orElse: () => _snapshot.members.first,
    );
  }

  String? get notesProfileId {
    final profileId = conversationPartner?['profile_id']?.toString();
    return profileId == null || profileId.trim().isEmpty ? null : profileId;
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _snapshot = ChatInfoSnapshot.initial(_initialIsMuted);
    notifyListeners();

    Map<String, dynamic>? data;
    var members = const <Map<String, dynamic>>[];
    var notes = const <Map<String, dynamic>>[];
    var history = const ChatHistoryBuckets.empty();
    try {
      if (_request.chatId == 'admin_chat') {
        final avatarUrl = await _settings.getAdminChatAvatar();
        data = {
          'name': 'Администрация (Чат с клиентами)',
          'avatar_url': avatarUrl,
        };
      } else if (_request.chatType == 'direct' ||
          _request.chatType == 'group') {
        data = await _messenger.getChat(_request.chatId);
        members = await _messenger.listChatMembers(_request.chatId);
      } else if (_request.chatType == 'channel') {
        final channels = await _messenger.listChannels();
        data = channels
            .where((channel) => channel['id']?.toString() == _request.chatId)
            .firstOrNull;
      }

      if (_canLoadNotes(members)) {
        final profileId = _profileIdFromMembers(members);
        if (profileId != null) {
          notes = await _profiles.listProfileNotes(profileId);
        }
      }

      history = await _loadHistory();
    } catch (error) {
      debugPrint('Error loading chat info: $error');
    }

    if (generation != _loadGeneration) return;
    _snapshot = ChatInfoSnapshot(
      loading: false,
      data: data,
      members: immutableChatInfoItems(members),
      history: history,
      notes: immutableChatInfoItems(notes),
      isMuted: data?['is_muted'] == true || _initialIsMuted,
    );
    notifyListeners();
  }

  Future<void> updateRequest(
    ChatInfoRequest request, {
    required bool initialIsMuted,
  }) async {
    _request = request;
    _initialIsMuted = initialIsMuted;
    await load();
  }

  void replaceInitialMuted(bool value) {
    _initialIsMuted = value;
    _snapshot = _snapshot.copyWith(isMuted: value);
    notifyListeners();
  }

  Future<void> setMuted(
    bool value,
    Future<void> Function(bool value)? persist,
  ) async {
    final previous = _snapshot.isMuted;
    _snapshot = _snapshot.copyWith(isMuted: value);
    notifyListeners();
    try {
      await persist?.call(value);
    } catch (_) {
      _snapshot = _snapshot.copyWith(isMuted: previous);
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createNote(String body) async {
    final profileId = notesProfileId;
    if (profileId == null) {
      throw StateError('Chat partner profile is unavailable');
    }
    final note = await _profiles.createProfileNote(
      profileId: profileId,
      body: body,
    );
    _snapshot = _snapshot.copyWith(
      notes: immutableChatInfoItems([note, ..._snapshot.notes]),
    );
    notifyListeners();
    return note;
  }

  Future<void> addMembers(Set<String> userIds) async {
    if (!access.canManageGroup || userIds.isEmpty) return;
    await _messenger.updateGroupMembers(
      _request.chatId,
      addUserIds: userIds.toList(),
    );
    final members = await _messenger.listChatMembers(_request.chatId);
    _snapshot = _snapshot.copyWith(members: immutableChatInfoItems(members));
    notifyListeners();
  }

  Future<void> removeMember(String userId) async {
    if (!access.canManageGroup || userId.isEmpty) return;
    await _messenger.updateGroupMembers(
      _request.chatId,
      removeUserIds: [userId],
    );
    _snapshot = _snapshot.copyWith(
      members: immutableChatInfoItems(
        _snapshot.members.where(
          (member) => member['user_id']?.toString() != userId,
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> leaveGroup() => _messenger.leaveGroup(_request.chatId);

  Future<Map<String, dynamic>> ensureDirectChat(String userId) =>
      _messenger.ensureDirectChat(userId);

  Future<List<Map<String, dynamic>>> listProfilesForMembership() =>
      _profiles.listProfiles(limit: 100);

  void replaceChannel(Map<String, dynamic> channel) {
    _snapshot = _snapshot.copyWith(data: channel);
    notifyListeners();
  }

  bool _canLoadNotes(List<Map<String, dynamic>> members) {
    return ChatInfoAccessPolicy(
          request: _request,
          isSystemGroup: false,
        ).hasNotes &&
        _profileIdFromMembers(members) != null;
  }

  String? _profileIdFromMembers(List<Map<String, dynamic>> members) {
    if (members.isEmpty) return null;
    final partner = members.firstWhere(
      (member) => member['is_current_user'] != true,
      orElse: () => members.first,
    );
    final profileId = partner['profile_id']?.toString();
    return profileId == null || profileId.trim().isEmpty ? null : profileId;
  }

  Future<ChatHistoryBuckets> _loadHistory() async {
    try {
      List<Map<String, dynamic>> messages;
      if (_request.chatType == 'group' || _request.chatType == 'direct') {
        messages = await _messenger
            .listMessages(_request.chatId, limit: 100)
            .timeout(const Duration(seconds: 15));
      } else if (_request.chatType == 'channel') {
        messages = await _messenger
            .listChannelPosts(_request.chatId, limit: 100)
            .timeout(const Duration(seconds: 15));
      } else {
        return const ChatHistoryBuckets.empty();
      }
      return ChatHistoryBuckets.fromMessages(messages.reversed);
    } catch (error) {
      debugPrint('Error loading history: $error');
      return const ChatHistoryBuckets.empty();
    }
  }
}
