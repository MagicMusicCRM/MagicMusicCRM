import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();

  }

  @override
  Widget build(BuildContext context) {
    // Both `admin` (Администратор) and `system_admin` (Администратор системы)
    // route here. Pass the real role so the shared CRM shell can keep role
    // editing stricter than operational CRM work.
    final role = ref.watch(releaseGateStatusProvider).asData?.value.role;
    final messengerRole = role == 'system_admin' ? 'system_admin' : 'admin';
    return MessengerScreen(role: messengerRole);
  }
}
