import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';
import 'package:magic_music_crm/core/workspace/workspace_store.dart';

final magicAuthServiceProvider = Provider<MagicAuthService>((ref) {
  final realtime = ref.watch(magicRealtimeServiceProvider);
  return MagicAuthService(
    ref.watch(magicApiClientProvider),
    // Dispose the authenticated transport before local tokens can change.
    // Invalidate the app-level stream only after the new token state has been
    // persisted, avoiding a reconnect race with the outgoing account.
    onBeforeSessionChange: () async {
      await ref.read(workspaceLogoutCoordinatorProvider).logoutAll();
      realtime.resetSession();
    },
    onAfterSessionChange: () => ref.invalidate(crmRealtimeProvider),
  );
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
