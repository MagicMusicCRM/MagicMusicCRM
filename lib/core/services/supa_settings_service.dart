import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Service for managing global system settings.
class SupaSettingsService {
  static final _supabase = Supabase.instance.client;

  /// Retrieves the Administration chat avatar URL.
  static Future<String?> getAdminChatAvatar() async {
    try {
      final res = await _supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'admin_chat_avatar_url')
          .maybeSingle();
      
      if (res == null) return null;
      
      final value = res['value'];
      if (value == null) return null;
      
      // Since it's stored as a JSON value, if it's a string, it will be returned as String
      return value.toString();
    } catch (e) {
      debugPrint('SupaSettingsService: Error getting admin avatar: $e');
      return null;
    }
  }

  /// Updates the Administration chat avatar URL.
  static Future<void> updateAdminChatAvatar(String? url) async {
    try {
      await _supabase.from('system_settings').upsert({
        'key': 'admin_chat_avatar_url',
        'value': url, // Supabase client handles JSON conversion
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('SupaSettingsService: Error updating admin avatar: $e');
      rethrow;
    }
  }
}
