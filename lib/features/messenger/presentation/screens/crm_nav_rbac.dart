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
///   4 Пользователи · 5 Финансы (legacy deep link) · 6 Задачи ·
///   7 Аналитика · 8 Настройки CRM.
/// Teacher reuses 0/1/2 for Чат/Расписание/Ученики.
///
/// The numbers are CANONICAL (alert_policy.dart's CrmSection and the unseen
/// counters key off them) — per-role lists may omit or reorder them, but never
/// renumber. V6 limits Administrator to Chat, Schedule and Clients; Tasks and
/// management surfaces start at Manager.
library;

import 'package:magic_music_crm/core/security/capability_snapshot.dart';

/// Operational CRM tab indices shared by admin/manager/director/system_admin.
const List<int> kManagerOnlyCrmTabs = [1, 4, 6, 7];

/// Whether [role] has access to operational CRM destinations.
bool crmHasManagerAccess(String role) =>
    role == 'admin' ||
    role == 'manager' ||
    role == 'director' ||
    role == 'system_admin';

/// KVA-239: ОБЩЕ-СУММАРНЫЕ финансы и финансовая аналитика (раздел «Финансы»,
/// отчёт по выручке, расходы, помесячные финансы) — только Директор и
/// Администратор системы. Управляющий/Администратор исключены; финансы в
/// КАРТОЧКАХ клиентов (история оплат, баланс, личный счёт) у них остаются.
bool crmHasSchoolFinanceAccess(String role) =>
    role == 'director' || role == 'system_admin';

/// Per-client finance is narrower than ordinary CRM access but intentionally
/// wider than school-wide finance: front-desk Admin and Manager may use it only
/// inside a client card. Client self-view uses a separate `/crm/me/commerce`
/// surface; Teacher never receives commerce data.
bool crmHasClientCardFinanceAccess(String role) =>
    role == 'admin' ||
    role == 'manager' ||
    role == 'director' ||
    role == 'system_admin';

/// Active commercial templates are needed by every role that can issue a
/// subscription. Catalog lifecycle changes remain a Director/root concern.
bool crmCanReadSubscriptionPackages(String role) =>
    role == 'admin' ||
    role == 'manager' ||
    role == 'director' ||
    role == 'system_admin';

bool crmCanManageSubscriptionPackages(String role) =>
    role == 'director' || role == 'system_admin';

/// ПОРАЗРЕЗНЫЕ финансы: ставка педагога за занятие, зарплатный раздел, отчёт
/// «Статистика преподавателей».
///
/// ✔ Решение владельца 16.07.2026 — «ставки педагога и иная подобная НЕ
/// обще-суммарная фин. информация» доступна Администратору и Управляющему.
/// Зеркалит серверный CrmPolicy.canReadTeacherRates; шире, чем
/// [crmHasSchoolFinanceAccess], но у́же операционного доступа: педагог и клиент
/// ставок не видят.
bool crmHasTeacherRatesAccess(String role) => crmHasManagerAccess(role);

/// Canonical CRM tab indices visible to [role], in display order.
List<int> crmVisibleTabs(String role, {required bool isDesktop}) {
  if (role == 'client') return const [];
  if (role == 'teacher') return const [0, 1, 2];
  if (role == 'admin') return const [0, 2, 3];
  // School-wide finance/reports remain desktop-only. Tasks are operational
  // work, however, so manager-tier roles must be able to open them on a phone
  // too (directly from Overview or through the nav shell's «Ещё» menu).
  if (!isDesktop) return const [0, 1, 2, 3, 4, 6];
  return const [0, 1, 2, 3, 4, 6, 7];
}

/// Server-sourced destination matrix used by the live shell. Role-based
/// helpers above remain only as compatibility utilities for older widgets.
List<int> crmVisibleTabsForCapabilities(
  CapabilitySnapshot snapshot, {
  required bool isDesktop,
}) {
  final assignedReadOnly =
      snapshot.scopes['schedule'] == 'assigned' &&
      snapshot.allows('schedule.lesson.read.assigned') &&
      !snapshot.allows('schedule.lesson.write');
  if (assignedReadOnly) return const [0, 1, 2];

  // Role is a deny ceiling; capabilities decide which allowed front-desk
  // destinations are mounted.
  if (snapshot.role == 'admin') {
    return [
      0,
      if (snapshot.allows('schedule.lesson.read.assigned')) 2,
      if (snapshot.allows('crm.client.read.basic')) 3,
    ];
  }

  final tabs = <int>[0];
  final canReadOverview =
      snapshot.allows('report.status.read') ||
      snapshot.allows('system.settings.manage');
  final canReadTasks = snapshot.allows('workflow.task.read');
  if (canReadOverview) {
    tabs.add(1);
  } else if (canReadTasks) {
    // Front-desk users start from their work queue instead of management
    // overview; the order is still derived from effective capabilities.
    tabs.add(6);
  }
  if (snapshot.allows('schedule.lesson.read.assigned')) tabs.add(2);
  if (snapshot.allows('crm.client.read.basic')) tabs.add(3);
  if (snapshot.allows('system.settings.manage')) tabs.add(4);
  if (canReadTasks && !tabs.contains(6)) tabs.add(6);
  if (isDesktop && snapshot.allows('report.status.read')) tabs.add(7);
  if (snapshot.role != 'admin' && snapshot.allows('config.crm.read')) {
    tabs.add(8);
  }
  return tabs;
}

/// Resolves a canonical navigation request without ever crossing the role's
/// visible-tab boundary. Hidden desktop-only targets on a phone keep the
/// current tab; stale current state falls back to the first visible tab.
int crmResolveVisibleTab({
  required List<int> visibleTabs,
  required int requestedTab,
  required int currentTab,
}) {
  if (visibleTabs.isEmpty) {
    throw ArgumentError.value(visibleTabs, 'visibleTabs', 'must not be empty');
  }
  if (visibleTabs.contains(requestedTab)) return requestedTab;
  // v7 unified Finance and Reports under Analytics. Keep old tab-5 links
  // useful without exposing a duplicate top-level destination.
  if (requestedTab == 5 && visibleTabs.contains(7)) return 7;
  if (visibleTabs.contains(currentTab)) return currentTab;
  return visibleTabs.first;
}
