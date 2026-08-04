import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';

class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => ProductionWorkspaceHost(
        snapshot: snapshot,
        tabBuilder: (_, tab) {
          final route = tab.currentRoute;
          if (route.link.entityType == EntityLinkType.client) {
            return ClientCardRouteSurface(
              key: ValueKey('workspace-client-${tab.tabId}'),
              snapshot: snapshot,
              entityType: route.link.rawEntityType == 'lead'
                  ? 'lead'
                  : 'student',
              entityId: route.link.entityId,
              initialSection:
                  route.link.optionalFocus?.filter['section']?.toString() ??
                  'overview',
              viewState: route.viewState,
            );
          }
          return MessengerScreen(
            key: ValueKey(
              'workspace-${tab.tabId}-${route.link.rawEntityType}-'
              '${route.link.entityId}',
            ),
            role: snapshot.role,
            initialLink: route.link,
          );
        },
      ),
    );
  }
}
