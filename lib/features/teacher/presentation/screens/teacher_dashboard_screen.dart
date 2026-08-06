import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart'
    show EntityLink;
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/features/crm/presentation/workspace_entity_surface.dart';

class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key, this.initialLink});

  final EntityLink? initialLink;

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => ProductionWorkspaceHost(
        snapshot: snapshot,
        initialLink: initialLink,
        tabBuilder: (_, tab) {
          final route = tab.currentRoute;
          final surface = buildStaffWorkspaceSurface(
            snapshot: snapshot,
            route: route,
            tabId: tab.tabId,
          );
          if (surface != null) return surface;
          return MessengerScreen(
            key: ValueKey(
              'workspace-${tab.tabId}-${route.link.rawEntityType}-'
              '${route.link.entityId}',
            ),
            role: snapshot.role,
            initialLink: route.link,
            initialViewState: route.viewState,
            workspaceOwned: true,
          );
        },
      ),
    );
  }
}
