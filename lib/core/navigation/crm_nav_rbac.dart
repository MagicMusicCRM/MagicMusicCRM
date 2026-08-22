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
///   4 Пользователи (legacy deep link) · 5 Финансы (legacy deep link) ·
///   6 Задачи · 7 Аналитика · 8 Настройки системы.
/// Teacher reuses 0/1/2 for Чат/Расписание/Ученики.
///
/// The numbers are CANONICAL (alert_policy.dart's CrmSection and the unseen
/// counters key off them) — per-role lists may omit or reorder them, but never
/// renumber. Administrator also sees the branch-scoped task board; management
/// overview, analytics and settings still start at Manager.
library;

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/navigation/responsive_navigation_shell.dart';

/// Operational CRM tab indices shared by admin/manager/director/system_admin.
const List<int> kManagerOnlyCrmTabs = [1, 7, 8];

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
  if (role == 'admin') return const [0, 2, 3, 6];
  // The compact shell keeps secondary destinations in «Ещё»; Analytics must
  // remain reachable because Overview KPI cards deep-link into it.
  if (!isDesktop) return const [0, 1, 2, 3, 6, 7, 8];
  return const [0, 1, 2, 3, 6, 7, 8];
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
      if (snapshot.allows('workflow.task.read')) 6,
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
  if (canReadTasks && !tabs.contains(6)) tabs.add(6);
  if (snapshot.allows('report.status.read')) tabs.add(7);
  if (snapshot.role != 'admin' &&
      (snapshot.allows('system.settings.manage') ||
          snapshot.allows('config.crm.read'))) {
    tabs.add(8);
  }
  return tabs;
}

ResponsiveNavDestination crmDestinationForTab(
  String role,
  int tab, {
  int badgeCount = 0,
}) {
  if (role == 'teacher') {
    if (tab == 1) {
      return const ResponsiveNavDestination(
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today_rounded,
        label: 'Расписание',
      );
    }
    if (tab == 2) {
      return const ResponsiveNavDestination(
        icon: Icons.school_outlined,
        selectedIcon: Icons.school_rounded,
        label: 'Ученики',
      );
    }
  }
  return switch (tab) {
    1 => const ResponsiveNavDestination(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      label: 'Обзор',
    ),
    2 => ResponsiveNavDestination(
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today_rounded,
      label: 'Расписание',
      badgeCount: badgeCount,
    ),
    3 => ResponsiveNavDestination(
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
      label: 'Клиенты',
      badgeCount: badgeCount,
    ),
    5 => ResponsiveNavDestination(
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
      label: 'Финансы',
      badgeCount: badgeCount,
    ),
    6 => ResponsiveNavDestination(
      icon: Icons.task_alt_outlined,
      selectedIcon: Icons.task_alt_rounded,
      label: 'Задачи',
      badgeCount: badgeCount,
    ),
    7 => const ResponsiveNavDestination(
      icon: Icons.insert_chart_outlined_rounded,
      selectedIcon: Icons.insert_chart_rounded,
      label: 'Аналитика',
    ),
    8 => const ResponsiveNavDestination(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
      label: 'Настройки',
    ),
    _ => const ResponsiveNavDestination(
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
      label: 'Чат',
    ),
  };
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
  if (requestedTab == 4 && visibleTabs.contains(8)) return 8;
  if (visibleTabs.contains(currentTab)) return currentTab;
  return visibleTabs.first;
}

String crmSectionForTab(String role, int tab) => role == 'teacher'
    ? switch (tab) {
        1 => 'schedule',
        2 => 'clients',
        _ => 'chat',
      }
    : switch (tab) {
        1 => 'overview',
        2 => 'schedule',
        3 => 'clients',
        5 => 'finance',
        6 => 'tasks',
        7 => 'reports',
        8 => 'configuration',
        _ => 'chat',
      };
