import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to handle Supabase message operations.
/// Follows the Prefix Service Model (Supa) from AGENTS.md.
class SupaMessageService {
  static final _supabase = Supabase.instance.client;

  /// Marks unread messages in a specific chat as read for the current user.
  static Future<void> markMessagesAsRead({
    required String currentUserId,
    required String chatId,
    required String chatType,
    bool isStaff = false,
  }) async {
    try {
      if (chatType == 'group') {
        await _supabase
            .from('messages')
            .update({
              'is_read': true,
              'read_at': DateTime.now().toIso8601String(),
            })
            .eq('group_chat_id', chatId)
            .eq('is_read', false);
      } else {
        if (chatId == 'admin_chat') {
          await _supabase
              .from('messages')
              .update({
                'is_read': true,
                'read_at': DateTime.now().toIso8601String(),
              })
              .eq('receiver_id', currentUserId)
              .filter('group_chat_id', 'is', 'null')
              .eq('is_read', false);
        } else {
          await _supabase
              .from('messages')
              .update({
                'is_read': true,
                'read_at': DateTime.now().toIso8601String(),
              })
              .eq('receiver_id', currentUserId)
              .eq('sender_id', chatId)
              .eq('is_read', false);

          if (isStaff) {
            await _supabase
                .from('messages')
                .update({
                  'is_read': true,
                  'read_at': DateTime.now().toIso8601String(),
                })
                .filter('receiver_id', 'is', 'null')
                .eq('sender_id', chatId)
                .eq('is_read', false);
          }
        }
      }
    } catch (e) {
      debugPrint('SupaMessageService: Error marking messages as read: $e');
    }
  }

