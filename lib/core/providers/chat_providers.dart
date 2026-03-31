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

  // Fetch all client profiles that have messages
  final clients = await _supabase
      .from('profiles')
      .select()
      .eq('role', 'client')
      .order('first_name');

  // Get last messages and unread counts
  final enriched = <Map<String, dynamic>>[];
  for (final client in clients) {
    final cid = client['id'] as String;
    // Get last message between this client and any admin/school
    final lastMsg = await _supabase
        .from('messages')
        .select()
        .or('sender_id.eq.$cid,receiver_id.eq.$cid')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    // Get unread count for this client
    final unreadRes = await _supabase
        .from('messages')
        .select('id')
        .eq('sender_id', cid)
        .eq('is_read', false)
        .or('receiver_id.is.null,receiver_id.eq.$userId');

    final unread = (unreadRes as List).length;

    if (lastMsg != null || unread > 0) {
      enriched.add({
        ...client,
        '_last_message': lastMsg,
        '_unread_count': unread,
        '_last_message_time': lastMsg?['created_at'],
      });
    }
  }

  // Sort by last message time
  enriched.sort((a, b) {
    final aTime = a['_last_message_time'] as String?;
    final bTime = b['_last_message_time'] as String?;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  });

  yield enriched;
});

// ── Messages for a specific conversation ─────────────────────────────────────

/// Messages between current user and a specific user (or school/null receiver).
final conversationMessagesProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String?>((ref, partnerId) {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);

  if (partnerId == null) {
    // School inbox — messages with receiver_id = null
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at');
  }

  return _supabase
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('created_at');
});

// ── Group chats ──────────────────────────────────────────────────────────────

/// Group chats the current user belongs to.
final userGroupChatsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = _supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final memberships = await _supabase
      .from('group_chat_members')
      .select('group_chat_id')
      .eq('user_id', userId);

  final groupIds = (memberships as List)
      .map((m) => m['group_chat_id'] as String)
      .toList();

  if (groupIds.isEmpty) return [];

  final groups = await _supabase
      .from('group_chats')
      .select()
      .inFilter('id', groupIds)
      .order('created_at', ascending: false);

  // Enrich with last message and unread count
  final enriched = <Map<String, dynamic>>[];
  for (final group in groups) {
    final gid = group['id'] as String;
    final lastMsg = await _supabase
        .from('messages')
        .select()
        .eq('group_chat_id', gid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    enriched.add({
      ...group,
      '_last_message': lastMsg,
      '_last_message_time': lastMsg?['created_at'],
      '_type': 'group',
    });
  }

  return enriched;
});

/// Messages for a group chat.
final groupMessagesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, groupChatId) async {
  final res = await _supabase
      .from('messages')
      .select()
      .eq('group_chat_id', groupChatId)
      .order('created_at', ascending: true)
      .limit(500);
  return List<Map<String, dynamic>>.from(res);
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

/// All channels.
final channelsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await _supabase.from('channels').select().order('created_at');
  return List<Map<String, dynamic>>.from(res);
});

/// Posts for a channel.
final channelPostsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, channelId) async {
  final res = await _supabase
      .from('channel_posts')
      .select('*, profiles:author_id(first_name, last_name)')
      .eq('channel_id', channelId)
      .order('created_at', ascending: true)
      .limit(500);
  return List<Map<String, dynamic>>.from(res);
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

// ── Admin IDs (cached) ───────────────────────────────────────────────────────

/// List of admin and manager profile IDs.
final adminIdsProvider = FutureProvider<List<String>>((ref) async {
  final res = await _supabase
      .from('profiles')
      .select('id')
      .inFilter('role', ['admin', 'manager']);
  return (res as List).map((a) => a['id'].toString()).toList();
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
