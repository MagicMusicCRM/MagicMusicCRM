import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';

final magicAuthServiceProvider = Provider<MagicAuthService>((ref) {
  return MagicAuthService(ref.watch(magicApiClientProvider));
});

final magicAuthStateProvider = StreamProvider<MagicAuthSession?>((ref) {
  return ref.watch(magicAuthServiceProvider).watchSession();
});
