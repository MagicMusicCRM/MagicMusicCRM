import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/widgets/updater_dialog.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends ConsumerState<TeacherDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdaterDialog.checkAndShow(context, ref).catchError((e) {
        debugPrint('TeacherDashboard Updater error: $e');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MessengerScreen(role: 'teacher');
  }
}
