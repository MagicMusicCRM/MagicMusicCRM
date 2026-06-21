import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';

final magicProfileAdminServiceProvider = Provider<MagicProfileAdminService>((
  ref,
) {
  return MagicProfileAdminService(ref.watch(magicApiClientProvider));
});

class MagicProfileAdminService {
  final MagicApiClient _api;

  const MagicProfileAdminService(this._api);

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

  Future<Map<String, dynamic>> updateRole({
    required String profileId,
    required String role,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      '/admin/profiles/$profileId/role',
      data: {'role': role},
    );
    return _legacyProfile(response);
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

  Map<String, dynamic> _legacyProfile(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'user_id': item['userId'],
      'email': item['email'],
      'role': item['role'],
      'first_name': item['firstName'],
      'last_name': item['lastName'],
      'phone': item['phone'],
      'dob': item['dob'],
      'avatar_file_id': item['avatarFileId'],
      'email_otp_2fa_enabled': item['emailOtp2faEnabled'],
      'is_app_account': item['isAppAccount'],
      'phone_verified_at': item['phoneVerifiedAt'],
      'linked_students': item['linkedStudents'] ?? 0,
      'linked_leads': item['linkedLeads'] ?? 0,
      'linked_teachers': item['linkedTeachers'] ?? 0,
      'linked_staff': item['linkedStaff'] ?? 0,
      'candidate_students': item['candidateStudents'] ?? 0,
      'candidate_leads': item['candidateLeads'] ?? 0,
      'candidate_teachers': item['candidateTeachers'] ?? 0,
      'candidate_staff': item['candidateStaff'] ?? 0,
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
    };
  }

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

  Map<String, dynamic> _legacyProfileNote(Map<String, dynamic> item) {
    final author = item['author'];
    final legacyAuthor = author is Map<String, dynamic>
        ? {
            'id': author['id'],
            'email': author['email'],
            'first_name': author['firstName'],
            'last_name': author['lastName'],
          }
        : null;

    return {
      'id': item['id'],
      'profile_id': item['profileId'],
      'author_id': item['authorId'],
      'body': item['body'],
      'content': item['body'],
      'created_at': item['createdAt'],
      'author': legacyAuthor,
    };
  }
}
