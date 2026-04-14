import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _supabase = Supabase.instance.client;

// ── Current user info ────────────────────────────────────────────────────────

/// Current user's profile data.
final currentProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return null;
  return await _supabase.from('profiles').select().eq('id', user.id).maybeSingle();
});

/// Current user's role.
final currentRoleProvider = FutureProvider<String>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  return (profile?['role'] as String?) ?? 'client';
});

class MessengerNavigationState {
  final String? partnerId;
  final String? groupChatId;
  const MessengerNavigationState({this.partnerId, this.groupChatId});
}

class MessengerNavigationNotifier extends Notifier<MessengerNavigationState?> {
  @override
  MessengerNavigationState? build() => null;
  void navigateTo(MessengerNavigationState? newState) => state = newState;
  void clear() => state = null;
}

final messengerNavigationProvider = NotifierProvider<MessengerNavigationNotifier, MessengerNavigationState?>(MessengerNavigationNotifier.new);


/// List of admin and manager profile IDs (for deciding what counts as an "Administration" message).
final adminIdsProvider = FutureProvider<List<String>>((ref) async {
  final res = await _supabase
      .from('profiles')
      .select('id')
      .inFilter('role', ['admin', 'manager']);
  return (res as List).map((a) => a['id'].toString()).toList();
});

// ── Direct chats (for admins/managers — list of client conversations) ────────

/// Provides list of conversations for admin/manager.
/// Returns profiles of all clients who have sent messages.
final clientConversationsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) {
    yield [];
    return;
  }

  // Subscribe to profiles changes where role is client
  final profilesStream = _supabase
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('role', 'client')
      .order('first_name');

  await for (final clients in profilesStream) {
    final enriched = await Future.wait(clients.map((client) async {
      final cid = client['id'] as String;
      // Get last message and unread count in parallel for each client
      final results = await Future.wait([
        _supabase
            .from('messages')
            .select()
            .or('sender_id.eq.$cid,receiver_id.eq.$cid')
            .isFilter('group_chat_id', null)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle() as Future<dynamic>,
        _supabase
            .from('messages')
            .select('id')
            .eq('sender_id', cid)
            .eq('is_read', false)
            .isFilter('group_chat_id', null)
            .or('receiver_id.is.null,receiver_id.eq.$userId') as Future<dynamic>,
      ]);

      final lastMsg = results[0] as Map<String, dynamic>?;
      final unread = (results[1] as List).length;

      if (lastMsg != null || unread > 0) {
        return {
          ...client,
          '_last_message': lastMsg,
          '_unread_count': unread,
          '_last_message_time': lastMsg?['created_at'],
        };
      }
      return <String, dynamic>{};
    }));

    final filteredEnriched = enriched.where((e) => e.isNotEmpty).toList();

    // Sort by last message time
    filteredEnriched.sort((a, b) {
      final aTime = a['_last_message_time'] as String?;
      final bTime = b['_last_message_time'] as String?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    yield filteredEnriched;
  }
});

// ── Messages for a specific conversation ─────────────────────────────────────

/// Messages between current user and a specific user (or school/null receiver).
final conversationMessagesProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String?>((ref, partnerId) {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);

  var query = _supabase.from('messages').stream(primaryKey: ['id']);

  if (partnerId == null) {
    // School inbox (Administration)
    return query
        .order('created_at', ascending: true)
        .map((messages) => messages.where((m) => m['group_chat_id'] == null && m['receiver_id'] == null).toList());
  }

  // Direct chat with partner
  return query
      .order('created_at', ascending: true)
      .map((messages) => messages.where((m) {
            final gid = m['group_chat_id'];
            if (gid != null) return false;
            final senderId = m['sender_id'];
            final receiverId = m['receiver_id'];
            return (senderId == userId && receiverId == partnerId) ||
                   (senderId == partnerId && receiverId == userId);
          }).toList());
});

// ── Group chats ──────────────────────────────────────────────────────────────

