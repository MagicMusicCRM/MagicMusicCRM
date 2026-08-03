import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key, this.initialLink});

  final EntityLink? initialLink;

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => ProductionWorkspaceHost(
        snapshot: snapshot,
        initialLink: initialLink,
        tabBuilder: (_, tab) => MessengerScreen(
          key: ValueKey(
            'workspace-${tab.tabId}-${tab.currentRoute.link.rawEntityType}-'
            '${tab.currentRoute.link.entityId}',
          ),
          role: snapshot.role,
          initialLink: tab.currentRoute.link,
        ),
      ),
    );
  }
}
