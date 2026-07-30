import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CapabilityShellGate(
      builder: (_, snapshot) => MessengerScreen(role: snapshot.role),
    );
  }
}
