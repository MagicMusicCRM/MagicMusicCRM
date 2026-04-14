import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to handle Supabase message operations.
/// Follows the Prefix Service Model (Supa) from AGENTS.md.
class SupaMessageService {
  static final _supabase = Supabase.instance.client;

  /// Marks unread messages in a specific chat as read for the current user.
  /// 
  /// [currentUserId] - ID of the user performing the action.
  /// [chatId] - ID of the chat (partner profile_id for direct, or group_chat_id for group).
  /// [chatType] - 'direct' or 'group'.
  /// [isStaff] - Whether the user has a staff role (admin/manager), enabling "Administration" message reading.
  static Future<void> markMessagesAsRead({
    required String currentUserId,
    required String chatId,
    required String chatType,
    bool isStaff = false,
  }) async {
    try {
      if (chatType == 'group') {
        // For groups, mark all unread messages as read
        await _supabase
            .from('messages')
            .update({
              'is_read': true,
              'read_at': DateTime.now().toIso8601String(),
            })
            .eq('group_chat_id', chatId)
            .eq('is_read', false);
      } else {
        // Direct or Administration chat
        if (chatId == 'admin_chat') {
          // Client (student) marking all incoming admin messages as read
          await _supabase
              .from('messages')
              .update({
                'is_read': true,
                'read_at': DateTime.now().toIso8601String(),
              })
              .eq('receiver_id', currentUserId)
              .isFilter('group_chat_id', null)
              .eq('is_read', false);
        } else {
          // Marking messages from a specific partner
          // 1. Mark messages sent directly to the user
          await _supabase
              .from('messages')
              .update({
                'is_read': true,
                'read_at': DateTime.now().toIso8601String(),
              })
              .eq('receiver_id', currentUserId)
              .eq('sender_id', chatId)
              .eq('is_read', false);

          // 2. If staff, also mark 'Administration' messages from this specific partner
          if (isStaff) {
            await _supabase
                .from('messages')
                .update({
                  'is_read': true,
                  'read_at': DateTime.now().toIso8601String(),
                })
                .isFilter('receiver_id', null)
                .eq('sender_id', chatId)
                .eq('is_read', false);
          }
        }
      }
    } catch (e) {
      // Fail silently or log error
      print('SupaMessageService: Error marking messages as read: $e');
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
      print('SupaMessageService: Error marking specific IDs as read: $e');
    }
  }

  /// Fetches unread counts for the current user.
  static Future<Map<String, int>> getUnreadCounts(bool isStaff) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return {};

      // 1. Fetch admin IDs (Foundational for filtering)
      final profileRes = await _supabase
          .from('profiles')
          .select('id, role')
          .timeout(const Duration(seconds: 5));
          
      final adminIds = (profileRes as List)
          .where((a) => a['role'].toString() == 'admin' || a['role'].toString() == 'manager')
          .map((a) => a['id'].toString())
          .toList();

      // 2. Fetch unread messages
      // Query 1: Direct or Group messages addressed to me
      final query1 = _supabase
          .from('messages')
          .select('sender_id, group_chat_id')
          .eq('receiver_id', user.id)
          .eq('is_read', false)
          .timeout(const Duration(seconds: 20));

      List<dynamic> unread = [];
      List<dynamic> unreadToSchool = [];

      if (isStaff) {
        // For staff: also fetch untargeted messages (to school)
        final results = await Future.wait([
          query1,
          _supabase
              .from('messages')
              .select('sender_id')
              .isFilter('receiver_id', null)
              .isFilter('group_chat_id', null) // Only Administration messages
              .eq('is_read', false)
              .timeout(const Duration(seconds: 20)),
        ]);
        unread = results[0] as List;
        unreadToSchool = results[1] as List;
      } else {
        // For client: only fetch direct messages to them
        unread = await query1;
      }

      final counts = <String, int>{};

      // Process direct and group messages
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

      // Special handling for "Administration" chat
      if (!isStaff) {
        // For client: count messages from admins to this specific user
        int adminUnread = 0;
        for (final m in unread) {
          if (adminIds.contains(m['sender_id']?.toString())) {
            adminUnread++;
          }
        }
        counts['admin_chat'] = adminUnread;
      } else {
        // For staff: count messages from clients TO school (receiver_id is null)
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
}
