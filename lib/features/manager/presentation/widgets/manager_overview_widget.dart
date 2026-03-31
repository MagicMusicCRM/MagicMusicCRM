import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class ManagerOverviewWidget extends StatefulWidget {
  final Function(int index, int? subIndex)? onTabChange;
  const ManagerOverviewWidget({super.key, this.onTabChange});

  @override
  State<ManagerOverviewWidget> createState() => _ManagerOverviewWidgetState();
}

class _ManagerOverviewWidgetState extends State<ManagerOverviewWidget> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

      final studentsCount = (await _supabase.from('students').select('id') as List).length;
      final teachersCount = (await _supabase.from('teachers').select('id') as List).length;
      final lessonsCount = (await _supabase.from('lessons')
            .select('id')
            .gte('scheduled_at', monthStart)
            .eq('status', 'completed') as List).length;
      final tasksCount = (await _supabase.from('tasks')
            .select('id')
            .eq('status', 'todo') as List).length;
      final leadsCount = (await _supabase.from('leads')
            .select('id')
            .eq('status', 'new') as List).length;
      final paymentsResult = await _supabase.from('payments')
            .select('amount')
            .gte('created_at', monthStart);

      final payments = paymentsResult as List;
      final revenue = payments.fold<double>(0, (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0));

      setState(() {
        _stats = {
          'students': studentsCount,
          'teachers': teachersCount,
          'lessons_done': lessonsCount,
          'tasks_open': tasksCount,
          'leads_new': leadsCount,
          'revenue': revenue,
        };
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.secondaryGold));
    }

    String fmt(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}к ₽' : '${v.toStringAsFixed(0)} ₽';

    return RefreshIndicator(
      color: AppTheme.secondaryGold,
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Сводка', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Данные за текущий месяц', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            // Revenue highlight card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Выручка за месяц', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    fmt(_stats['revenue']?.toDouble() ?? 0),
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                GestureDetector(onTap: () => widget.onTabChange?.call(1, 0), child: _StatCard(icon: Icons.people_alt_rounded, label: 'Учеников', value: '${_stats['students'] ?? 0}', color: AppTheme.primaryPurple)),
                GestureDetector(onTap: () => widget.onTabChange?.call(1, 1), child: _StatCard(icon: Icons.school_rounded, label: 'Преподавателей', value: '${_stats['teachers'] ?? 0}', color: AppTheme.secondaryGold)),
                GestureDetector(onTap: () => widget.onTabChange?.call(1, 4), child: _StatCard(icon: Icons.check_circle_rounded, label: 'Занятий в месяц', value: '${_stats['lessons_done'] ?? 0}', color: AppTheme.success)),
                GestureDetector(onTap: () => widget.onTabChange?.call(2, null), child: _StatCard(icon: Icons.task_alt_rounded, label: 'Открытых задач', value: '${_stats['tasks_open'] ?? 0}', color: AppTheme.warning)),
                GestureDetector(onTap: () => widget.onTabChange?.call(3, null), child: _StatCard(icon: Icons.person_add_rounded, label: 'Новых лидов', value: '${_stats['leads_new'] ?? 0}', color: AppTheme.danger)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
                Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
