/// Single source of truth for which CRM destinations each role may see.
/// Unit-tested in `test/features/rbac_nav_matrix_test.dart`.
///
/// Business hierarchy (KVA-239): **client < teacher < admin < manager <
/// director < system_admin** — Управляющий (`manager`) выше Администратора
/// (`admin`), Директор (`director`) выше Управляющего.
/// Role editing follows that hierarchy, but day-to-day CRM operations are
/// collaborative: `admin`, `manager`, `director` and `system_admin` all see
/// the working CRM sections so administrators can cover each other's shifts.
///
/// Canonical (non-teacher) tab index meaning:
///   0 Чат · 1 Обзор · 2 Расписание · 3 Клиенты ·
///   4 Пользователи · 5 Финансы · 6 Задачи · 7 Отчёты.
/// Teacher reuses 0/1/2 for Чат/Расписание/Ученики.
library;

/// Operational CRM tab indices shared by admin/manager/director/system_admin.
const List<int> kManagerOnlyCrmTabs = [1, 4, 6, 7];

/// Whether [role] has access to operational CRM destinations.
bool crmHasManagerAccess(String role) =>
    role == 'admin' ||
    role == 'manager' ||
    role == 'director' ||
    role == 'system_admin';

/// KVA-239: ОБЩЕШКОЛЬНЫЕ финансы и финансовая аналитика (раздел «Финансы»,
/// отчёт по выручке, расходы, помесячные финансы) — только Директор и
/// Администратор системы. Управляющий/Администратор исключены; финансы в
/// КАРТОЧКАХ клиентов (история оплат, баланс, личный счёт) у них остаются.
bool crmHasSchoolFinanceAccess(String role) =>
    role == 'director' || role == 'system_admin';

/// Canonical CRM tab indices visible to [role], in display order.
List<int> crmVisibleTabs(String role, {required bool isDesktop}) {
  if (role == 'teacher') return const [0, 1, 2];
  // Финансы/Задачи/Отчёты remain desktop-only, preserved from the legacy
  // behaviour. Финансы (5) — only for roles with school-finance access.
  if (!isDesktop) return const [0, 1, 2, 3, 4];
  return crmHasSchoolFinanceAccess(role)
      ? const [0, 1, 2, 3, 4, 5, 6, 7]
      : const [0, 1, 2, 3, 4, 6, 7];
}
