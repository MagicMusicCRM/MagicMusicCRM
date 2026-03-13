import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/admin_overview_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/custom_field_config_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/mass_notification_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/leads_widget.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    AdminOverviewWidget(),
    ManageEntitiesWidget(),
    LeadsWidget(),
    CustomFieldConfigWidget(),
    MassNotificationWidget(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primaryPurple, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Администратор'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Выйти',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Обзор'),
          BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'Управление'),
          BottomNavigationBarItem(icon: Icon(Icons.view_kanban_rounded), label: 'Лиды'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Настройки'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_rounded), label: 'Рассылка'),
        ],
      ),
    );
  }
}
