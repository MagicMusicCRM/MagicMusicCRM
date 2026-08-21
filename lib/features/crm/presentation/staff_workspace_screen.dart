import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_primary_destination.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_secondary_destination.dart';
import 'package:magic_music_crm/features/crm/presentation/workspace_entity_surface.dart';

class StaffWorkspaceScreen extends StatelessWidget {
  const StaffWorkspaceScreen({super.key, this.initialLink});

  final EntityLink? initialLink;

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => ProductionWorkspaceHost(
        snapshot: snapshot,
        initialLink: initialLink,
        tabBuilder: (_, tab) => _StaffWorkspaceContent(
          key: ValueKey('staff-workspace-${tab.tabId}'),
          snapshot: snapshot,
          tab: tab,
        ),
      ),
    );
  }
}

class _StaffWorkspaceContent extends StatefulWidget {
  const _StaffWorkspaceContent({
    required this.snapshot,
    required this.tab,
    super.key,
  });

  final CapabilitySnapshot snapshot;
  final WorkspaceTabState tab;

  @override
  State<_StaffWorkspaceContent> createState() => _StaffWorkspaceContentState();
}

class _StaffWorkspaceContentState extends State<_StaffWorkspaceContent> {
  int _selectedReportsTab = 0;

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

    final primaryDestination = buildStaffWorkspacePrimaryDestination(
      selectedTab: selectedTab,
      snapshot: widget.snapshot,
      tab: widget.tab,
      isDesktop: isDesktop,
      onOverviewTabChange: (index, subIndex) =>
          _handleOverviewTabChange(index, subIndex, isDesktop),
    );
    if (primaryDestination != null) return primaryDestination;

    return buildStaffWorkspaceSecondaryDestination(
      selectedTab: selectedTab,
      snapshot: widget.snapshot,
      tab: widget.tab,
      selectedReportsTab: _selectedReportsTab,
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
