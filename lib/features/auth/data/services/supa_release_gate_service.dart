import 'package:supabase_flutter/supabase_flutter.dart';

class ReleaseGateStatus {
  final String role;
  final bool profileComplete;
  final bool legalAccepted;
  final bool deletionPending;

  const ReleaseGateStatus({
    required this.role,
    required this.profileComplete,
    required this.legalAccepted,
    required this.deletionPending,
  });

  factory ReleaseGateStatus.fromJson(Map<String, dynamic> json) {
    return ReleaseGateStatus(
      role: json['role']?.toString() ?? 'client',
      profileComplete: json['profileComplete'] == true,
      legalAccepted: json['legalAccepted'] == true,
      deletionPending: json['deletionPending'] == true,
    );
  }
}

class LegalDocument {
  final String id;
  final String type;
  final String title;
  final String version;
  final String content;

  const LegalDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.version,
    required this.content,
  });

  factory LegalDocument.fromJson(Map<String, dynamic> json) {
    return LegalDocument(
      id: json['id'].toString(),
      type: json['document_type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
    );
  }
}

class AccountDeletionRequest {
  final String id;
  final String status;
  final String? reason;
  final DateTime requestedAt;

  const AccountDeletionRequest({
    required this.id,
    required this.status,
    required this.requestedAt,
    this.reason,
  });

  factory AccountDeletionRequest.fromJson(Map<String, dynamic> json) {
    return AccountDeletionRequest(
      id: json['id'].toString(),
      status: json['status']?.toString() ?? 'pending',
      reason: json['reason']?.toString(),
      requestedAt:
          DateTime.tryParse(json['requested_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class SupaReleaseGateService {
  final SupabaseClient _client;

  const SupaReleaseGateService(this._client);

  Future<ReleaseGateStatus> getGateStatus() async {
    final result = await _client.rpc('get_release_gate_status');
    return ReleaseGateStatus.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<void> completeOnboarding({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    await _client.rpc(
      'complete_onboarding',
      params: {
        'p_first_name': firstName,
        'p_last_name': lastName,
        'p_phone': phone,
      },
    );
  }

  Future<List<LegalDocument>> getCurrentLegalDocuments() async {
    final result = await _client
        .from('legal_documents')
        .select('id, document_type, title, version, content')
        .eq('is_current', true)
        .order('document_type');

    return List<Map<String, dynamic>>.from(
      result,
    ).map(LegalDocument.fromJson).toList();
  }

  Future<void> acceptCurrentLegalDocuments() async {
    await _client.rpc('accept_current_legal_documents');
  }

  Future<String> requestAccountDeletion({String? reason}) async {
    final result = await _client.rpc(
      'request_account_deletion',
      params: {'p_reason': reason},
    );
    return result.toString();
  }

  Future<AccountDeletionRequest?> getPendingDeletionRequest() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final result = await _client
        .from('account_deletion_requests')
        .select('id, status, reason, requested_at')
        .eq('user_id', userId)
        .inFilter('status', ['pending', 'processing'])
        .order('requested_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (result == null) return null;
    return AccountDeletionRequest.fromJson(Map<String, dynamic>.from(result));
  }

  Future<String> ensureAdminChatThread() async {
    final result = await _client.rpc('ensure_admin_chat_thread');
    return result.toString();
  }
}
