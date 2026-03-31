import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/widgets/updater_dialog.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdaterDialog.checkAndShow(context, ref).catchError((e) {
        debugPrint('ManagerDashboard Updater error: $e');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MessengerScreen(role: 'manager');
  }
}
