import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to manage messenger-related preferences, specifically mute status.
/// Follows the Prefix Service Model (Supa) from AGENTS.md.
class SupaMessengerService {
  static final _supabase = Supabase.instance.client;

  /// Retrieves the mute status for a specific chat.
  static Future<bool> isChatMuted(String chatId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final res = await _supabase
          .from('chat_preferences')
          .select('is_muted')
          .eq('user_id', userId)
          .eq('chat_id', chatId)
          .maybeSingle();

      return res?['is_muted'] ?? false;
    } catch (e) {
      debugPrint('SupaMessengerService: Error getting mute status: $e');
      return false;
    }
  }

  /// Sets the mute status for a specific chat.
  static Future<void> setChatMuteStatus({
    required String chatId,
    required String chatType,
    required bool isMuted,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('chat_preferences').upsert({
        'user_id': userId,
        'chat_id': chatId,
        'chat_type': chatType,
        'is_muted': isMuted,
      });
    } catch (e) {
      debugPrint('SupaMessengerService: Error setting mute status: $e');
    }
  }

  /// Fetches all muted chat IDs for the current user.
  /// Useful for local caching/filtering.
  static Future<Set<String>> getMutedChatIds() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return {};

      final res = await _supabase
          .from('chat_preferences')
          .select('chat_id')
          .eq('user_id', userId)
          .eq('is_muted', true);

      return (res as List).map((row) => row['chat_id'].toString()).toSet();
    } catch (e) {
      debugPrint('SupaMessengerService: Error getting muted IDs: $e');
      return {};
    }
  }

  /// Toggles the pinned status for a specific chat.
  static Future<void> togglePinChat({
    required String chatId,
    required String chatType,
    required bool isPinned,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('chat_preferences').upsert({
        'user_id': userId,
        'chat_id': chatId,
        'chat_type': chatType,
        'is_pinned': isPinned,
        'pinned_at': isPinned ? DateTime.now().toIso8601String() : null,
      });
    } catch (e) {
      debugPrint('SupaMessengerService: Error toggling pin status: $e');
    }
  }

  /// Fetches all pinned chat IDs for the current user.
  static Future<Set<String>> getPinnedChatIds() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return {};

      final res = await _supabase
          .from('chat_preferences')
          .select('chat_id')
          .eq('user_id', userId)
          .eq('is_pinned', true);

      return (res as List).map((row) => row['chat_id'].toString()).toSet();
    } catch (e) {
      debugPrint('SupaMessengerService: Error getting pinned IDs: $e');
      return {};
    }
  }

  /// Updates the 'last_seen_at' timestamp for the current user.
  static Future<void> updateLastSeen() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      
      // Use the RPC for SECURITY DEFINER safety or simple update
      await _supabase.from('profiles').update({
        'last_seen_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (e) {
      debugPrint('SupaMessengerService: Error updating last seen: $e');
    }
  }
}
