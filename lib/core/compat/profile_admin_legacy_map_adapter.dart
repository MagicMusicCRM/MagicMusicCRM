/// Compatibility boundary for admin presentation consumers that still expect
/// historical snake_case profile maps. Remove when they use typed models.
abstract interface class ProfileAdminLegacyMapAdapter {
  Map<String, dynamic> profile(Map<String, dynamic> source);
  Map<String, dynamic> profileNote(Map<String, dynamic> source);
}

class DefaultProfileAdminLegacyMapAdapter
    implements ProfileAdminLegacyMapAdapter {
  const DefaultProfileAdminLegacyMapAdapter();

  @override
  Map<String, dynamic> profile(Map<String, dynamic> item) => {
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

  @override
  Map<String, dynamic> profileNote(Map<String, dynamic> item) {
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
