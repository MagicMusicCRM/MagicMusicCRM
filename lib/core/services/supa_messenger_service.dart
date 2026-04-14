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
      print('SupaMessengerService: Error getting mute status: $e');
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
      print('SupaMessengerService: Error setting mute status: $e');
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
      print('SupaMessengerService: Error getting muted IDs: $e');
      return {};
    }
  }
}
