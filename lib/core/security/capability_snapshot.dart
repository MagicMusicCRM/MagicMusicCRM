import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

class CapabilitySnapshot {
  const CapabilitySnapshot({
    required this.accountId,
    required this.role,
    required this.accessVersion,
    required this.capabilities,
    required this.scopes,
  });

  factory CapabilitySnapshot.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    final rawScopes = json['scopes'];
    return CapabilitySnapshot(
      accountId: json['accountId']?.toString() ?? '',
      role: json['role']?.toString() ?? 'client',
      accessVersion: (json['accessVersion'] as num?)?.toInt() ?? 0,
      capabilities: rawCapabilities is List
          ? rawCapabilities.map((value) => value.toString()).toSet()
          : const <String>{},
      scopes: rawScopes is Map
          ? rawScopes.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }

  final String accountId;
  final String role;
  final int accessVersion;
  final Set<String> capabilities;
  final Map<String, String> scopes;

  String get cacheKey => '$accountId:$accessVersion';

  bool allows(String capability) => capabilities.contains(capability);
}

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
