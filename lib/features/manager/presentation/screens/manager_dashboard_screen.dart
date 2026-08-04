import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart'
    show EntityLink;
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';

class ManagerDashboardScreen extends StatelessWidget {
  const ManagerDashboardScreen({super.key, this.initialLink});

  final EntityLink? initialLink;

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => ProductionWorkspaceHost(
        snapshot: snapshot,
        initialLink: initialLink,
        tabBuilder: (_, tab) {
          final route = tab.currentRoute;
          final client = buildClientWorkspaceSurface(
            snapshot: snapshot,
            route: route,
            tabId: tab.tabId,
          );
          if (client != null) return client;
          return MessengerScreen(
            key: ValueKey(
              'workspace-${tab.tabId}-${route.link.rawEntityType}-'
              '${route.link.entityId}',
            ),
            role: snapshot.role,
            initialLink: route.link,
            initialViewState: route.viewState,
          );
        },
      ),
    );
  }
}
