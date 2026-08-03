import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/core/workspace/production_workspace_host.dart';

class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => ProductionWorkspaceHost(
        snapshot: snapshot,
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
