import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_release_gate_service.dart';

class SessionBoundReleaseGateError implements Exception {
  const SessionBoundReleaseGateError(this.sessionAccessToken, this.error);

  final String? sessionAccessToken;
  final Object error;

  @override
  String toString() => error.toString();
}

bool releaseGateErrorBelongsToSession(Object error, String accessToken) =>
    error is! SessionBoundReleaseGateError ||
    error.sessionAccessToken == accessToken;

final releaseGateServiceProvider = Provider<MagicReleaseGateService>((ref) {
  return MagicReleaseGateService(ref.watch(magicApiClientProvider));
});

final releaseGateStatusProvider = FutureProvider<ReleaseGateStatus>((
  ref,
) async {
  final accessToken =
      (await ref.read(magicApiClientProvider).readTokens())?.accessToken;
  try {
    final status = await ref.watch(releaseGateServiceProvider).getGateStatus();
    return ReleaseGateStatus(
      role: status.role,
      profileComplete: status.profileComplete,
      legalAccepted: status.legalAccepted,
      deletionPending: status.deletionPending,
      sessionAccessToken: accessToken,
    );
  } catch (error) {
    throw SessionBoundReleaseGateError(accessToken, error);
  }
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
