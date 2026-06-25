/// Single source of truth for which CRM destinations each role may see.
/// Unit-tested in `test/features/rbac_nav_matrix_test.dart`.
///
/// Business hierarchy: **Управляющий (`manager`) > Администратор (`admin`)**.
/// Role editing still follows that hierarchy, but day-to-day CRM operations are
/// collaborative: `admin`, `manager`, and `system_admin` all see the working
/// CRM sections so administrators can cover each other's shifts.
///
/// Canonical (non-teacher) tab index meaning:
///   0 Чат · 1 Обзор · 2 Расписание · 3 Клиенты ·
///   4 Пользователи · 5 Финансы · 6 Задачи · 7 Отчёты.
/// Teacher reuses 0/1/2 for Чат/Расписание/Ученики.
library;

/// Operational CRM tab indices shared by admin/manager/system_admin.
const List<int> kManagerOnlyCrmTabs = [1, 4, 5, 6, 7];

/// Whether [role] has access to operational CRM destinations.
bool crmHasManagerAccess(String role) =>
    role == 'admin' || role == 'manager' || role == 'system_admin';

/// Canonical CRM tab indices visible to [role], in display order.
List<int> crmVisibleTabs(String role, {required bool isDesktop}) {
  if (role == 'teacher') return const [0, 1, 2];
  // Admin + manager + system_admin: full operational set. Финансы/Задачи/Отчёты
  // remain desktop-only, preserved from the legacy behaviour.
  return isDesktop ? const [0, 1, 2, 3, 4, 5, 6, 7] : const [0, 1, 2, 3, 4];
}