/// Group chats the current user belongs to.
final userGroupChatsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) {
    yield [];
    return;
  }

  // Subscribe to memberships to know when groups are added/removed
  final membershipsStream = _supabase
      .from('group_chat_members')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId);

  await for (final memberships in membershipsStream) {
    final groupIds = memberships.map((m) => m['group_chat_id'] as String).toList();
    if (groupIds.isEmpty) {
      yield [];
      continue;
    }

    final groups = await _supabase
        .from('group_chats')
        .select('*, first_responder:profiles!first_responder_id(first_name, last_name)')
        .inFilter('id', groupIds)
        .order('created_at', ascending: false);

    // Enrich with last message in parallel
    final enriched = await Future.wait(groups.map((group) async {
      final gid = group['id'] as String;
      final lastMsg = await _supabase
          .from('messages')
          .select()
          .eq('group_chat_id', gid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return {
        ...group,
        '_last_message': lastMsg,
        '_last_message_time': lastMsg?['created_at'],
        '_type': 'group',
      };
    }));

    yield enriched;
  }
});

// ── Presence (For "Admin X is handling this") ────────────────────────────────

/// Presence state for a specific chat.
/// Listens to a channel and returns list of active admin names.
final chatPresenceProvider =
    StreamProvider.family<List<String>, String>((ref, chatId) async* {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null || (profile['role'].toString() != 'admin' && profile['role'].toString() != 'manager')) {
    yield [];
    return;
  }

  final channel = _supabase.channel('chat_presence:$chatId');
  // Join Presence
  channel.subscribe((status, [error]) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      channel.track({
        'user_id': profile['id'],
        'online_at': DateTime.now().toIso8601String(),
      });
    }
  });

  // Listen to sync
  final stream = StreamController<List<String>>();
  
  channel.onPresenceSync((payload) {
    final state = channel.presenceState();
    final activeAdmins = <String>[];
    
    for (final presence in state) {
      final p = (presence as dynamic).payload;
      // Only show other admins
      if (p['user_id'] != profile['id'] && (p['role'] == 'admin' || p['role'] == 'manager')) {
        activeAdmins.add(p['name'] as String);
      }
    }
    
    stream.add(activeAdmins.toSet().toList());
  });

  ref.onDispose(() {
    channel.unsubscribe();
    stream.close();
  });

  yield* stream.stream;
});

/// Real-time messages for a group chat.
final groupMessagesProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, groupChatId) {
  return _supabase
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('group_chat_id', groupChatId)
      .order('created_at', ascending: true);
});

/// Members of a group chat with profile info.
final groupMembersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, groupChatId) async {
  final members = await _supabase
      .from('group_chat_members')
      .select('*, profiles(*)')
      .eq('group_chat_id', groupChatId);
  return List<Map<String, dynamic>>.from(members);
});

// ── Channels ─────────────────────────────────────────────────────────────────

/// All channels (real-time).
final channelsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return _supabase
      .from('channels')
      .stream(primaryKey: ['id'])
      .order('created_at');
});

/// Real-time posts for a channel.
final channelPostsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, channelId) {
  return _supabase
      .from('channel_posts')
      .stream(primaryKey: ['id'])
      .eq('channel_id', channelId)
      .order('created_at', ascending: true);
});

/// Current user's permissions for a channel.
final channelUserPermissionProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, channelId) async {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) return null;
  return await _supabase
      .from('channel_permissions')
      .select()
      .eq('channel_id', channelId)
      .eq('user_id', userId)
      .maybeSingle();
});

/// All permissions for a channel (for manager to manage).
final channelAllPermissionsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, channelId) async {
  final res = await _supabase
      .from('channel_permissions')
      .select('*, profiles:user_id(first_name, last_name, role)')
      .eq('channel_id', channelId);
  return List<Map<String, dynamic>>.from(res);
});

// ── All profiles (for group creation) ────────────────────────────────────────

/// All profiles for admin group creation.
final allProfilesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await _supabase
      .from('profiles')
      .select()
      .order('first_name');
  return List<Map<String, dynamic>>.from(res);
});
