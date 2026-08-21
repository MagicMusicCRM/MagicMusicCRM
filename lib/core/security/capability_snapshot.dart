import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';

export 'package:magic_music_crm/core/security/capability_snapshot_model.dart';

class MagicAccessService {
  const MagicAccessService(this._api);

  final MagicApiClient _api;

  Future<CapabilitySnapshot> getMySnapshot() async {
    final response = await _api.get<Map<String, dynamic>>('/access/me');
    final snapshot = CapabilitySnapshot.fromJson(response);
    if (snapshot.accountId.isEmpty || snapshot.accessVersion < 1) {
      throw const FormatException('Invalid access snapshot.');
    }
    return snapshot;
  }
}

final magicAccessServiceProvider = Provider<MagicAccessService>((ref) {
  return MagicAccessService(ref.watch(magicApiClientProvider));
});

/// Account/accessVersion-keyed server truth for navigation and affordances.
/// Invalidating this provider drops the prior snapshot before a refetch, so a
/// revoked capability cannot keep a sensitive route visible.
final capabilitySnapshotProvider = FutureProvider<CapabilitySnapshot>((ref) {
  return ref.watch(magicAccessServiceProvider).getMySnapshot();
});
