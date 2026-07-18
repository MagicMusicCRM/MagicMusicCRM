import 'package:magic_music_crm/core/api/magic_api_client.dart';

/// Клиент справочника сотрудников для пикера «Ответственный» (#7).
///
/// Контракт (закреплён): `GET /api/admin/staff?search=&roles=admin,manager,director`
/// → `200 [{id, displayName, role}]`, доступ admin+. Живёт extension'ом на
/// [MagicApiClient] в папке карточки, а не в общих сервисах, — общие API-файлы
/// параллельно правят другие фичи.
extension ClientCardStaffApi on MagicApiClient {
  /// Список сотрудников для выбора ответственного. [search] — подстрока имени,
  /// [roles] — CSV ролей (по умолчанию все админ-роли на сервере).
  Future<List<Map<String, dynamic>>> listResponsibleStaff({
    String? search,
    String roles = 'admin,manager,director',
  }) async {
    final response = await get<List<dynamic>>(
      '/admin/staff',
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'roles': roles,
      },
    );
    return response.whereType<Map<String, dynamic>>().toList();
  }
}
