import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/features/auth/data/services/supa_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supaAuthServiceProvider = Provider<SupaAuthService>((ref) {
  return SupaAuthService(Supabase.instance.client);
});
