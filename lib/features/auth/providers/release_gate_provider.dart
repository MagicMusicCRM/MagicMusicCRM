import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_release_gate_service.dart';

final releaseGateServiceProvider = Provider<MagicReleaseGateService>((ref) {
  return MagicReleaseGateService(ref.watch(magicApiClientProvider));
});

final releaseGateStatusProvider = FutureProvider<ReleaseGateStatus>((ref) {
  return ref.watch(releaseGateServiceProvider).getGateStatus();
});

final currentLegalDocumentsProvider = FutureProvider<List<LegalDocument>>((
  ref,
) {
  return ref.watch(releaseGateServiceProvider).getCurrentLegalDocuments();
});

final pendingDeletionRequestProvider = FutureProvider<AccountDeletionRequest?>((
  ref,
) {
  return ref.watch(releaseGateServiceProvider).getPendingDeletionRequest();
});
