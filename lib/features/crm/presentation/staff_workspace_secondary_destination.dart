import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

Widget buildStaffWorkspaceSecondaryDestination({
  required int selectedTab,
  required CapabilitySnapshot snapshot,
  required WorkspaceTabState tab,
  required int selectedReportsTab,
}) {
  final route = tab.currentRoute;
  return switch (selectedTab) {
    4 when snapshot.allows('crm.client.read.basic') => PersonnelWorkspace(
      snapshot: snapshot,
      initialLink: route.link,
    ),
    6 when snapshot.allows('workflow.task.read') => SharedTasksPanel(
      initialLink: route.link,
      canWrite: snapshot.allows('workflow.task.write'),
      defaultToMineToday: snapshot.role == 'admin',
    ),
    7 when snapshot.allows('report.status.read') => ReportsWidget(
      role: snapshot.role,
      initialTab: selectedReportsTab,
      initialLink: route.link,
      initialViewState: route.viewState,
      accessSnapshot: snapshot,
    ),
    8
        when snapshot.allows('system.settings.manage') ||
            snapshot.allows('config.crm.read') =>
      SystemSettingsWorkspace(
        role: snapshot.role,
        initialArea: route.link.entityType == EntityLinkType.user
            ? 'users'
            : route.link.optionalFocus?.focus == 'users'
            ? 'users'
            : route.link.rawEntityType == 'configuration'
            ? route.link.optionalFocus?.focus == 'learning'
                  ? 'learning'
                  : 'crm'
            : null,
        initialTeacherId: route.link.optionalFocus?.filter['teacherId']
            ?.toString(),
        initialUserSearch: route.link.optionalFocus?.filter['query']
            ?.toString(),
      ),
    _ => MessengerScreen(
      key: ValueKey(
        'workspace-messenger-${tab.tabId}-'
        '${route.link.rawEntityType}-${route.link.entityId}',
      ),
      role: snapshot.role,
      initialLink: route.link,
      initialViewState: route.viewState,
      workspaceOwned: true,
    ),
  };
}
