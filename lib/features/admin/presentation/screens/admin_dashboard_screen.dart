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
    // route here. Pass the REAL role so the messenger can enforce the A1
    // hierarchy — Администратор is restricted to Чат/Расписание/Клиенты, while
    // the superuser Администратор системы keeps full access. The gate status is
    // already loaded by the router before this screen renders; default to the
    // less-privileged `admin` if it is somehow unavailable.
    final role = ref.watch(releaseGateStatusProvider).asData?.value.role;
    final messengerRole = role == 'system_admin' ? 'system_admin' : 'admin';
    return MessengerScreen(role: messengerRole);
  }
}
