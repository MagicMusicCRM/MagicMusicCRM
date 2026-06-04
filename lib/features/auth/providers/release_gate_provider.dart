import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/features/auth/data/services/supa_release_gate_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supaReleaseGateServiceProvider = Provider<SupaReleaseGateService>((ref) {
  return SupaReleaseGateService(Supabase.instance.client);
});

final releaseGateStatusProvider = FutureProvider<ReleaseGateStatus>((ref) {
  return ref.watch(supaReleaseGateServiceProvider).getGateStatus();
});

final currentLegalDocumentsProvider = FutureProvider<List<LegalDocument>>((
  ref,
) {
  return ref.watch(supaReleaseGateServiceProvider).getCurrentLegalDocuments();
});

final pendingDeletionRequestProvider = FutureProvider<AccountDeletionRequest?>((
  ref,
) {
  return ref.watch(supaReleaseGateServiceProvider).getPendingDeletionRequest();
});
