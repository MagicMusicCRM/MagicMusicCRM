/// Single source of truth for which CRM destinations each role may see — the
/// A1 hierarchy enforcement (KVA-194 / P1-2). Unit-tested in
/// `test/features/rbac_nav_matrix_test.dart`.
///
/// Business hierarchy: **Управляющий (`manager`) > Администратор (`admin`)**.
/// The backend RBAC is set-based `@Roles(...)`, not linear; the frontend used
/// to fold `admin` into the manager permission set (`isManagerOrAdmin`), which
/// over-privileged Администратор (bug A1). This module restricts Администратор
/// to Чат/Расписание/Клиенты while keeping the superuser `system_admin`
/// (Администратор системы) on the full set.
///
/// Canonical (non-teacher) tab index meaning:
///   0 Чат · 1 Обзор · 2 Расписание · 3 Клиенты ·
///   4 Пользователи · 5 Финансы · 6 Задачи · 7 Отчёты.
/// Teacher reuses 0/1/2 for Чат/Расписание/Ученики.
library;

/// Manager-only CRM tab indices — visible to Управляющий + Администратор
/// системы, never to Администратор.
const List<int> kManagerOnlyCrmTabs = [1, 4, 5, 6, 7];

/// Whether [role] has manager-tier access: the manager-only destinations
/// (Обзор/Пользователи/Финансы/Задачи/Отчёты) and role editing. Администратор
/// (`admin`) is excluded; the superuser `system_admin` is included.
bool crmHasManagerAccess(String role) =>
    role == 'manager' || role == 'system_admin';

/// Canonical CRM tab indices visible to [role], in display order.
List<int> crmVisibleTabs(String role, {required bool isDesktop}) {
  if (role == 'teacher') return const [0, 1, 2];
  if (role == 'admin') return const [0, 2, 3]; // A1: Чат/Расписание/Клиенты
  // Управляющий + Администратор системы: full set (Финансы/Задачи/Отчёты are
  // desktop-only, preserved from the legacy behaviour).
  return isDesktop ? const [0, 1, 2, 3, 4, 5, 6, 7] : const [0, 1, 2, 3, 4];
}
