import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

class ManagerDashboardScreen extends ConsumerStatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  ConsumerState<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends ConsumerState<ManagerDashboardScreen> {
  @override
  void initState() {
    super.initState();

  }

  @override
  Widget build(BuildContext context) {
    // KVA-239: и Управляющий (manager), и Директор (director) используют эту
    // оболочку; передаём реальную роль, чтобы гейтинг общешкольных финансов
    // работал по роли.
    final role = ref.watch(releaseGateStatusProvider).asData?.value.role;
    return MessengerScreen(role: role == 'director' ? 'director' : 'manager');
  }
}
