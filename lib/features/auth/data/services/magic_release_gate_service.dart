import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';

class MagicReleaseGateService {
  final MagicApiClient _api;

  const MagicReleaseGateService(this._api);

  Future<ReleaseGateStatus> getGateStatus() async {
    final legal = await _api.get<Map<String, dynamic>>('/legal/gate');
    return ReleaseGateStatus.fromJson(legal);
  }

  Future<void> completeOnboarding({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    await _api.patch<Map<String, dynamic>>(
      '/profile/me',
      data: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'phone': phone.trim(),
      },
    );
  }

  Future<List<LegalDocument>> getCurrentLegalDocuments() async {
    final result = await _api.get<List<dynamic>>('/legal/documents/current');
    return result
        .whereType<Map<String, dynamic>>()
        .map(LegalDocument.fromJson)
        .toList();
  }

  Future<void> acceptCurrentLegalDocuments() async {
    final documents = await getCurrentLegalDocuments();
    await _api.post<Map<String, dynamic>>(
      '/legal/consents/current',
      data: {'documentIds': documents.map((item) => item.id).toList()},
    );
  }

  Future<String> requestAccountDeletion({String? reason}) async {
    final trimmedReason = reason?.trim();
    final result = await _api.post<Map<String, dynamic>>(
      '/profile/deletion-request',
      data: {
        'acknowledgement': true,
        if (trimmedReason != null && trimmedReason.isNotEmpty)
          'reason': trimmedReason,
      },
    );
    return result['id']?.toString() ?? '';
  }

  Future<AccountDeletionRequest?> getPendingDeletionRequest() async {
    final result = await _api.get<Map<String, dynamic>?>(
      '/profile/deletion-request',
    );
    if (result == null) return null;
    return AccountDeletionRequest.fromJson(result);
  }

  Future<AccountDeletionRequest> cancelAccountDeletion() async {
    final result = await _api.delete<Map<String, dynamic>>(
      '/profile/deletion-request',
    );
    return AccountDeletionRequest.fromJson(result);
  }

  Future<String> ensureAdminChatThread() async {
    final result = await _api.post<Map<String, dynamic>>(
      '/messenger/chats/direct',
      data: {'type': 'administration'},
    );
    return result['id']?.toString() ?? '';
  }
}
