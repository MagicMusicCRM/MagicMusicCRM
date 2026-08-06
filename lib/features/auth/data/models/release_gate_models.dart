class ReleaseGateStatus {
  final String role;
  final bool profileComplete;
  final bool legalAccepted;
  final bool deletionPending;
  final String? sessionAccessToken;

  const ReleaseGateStatus({
    required this.role,
    required this.profileComplete,
    required this.legalAccepted,
    required this.deletionPending,
    this.sessionAccessToken,
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

  String? get publicUrl {
    switch (type) {
      case 'privacy_policy':
        return 'https://magicmusiccrm-legal.vercel.app/privacy/';
      case 'terms_of_use':
        return 'https://magicmusiccrm-legal.vercel.app/terms/';
      case 'account_deletion':
        return 'https://magicmusiccrm-legal.vercel.app/account-deletion/';
      default:
        return null;
    }
  }

  factory LegalDocument.fromJson(Map<String, dynamic> json) {
    return LegalDocument(
      id: json['id'].toString(),
      type:
          json['document_type']?.toString() ??
          json['documentType']?.toString() ??
          json['type']?.toString() ??
          '',
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
          DateTime.tryParse(
            json['requested_at']?.toString() ??
                json['requestedAt']?.toString() ??
                '',
          ) ??
          DateTime.now(),
    );
  }
}