  /// Marks a specific list of message IDs as read.
  static Future<void> markIdsAsRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    try {
      await _supabase
          .from('messages')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .filter('id', 'in', messageIds);
    } catch (e) {
      debugPrint('SupaMessageService: Error marking specific IDs as read: $e');
    }
  }

  /// Fetches unread counts for the current user.
  static Future<Map<String, int>> getUnreadCounts(bool isStaff) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return {};

      final profileRes = await _supabase
          .from('profiles')
          .select('id, role')
          .timeout(const Duration(seconds: 10));
          
      final adminIds = (profileRes as List)
          .where((a) => a['role'].toString() == 'admin' || a['role'].toString() == 'manager')
          .map((a) => a['id'].toString())
          .toList();

      final query1 = _supabase
          .from('messages')
          .select('sender_id, group_chat_id')
          .eq('receiver_id', user.id)
          .eq('is_read', false)
          .timeout(const Duration(seconds: 30));

      List<dynamic> unread = [];
      List<dynamic> unreadToSchool = [];

      if (isStaff) {
        // Use Future.wait with explicit typing to avoid inference issues
        final results = await Future.wait<dynamic>(<Future<dynamic>>[
          query1,
          _supabase
              .from('messages')
              .select('sender_id')
              .filter('receiver_id', 'is', 'null')
              .filter('group_chat_id', 'is', 'null')
              .eq('is_read', false)
              .timeout(const Duration(seconds: 30)),
        ]);
        unread = results[0] as List;
        unreadToSchool = results[1] as List;
      } else {
        unread = await query1;
      }

      final counts = <String, int>{};
      for (final m in unread) {
        final gid = m['group_chat_id']?.toString();
        if (gid != null) {
          counts[gid] = (counts[gid] ?? 0) + 1;
        } else {
          final sender = m['sender_id']?.toString() ?? '';
          if (sender.isNotEmpty) {
            counts[sender] = (counts[sender] ?? 0) + 1;
          }
        }
      }

      if (!isStaff) {
        int adminUnread = 0;
        for (final m in unread) {
          if (adminIds.contains(m['sender_id']?.toString())) {
            adminUnread++;
          }
        }
        counts['admin_chat'] = adminUnread;
      } else {
        for (final m in unreadToSchool) {
          final sender = m['sender_id']?.toString() ?? '';
          if (sender.isNotEmpty && !adminIds.contains(sender)) {
            counts[sender] = (counts[sender] ?? 0) + 1;
          }
        }
      }

      return counts;
    } catch (e) {
      debugPrint('SupaMessageService: Error fetching unread counts: $e');
      return {};
    }
  }

  /// Sends a new message (Standard, Reply, or Forward).
  static Future<Map<String, dynamic>?> sendMessage({
    required String senderId,
    String? receiverId,
    String? groupChatId,
    required String content,
    String? messageType = 'text',
    String? attachmentUrl,
    String? attachmentName,
    int? attachmentSize,
    String? replyToId,
    String? forwardedFromId,
  }) async {
    try {
      return await _supabase.from('messages').insert({
        'sender_id': senderId,
        'receiver_id': receiverId,
        'group_chat_id': groupChatId,
        'content': content,
        'message_type': messageType,
        'attachment_url': attachmentUrl,
        'attachment_name': attachmentName,
        'attachment_size': attachmentSize,
        'reply_to_id': replyToId,
        'forwarded_from_id': forwardedFromId,
      }).select().single();
    } catch (e) {
      debugPrint('SupaMessageService: Error sending message: $e');
      return null;
    }
  }

  /// Edits an existing message's content.
  static Future<void> editMessage(String messageId, String newContent) async {
    try {
      await _supabase.from('messages').update({
        'content': newContent,
        'is_edited': true,
      }).eq('id', messageId);
    } catch (e) {
      debugPrint('SupaMessageService: Error editing message: $e');
    }
  }

  /// Soft deletes a message for everyone.
  static Future<bool> deleteMessage(String messageId) async {
    try {
      await _supabase.from('messages').update({
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', messageId);
      return true;
    } catch (e) {
      debugPrint('SupaMessageService: Error deleting message: $e');
      return false;
    }
  }

  /// Toggles pinning for a message.
  static Future<void> toggleMessagePin({
    required String messageId,
    required bool isPinned,
    String? groupChatId,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('messages').update({
        'pinned_at': isPinned ? DateTime.now().toIso8601String() : null,
        'pinned_by_id': isPinned ? user.id : null,
      }).eq('id', messageId);

      // If it's a known group chat, we can also update the group's specific pinned reference
      // though getPinnedMessages often relies on the message's pinned_at column instead.
      if (groupChatId != null && groupChatId != 'admin_chat') {
        await _supabase.from('group_chats').update({
          'pinned_message_id': isPinned ? messageId : null,
        }).eq('id', groupChatId);
      }
    } catch (e) {
      debugPrint('SupaMessageService: Error toggling pin: $e');
    }
  }

  /// Adds a reaction to a message.
  static Future<void> addReaction({
    required String messageId,
    required String emoji,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('message_reactions').upsert({
        'message_id': messageId,
        'user_id': user.id,
        'emoji': emoji,
      });
    } catch (e) {
      debugPrint('SupaMessageService: Error adding reaction: $e');
    }
  }

  /// Removes a reaction from a message.
  static Future<void> removeReaction({
    required String messageId,
    required String emoji,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', user.id)
          .eq('emoji', emoji);
    } catch (e) {
      debugPrint('SupaMessageService: Error removing reaction: $e');
    }
  }

  /// Fetches pinned messages for a specific chat.
  static Future<List<Map<String, dynamic>>> getPinnedMessages(
    String chatId,
    String chatType,
  ) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      var query = _supabase.from('messages')
          .select('*, profiles:sender_id(first_name, last_name), forwarded_profiles:forwarded_from_id(first_name, last_name)')
          .not('pinned_at', 'is', null)
          .filter('deleted_at', 'is', 'null');

      if (chatType == 'group') {
        return await query.eq('group_chat_id', chatId).order('pinned_at', ascending: false);
      } else if (chatId == 'admin_chat') {
        // Virtual admin chat for students
        return await query.or('and(sender_id.eq.${user.id},receiver_id.is.null),receiver_id.eq.${user.id}').order('pinned_at', ascending: false);
      } else {
        // Direct chats
        return await query.or('and(sender_id.eq.$chatId,or(receiver_id.eq.${user.id},receiver_id.is.null)),and(sender_id.eq.${user.id},receiver_id.eq.$chatId)').order('pinned_at', ascending: false);
      }
    } catch (e) {
      debugPrint('SupaMessageService: Error fetching pinned messages: $e');
      return [];
    }
  }

  /// Searches for messages containing a query string within a specific chat.
  static Future<List<Map<String, dynamic>>> searchMessages({
    required String query,
    required String chatId,
    required String chatType,
  }) async {
    try {
      var baseQuery = _supabase.from('messages')
          .select('*, profiles:sender_id(first_name, last_name), forwarded_profiles:forwarded_from_id(first_name, last_name)')
          .ilike('content', '%$query%');
      
      if (chatType == 'group') {
        return await baseQuery.eq('group_chat_id', chatId).order('created_at', ascending: false).limit(50);
      } else {
        final userId = _supabase.auth.currentUser?.id;
        if (userId == null) return [];
        
        return await baseQuery
            .or('and(sender_id.eq.$chatId,receiver_id.eq.$userId),and(sender_id.eq.$userId,receiver_id.eq.$chatId)')
            .order('created_at', ascending: false)
            .limit(50);
      }
    } catch (e) {
      debugPrint('SupaMessageService: Error searching messages: $e');
      return [];
    }
  }

  /// Fetches reactions for a list of message IDs.
  static Future<List<dynamic>> getReactionsForMessages(List<String> messageIds) async {
    if (messageIds.isEmpty) return [];
    try {
      return await _supabase
          .from('message_reactions')
          .select()
          .filter('message_id', 'in', messageIds);
    } catch (e) {
      debugPrint('SupaMessageService: Error fetching reactions: $e');
      return [];
    }
  }
}
