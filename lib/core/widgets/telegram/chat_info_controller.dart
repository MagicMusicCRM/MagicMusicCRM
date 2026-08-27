import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';

const _disposedControllerMessage = 'Chat info controller is disposed';

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
  int _requestGeneration = 0;
  int _muteGeneration = 0;
  int _membershipGeneration = 0;
  bool _disposed = false;

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
    if (_disposed) return;
    final generation = ++_loadGeneration;
    final requestGeneration = _requestGeneration;
    final muteGeneration = _muteGeneration;
    final request = _request;
    final initialIsMuted = _initialIsMuted;
    _snapshot = ChatInfoSnapshot.initial(initialIsMuted);
    notifyListeners();

    Map<String, dynamic>? data;
    var members = const <Map<String, dynamic>>[];
    var notes = const <Map<String, dynamic>>[];
    var history = const ChatHistoryBuckets.empty();
    try {
      if (request.chatId == 'admin_chat') {
        final avatarUrl = await _settings.getAdminChatAvatar();
        data = {
          'name': 'Администрация (Чат с клиентами)',
          'avatar_url': avatarUrl,
        };
      } else if (request.chatType == 'direct' || request.chatType == 'group') {
        data = await _messenger.getChat(request.chatId);
        members = await _messenger.listChatMembers(request.chatId);
      } else if (request.chatType == 'channel') {
        final channels = await _messenger.listChannels();
        data = channels
            .where((channel) => channel['id']?.toString() == request.chatId)
            .firstOrNull;
      }

      notes = await _loadNotes(request, members);
      history = await _loadHistory(request);
    } catch (error) {
      if (!_isCurrentLoad(requestGeneration, generation)) return;
      debugPrint('Error loading chat info: $error');
    }

    if (!_isCurrentLoad(requestGeneration, generation)) return;
    _snapshot = ChatInfoSnapshot(
      loading: false,
      data: data,
      members: immutableChatInfoItems(members),
      history: history,
      notes: immutableChatInfoItems(notes),
      isMuted: _resolvedLoadedMute(
        loadMuteGeneration: muteGeneration,
        currentMuteGeneration: _muteGeneration,
        currentIsMuted: _snapshot.isMuted,
        serverIsMuted: data?['is_muted'] == true,
        initialIsMuted: _initialIsMuted,
      ),
    );
    notifyListeners();
  }

  Future<void> updateRequest(
    ChatInfoRequest request, {
    required bool initialIsMuted,
  }) async {
    if (_disposed) return;
    _request = request;
    _initialIsMuted = initialIsMuted;
    _requestGeneration++;
    _muteGeneration++;
    _membershipGeneration++;
    await load();
  }

  void replaceInitialMuted(bool value) {
    if (_disposed) return;
    _initialIsMuted = value;
    _muteGeneration++;
    _snapshot = _snapshot.copyWith(isMuted: value);
    notifyListeners();
  }

  Future<void> setMuted(
    bool value,
    Future<void> Function(bool value)? persist,
  ) async {
    if (_disposed) return;
    final requestGeneration = _requestGeneration;
    final muteGeneration = ++_muteGeneration;
    final previous = _snapshot.isMuted;
    _snapshot = _snapshot.copyWith(isMuted: value);
    notifyListeners();
    try {
      await persist?.call(value);
    } catch (_) {
      if (!_isActive(requestGeneration) || muteGeneration != _muteGeneration) {
        rethrow;
      }
      _snapshot = _snapshot.copyWith(isMuted: previous);
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createNote(String body) async {
    if (_disposed) throw StateError(_disposedControllerMessage);
    final profileId = notesProfileId;
    if (profileId == null) {
      throw StateError('Chat partner profile is unavailable');
    }
    final requestGeneration = _requestGeneration;
    final note = await _profiles.createProfileNote(
      profileId: profileId,
      body: body,
    );
    if (!_isActive(requestGeneration)) return note;
    _snapshot = _snapshot.copyWith(
      notes: immutableChatInfoItems([note, ..._snapshot.notes]),
    );
    notifyListeners();
    return note;
  }

  Future<void> addMembers(Set<String> userIds) async {
    if (_disposed || !access.canManageGroup || userIds.isEmpty) return;
    final requestGeneration = _requestGeneration;
    final membershipGeneration = ++_membershipGeneration;
    final chatId = _request.chatId;
    await _messenger.updateGroupMembers(chatId, addUserIds: userIds.toList());
    if (!_isActive(requestGeneration) ||
        membershipGeneration != _membershipGeneration) {
      return;
    }
    final members = await _messenger.listChatMembers(chatId);
    if (!_isActive(requestGeneration) ||
        membershipGeneration != _membershipGeneration) {
      return;
    }
    _snapshot = _snapshot.copyWith(members: immutableChatInfoItems(members));
    notifyListeners();
  }

  Future<void> removeMember(String userId) async {
    if (_disposed || !access.canManageGroup || userId.isEmpty) return;
    final requestGeneration = _requestGeneration;
    final membershipGeneration = ++_membershipGeneration;
    final chatId = _request.chatId;
    await _messenger.updateGroupMembers(chatId, removeUserIds: [userId]);
    if (!_isActive(requestGeneration) ||
        membershipGeneration != _membershipGeneration) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      members: immutableChatInfoItems(
        _snapshot.members.where(
          (member) => member['user_id']?.toString() != userId,
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> leaveGroup() async {
    if (_disposed) return;
    await _messenger.leaveGroup(_request.chatId);
  }

  Future<Map<String, dynamic>> ensureDirectChat(String userId) {
    if (_disposed) {
      return Future.error(StateError(_disposedControllerMessage));
    }
    return _messenger.ensureDirectChat(userId);
  }

  Future<List<Map<String, dynamic>>> listProfilesForMembership() {
    if (_disposed) return Future.value(const <Map<String, dynamic>>[]);
    return _profiles.listProfiles(limit: 100);
  }

  void replaceChannel(Map<String, dynamic> channel) {
    if (_disposed) return;
    _snapshot = _snapshot.copyWith(data: channel);
    notifyListeners();
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

  Future<List<Map<String, dynamic>>> _loadNotes(
    ChatInfoRequest request,
    List<Map<String, dynamic>> members,
  ) async {
    final hasNotes = ChatInfoAccessPolicy(
      request: request,
      isSystemGroup: false,
    ).hasNotes;
    if (!hasNotes) {
      return const <Map<String, dynamic>>[];
    }
    final profileId = _profileIdFromMembers(members);
    if (profileId == null) return const <Map<String, dynamic>>[];
    return _profiles.listProfileNotes(profileId);
  }

  Future<ChatHistoryBuckets> _loadHistory(ChatInfoRequest request) async {
    try {
      List<Map<String, dynamic>> messages;
      if (request.chatType == 'group' || request.chatType == 'direct') {
        messages = await _messenger
            .listMessages(request.chatId, limit: 100)
            .timeout(const Duration(seconds: 15));
      } else if (request.chatType == 'channel') {
        messages = await _messenger
            .listChannelPosts(request.chatId, limit: 100)
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

  bool _isActive(int requestGeneration) =>
      !_disposed && requestGeneration == _requestGeneration;

  bool _isCurrentLoad(int requestGeneration, int loadGeneration) =>
      _isActive(requestGeneration) && loadGeneration == _loadGeneration;

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _requestGeneration++;
    _muteGeneration++;
    _membershipGeneration++;
    super.dispose();
  }
}

bool _resolvedLoadedMute({
  required int loadMuteGeneration,
  required int currentMuteGeneration,
  required bool currentIsMuted,
  required bool serverIsMuted,
  required bool initialIsMuted,
}) {
  if (loadMuteGeneration != currentMuteGeneration) return currentIsMuted;
  return serverIsMuted || initialIsMuted;
}
