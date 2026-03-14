import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/widgets/updater_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import '../widgets/manager_overview_widget.dart';
import '../widgets/tasks_widget.dart';
import '../widgets/leads_widget.dart';
import '../widgets/finance_widget.dart';
import '../widgets/reports_widget.dart';
import '../widgets/debtors_widget.dart';

class ManagerDashboardScreen extends ConsumerStatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  ConsumerState<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends ConsumerState<ManagerDashboardScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdaterDialog.checkAndShow(context, ref).catchError((e) {
        debugPrint('ManagerDashboard Updater error: $e');
      });
    });
  }

  final List<Widget> _tabs = [
    const ManagerOverviewWidget(),
    const TasksWidget(),
    const LeadsWidget(),
    const FinanceWidget(),
    const DebtorsWidget(),
    const ReportsWidget(),
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
          BottomNavigationBarItem(icon: Icon(Icons.money_off_rounded), label: 'Долги'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Отчёты'),
        ],
      ),
    );
  }
}
