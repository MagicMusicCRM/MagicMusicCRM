import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

class ManagedCapability {
  const ManagedCapability({
    required this.key,
    required this.domain,
    required this.overrideMode,
    required this.packageEffect,
    required this.overrideEffect,
    required this.effectiveAllowed,
  });

  factory ManagedCapability.fromJson(Map<String, dynamic> json) {
    return ManagedCapability(
      key: json['key']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      overrideMode: json['overrideMode']?.toString() ?? 'locked',
      packageEffect: json['packageEffect']?.toString() ?? 'deny',
      overrideEffect: json['overrideEffect']?.toString(),
      effectiveAllowed: json['effectiveAllowed'] == true,
    );
  }

  final String key;
  final String domain;
  final String overrideMode;
  final String packageEffect;
  final String? overrideEffect;
  final bool effectiveAllowed;

  bool get canDeny => overrideMode != 'locked';
  bool get canAllow => overrideMode == 'allow_deny';
}

class ManagedUserAccess {
  const ManagedUserAccess({
    required this.userId,
    required this.role,
    required this.accessVersion,
    required this.packageVersion,
    required this.capabilities,
  });

  factory ManagedUserAccess.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    final rolePackage =
        json['rolePackage'] as Map<String, dynamic>? ?? const {};
    final definitions = json['definitions'];
    return ManagedUserAccess(
      userId: user['id']?.toString() ?? '',
      role: user['role']?.toString() ?? 'client',
      accessVersion: (user['accessVersion'] as num?)?.toInt() ?? 1,
      packageVersion: (rolePackage['version'] as num?)?.toInt() ?? 1,
      capabilities: definitions is List
          ? definitions
                .whereType<Map<String, dynamic>>()
                .map(ManagedCapability.fromJson)
                .where((item) => item.key.isNotEmpty)
                .toList()
          : const [],
    );
  }

  final String userId;
  final String role;
  final int accessVersion;
  final int packageVersion;
  final List<ManagedCapability> capabilities;
}

abstract interface class AccessManagementDataSource {
  Future<ManagedUserAccess> getUserAccess(String userId);

  Future<void> assignRole({
    required String userId,
    required String role,
    required int expectedVersion,
    required bool resetOverridesConfirmed,
    required bool emergencySurface,
    required String reasonCode,
    required MagicMutationIdentity identity,
  });

  Future<void> setOverride({
    required String userId,
    required String capabilityKey,
    required String effect,
    required int expectedVersion,
    required bool emergencySurface,
    required String reasonCode,
    required MagicMutationIdentity identity,
  });
}

class MagicAccessManagementService implements AccessManagementDataSource {
  const MagicAccessManagementService(this._api);

  final MagicApiClient _api;

  @override
  Future<ManagedUserAccess> getUserAccess(String userId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/access/users/$userId',
    );
    return ManagedUserAccess.fromJson(response);
  }

  @override
  Future<void> assignRole({
    required String userId,
    required String role,
    required int expectedVersion,
    required bool resetOverridesConfirmed,
    required bool emergencySurface,
    required String reasonCode,
    required MagicMutationIdentity identity,
  }) async {
    await _api.request<Map<String, dynamic>>(
      'PUT',
      '/access/users/$userId/role',
      mutationIdentity: identity,
      data: {
        'role': role,
        'expectedVersion': expectedVersion,
        'resetOverridesConfirmed': resetOverridesConfirmed,
        'emergencySurface': emergencySurface,
        'reasonCode': reasonCode,
      },
    );
  }

  @override
  Future<void> setOverride({
    required String userId,
    required String capabilityKey,
    required String effect,
    required int expectedVersion,
    required bool emergencySurface,
    required String reasonCode,
    required MagicMutationIdentity identity,
  }) async {
    await _api.request<Map<String, dynamic>>(
      'PUT',
      '/access/users/$userId/overrides/$capabilityKey',
      mutationIdentity: identity,
      data: {
        'effect': effect,
        'expectedVersion': expectedVersion,
        'emergencySurface': emergencySurface,
        'reasonCode': reasonCode,
      },
    );
  }
}

final accessManagementServiceProvider = Provider<AccessManagementDataSource>((
  ref,
) {
  return MagicAccessManagementService(ref.watch(magicApiClientProvider));
});
