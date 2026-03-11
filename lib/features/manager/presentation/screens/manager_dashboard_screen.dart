import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import '../widgets/manager_overview_widget.dart';
import '../widgets/tasks_widget.dart';
import '../widgets/leads_widget.dart';
import '../widgets/finance_widget.dart';
import '../widgets/reports_widget.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    ManagerOverviewWidget(),
    TasksWidget(),
    LeadsWidget(),
    FinanceWidget(),
    ReportsWidget(),
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
                color: AppTheme.secondaryGold.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.business_center_rounded, color: AppTheme.secondaryGold, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('CRM — Управляющий'),
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
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Обзор'),
          BottomNavigationBarItem(icon: Icon(Icons.task_alt_rounded), label: 'Задачи'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline_rounded), label: 'Лиды'),
          BottomNavigationBarItem(icon: Icon(Icons.payments_rounded), label: 'Финансы'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Отчёты'),
        ],
      ),
    );
  }
}
