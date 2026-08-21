import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart'
    show EntityLink;
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';

class ManagerDashboardScreen extends StatelessWidget {
  const ManagerDashboardScreen({super.key, this.initialLink});

  final EntityLink? initialLink;

  @override
  Widget build(BuildContext context) {
    return StaffWorkspaceScreen(initialLink: initialLink);
  }
}
