import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/compat/profile_admin_legacy_map_adapter.dart';

final magicProfileAdminServiceProvider = Provider<MagicProfileAdminService>((
  ref,
) {
  return MagicProfileAdminService(ref.watch(magicApiClientProvider));
});

class MagicProfileAdminService {
  final MagicApiClient _api;
  final ProfileAdminLegacyMapAdapter _legacyMapAdapter;

  const MagicProfileAdminService(
    this._api, {
    ProfileAdminLegacyMapAdapter legacyMapAdapter =
        const DefaultProfileAdminLegacyMapAdapter(),
  }) : _legacyMapAdapter = legacyMapAdapter;

  Future<List<Map<String, dynamic>>> listProfiles({
    String? q,
    String? role,
    int limit = 100,
  }) async {
    final queryParameters = <String, dynamic>{'limit': limit};
    if (q != null && q.trim().isNotEmpty) {
      queryParameters['q'] = q.trim();
    }
    if (role != null && role.trim().isNotEmpty) {
      queryParameters['role'] = role.trim();
    }

    final response = await _api.get<Map<String, dynamic>>(
      '/admin/profiles',
      queryParameters: queryParameters,
    );
    final items = response['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().map(_legacyProfile).toList();
  }

  Future<Map<String, dynamic>> getProfile(String profileId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/admin/profiles/$profileId',
    );
    return _legacyProfile(response);
  }

  /// The signed-in user's own profile, including `homeBranchId` / `branchIds`
  /// (the staff member's assigned branches). Used to open the schedule on the
  /// branch the user actually works at rather than the first in the system.
  ///
  /// NB: the server route is singular `/profile/me` (profile.controller.ts).
  /// The plural `/profiles/me` 404-ed forever, and the only caller swallowed
  /// the error — so the default-branch feature silently never worked.
  Future<Map<String, dynamic>> getMyProfile() async {
    return _api.get<Map<String, dynamic>>('/profile/me');
  }

  /// Загружает привязанные к профилю CRM-сущности (ученики/лиды).
  /// Возвращает список `{entityType, entityId, name}`.
  Future<List<Map<String, dynamic>>> getProfileLinks(String profileId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/admin/profiles/$profileId/links',
    );
    final items = response['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().map((item) {
      return {
        'entity_type': item['entityType'],
        'entity_id': item['entityId'],
        'name': item['name'],
      };
    }).toList();
  }

  // ── Account deletion requests (P5-7 orphan) ──────────────────────────────
  Future<List<Map<String, dynamic>>> listDeletionRequests({
    String? status,
    int? limit,
  }) async {
    final queryParameters = <String, dynamic>{};
    if (status != null && status.isNotEmpty) queryParameters['status'] = status;
    if (limit != null) queryParameters['limit'] = limit;
    final response = await _api.get<Map<String, dynamic>>(
      '/admin/deletion-requests',
      queryParameters: queryParameters,
    );
    final items = response['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> updateDeletionRequest(
    String id, {
    required String status,
    String? resolutionNote,
  }) async {
    final data = <String, dynamic>{'status': status};
    if (resolutionNote != null && resolutionNote.trim().isNotEmpty) {
      data['resolutionNote'] = resolutionNote.trim();
    }
    return _api.patch<Map<String, dynamic>>(
      '/admin/deletion-requests/$id',
      data: data,
    );
  }

  Future<Map<String, dynamic>> listLinkCandidates(String profileId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/admin/profiles/$profileId/link-candidates',
    );
    return {
      'students': _legacyCandidates(response['students']),
      'leads': _legacyCandidates(response['leads']),
      'teachers': _legacyCandidates(response['teachers']),
      'staff': _legacyCandidates(response['staff']),
    };
  }

  Future<Map<String, dynamic>> autoLinkByPhone(String profileId) async {
    return _api.post<Map<String, dynamic>>(
      '/admin/profiles/$profileId/links/auto',
    );
  }

  Future<Map<String, dynamic>> linkCrmEntity({
    required String profileId,
    required String entityType,
    required String entityId,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/admin/profiles/$profileId/links',
      data: {'entityType': entityType, 'entityId': entityId},
    );
  }

  Future<List<Map<String, dynamic>>> listProfileNotes(String profileId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/admin/profiles/$profileId/notes',
    );
    final items = response['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_legacyProfileNote)
        .toList();
  }

  Future<Map<String, dynamic>> createProfileNote({
    required String profileId,
    required String body,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/admin/profiles/$profileId/notes',
      data: {'body': body},
    );
    return _legacyProfileNote(response);
  }

  Map<String, dynamic> _legacyProfile(Map<String, dynamic> item) =>
      _legacyMapAdapter.profile(item);

  List<Map<String, dynamic>> _legacyCandidates(Object? items) {
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().map((item) {
      return {
        'id': item['id'],
        'entity_type': item['entityType'],
        'first_name': item['firstName'],
        'last_name': item['lastName'],
        'phone': item['phone'],
        'email': item['email'],
        'status': item['status'],
        'created_at': item['createdAt'],
      };
    }).toList();
  }

  Map<String, dynamic> _legacyProfileNote(Map<String, dynamic> item) =>
      _legacyMapAdapter.profileNote(item);
}
