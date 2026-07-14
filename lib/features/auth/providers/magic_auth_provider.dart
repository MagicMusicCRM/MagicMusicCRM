import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';

final magicAuthServiceProvider = Provider<MagicAuthService>((ref) {
  return MagicAuthService(ref.watch(magicApiClientProvider));
});

final magicAuthStateProvider = StreamProvider<MagicAuthSession?>((ref) {
  return ref.watch(magicAuthServiceProvider).watchSession();
});

/// Current authenticated user's id (from the profile). Resolves once after
/// login and is cached; used for recipient-scoped realtime hints (e.g. the
/// «У вас новая задача» popup). Returns null when signed out.
final currentUserIdProvider = FutureProvider<String?>((ref) async {
  final session = ref.watch(magicAuthStateProvider).asData?.value;
  if (session == null) return null;
  try {
    return (await ref.read(magicAuthServiceProvider).currentProfile()).userId;
  } catch (_) {
    return null;
  }
});
