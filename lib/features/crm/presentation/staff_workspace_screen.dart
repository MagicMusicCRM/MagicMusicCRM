import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';
import 'package:magic_music_crm/core/services/alert_policy.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/admin_overview_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/workspace_entity_surface.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/shared_tasks_v4_panel.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';

class StaffWorkspaceScreen extends StatelessWidget {
  const StaffWorkspaceScreen({super.key, this.initialLink});

  final EntityLink? initialLink;

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => ProductionWorkspaceHost(
        snapshot: snapshot,
        initialLink: initialLink,
        tabBuilder: (_, tab) => StaffWorkspaceContent(
          key: ValueKey('staff-workspace-${tab.tabId}'),
          snapshot: snapshot,
          tab: tab,
        ),
      ),
    );
  }
}

class StaffWorkspaceContent extends StatefulWidget {
  const StaffWorkspaceContent({
    required this.snapshot,
    required this.tab,
    super.key,
  });

  final CapabilitySnapshot snapshot;
  final WorkspaceTabState tab;

  @override
  State<StaffWorkspaceContent> createState() => _StaffWorkspaceContentState();
}

class _StaffWorkspaceContentState extends State<StaffWorkspaceContent> {
  int _selectedReportsTab = 0;

  bool get _isAdminRole =>
      widget.snapshot.role == 'admin' || widget.snapshot.role == 'system_admin';

  @override
  Widget build(BuildContext context) {
    final route = widget.tab.currentRoute;
    final entitySurface = buildStaffWorkspaceSurface(
      snapshot: widget.snapshot,
      route: route,
      tabId: widget.tab.tabId,
    );
    if (entitySurface != null) return entitySurface;

    final workspace = WorkspaceNavigationScope.maybeOf(context);
    final isDesktop =
        workspace?.isDesktop ?? MediaQuery.sizeOf(context).width >= 840;
    final visibleTabs = crmVisibleTabsForCapabilities(
      widget.snapshot,
      isDesktop: isDesktop,
    );
    final requestedTab =
        crmTabForEntityLink(route.link, widget.snapshot.role) ??
        visibleTabs.first;
    final selectedTab = crmResolveVisibleTab(
      visibleTabs: visibleTabs,
      requestedTab: requestedTab,
      currentTab: visibleTabs.first,
    );

    if (selectedTab == CrmSection.chat) {
      return MessengerScreen(
        key: ValueKey(
          'workspace-messenger-${widget.tab.tabId}-'
          '${route.link.rawEntityType}-${route.link.entityId}',
        ),
        role: widget.snapshot.role,
        initialLink: route.link,
        initialViewState: route.viewState,
        workspaceOwned: true,
      );
    }

    if (widget.snapshot.role == 'teacher') {
      return switch (selectedTab) {
        1 => const TeacherScheduleWidget(),
        2 => const TeacherStudentsWidget(),
        _ => _messenger(route.link),
      };
    }

    return switch (selectedTab) {
      1
          when widget.snapshot.allows('report.status.read') ||
              widget.snapshot.allows('system.settings.manage') =>
        _isAdminRole
            ? AdminOverviewWidget(
                onTabChange: (index, subIndex) =>
                    _handleOverviewTabChange(index, subIndex, isDesktop),
              )
            : ManagerOverviewWidget(
                role: widget.snapshot.role,
                onTabChange: (index, subIndex) =>
                    _handleOverviewTabChange(index, subIndex, isDesktop),
              ),
      2 when widget.snapshot.allows('schedule.lesson.read.assigned') =>
        ScheduleWidget(
          initialLink: route.link,
          initialViewState: route.viewState,
          canWrite: widget.snapshot.allows('schedule.lesson.write'),
        ),
      3 when widget.snapshot.allows('crm.client.read.basic') =>
        const ClientsWidget(),
      5
          when isDesktop &&
              widget.snapshot.allows('commerce.school_finance.read') =>
        const FinanceWidget(),
      6 when widget.snapshot.allows('workflow.task.read') => SharedTasksV4Panel(
        initialLink: route.link,
        canWrite: widget.snapshot.allows('workflow.task.write'),
        defaultToMineToday: widget.snapshot.role == 'admin',
      ),
      7 when widget.snapshot.allows('report.status.read') => ReportsWidget(
        role: widget.snapshot.role,
        initialTab: _selectedReportsTab,
        initialLink: route.link,
        initialViewState: route.viewState,
        accessSnapshot: widget.snapshot,
      ),
      8
          when widget.snapshot.allows('system.settings.manage') ||
              widget.snapshot.allows('config.crm.read') =>
        SystemSettingsWorkspace(
          role: widget.snapshot.role,
          initialArea: route.link.entityType == EntityLinkType.user
              ? 'users'
              : route.link.optionalFocus?.focus == 'users'
              ? 'users'
              : route.link.rawEntityType == 'configuration'
              ? 'crm'
              : null,
          initialUserSearch: route.link.optionalFocus?.filter['query']
              ?.toString(),
        ),
      _ => _messenger(route.link),
    };
  }

  Widget _messenger(EntityLink link) {
    return MessengerScreen(
      key: ValueKey(
        'workspace-messenger-${widget.tab.tabId}-'
        '${link.rawEntityType}-${link.entityId}',
      ),
      role: widget.snapshot.role,
      initialLink: link,
      initialViewState: widget.tab.currentRoute.viewState,
      workspaceOwned: true,
    );
  }

  void _handleOverviewTabChange(int index, int? subIndex, bool isDesktop) {
    final targetTab = _overviewTargetTab(index, subIndex);
    final reportsTab = index == 5 ? 1 : subIndex;
    final visibleTabs = crmVisibleTabsForCapabilities(
      widget.snapshot,
      isDesktop: isDesktop,
    );
    final currentTab =
        crmTabForEntityLink(
          widget.tab.currentRoute.link,
          widget.snapshot.role,
        ) ??
        visibleTabs.first;
    final resolvedTab = crmResolveVisibleTab(
      visibleTabs: visibleTabs,
      requestedTab: targetTab,
      currentTab: currentTab,
    );
    if (targetTab == 7 && reportsTab != null) {
      setState(() => _selectedReportsTab = reportsTab.clamp(0, 5));
    }
    _selectSection(resolvedTab);
  }

  void _selectSection(int tab) {
    final workspace = WorkspaceNavigationScope.maybeOf(context);
    if (workspace == null) return;
    final link = EntityRouteRegistry.sectionRootLink(
      crmSectionForTab(widget.snapshot.role, tab),
    );
    workspace.controller.replaceCurrentLink(widget.tab.tabId, link);
  }

  static int _overviewTargetTab(int index, int? subIndex) {
    if (index == 5) return 7;
    if (index == 1 && subIndex != null) {
      if (subIndex == 3 || subIndex == 4) return 2;
      return 8;
    }
    return index;
  }
}
