import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class ReportsWidget extends StatefulWidget {
  const ReportsWidget({super.key});

  @override
  State<ReportsWidget> createState() => _ReportsWidgetState();
}

class _ReportsWidgetState extends State<ReportsWidget> {
  final _supabase = Supabase.instance.client;
  List<_MonthData> _monthlyData = [];
  bool _loading = true;
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);

      final [lessons, payments, students] = await Future.wait([
        _supabase
            .from('lessons')
            .select('scheduled_at, status')
            .gte('scheduled_at', sixMonthsAgo.toIso8601String()),
        _supabase
            .from('payments')
            .select('created_at, amount')
            .gte('created_at', sixMonthsAgo.toIso8601String()),
        _supabase
            .from('students')
            .select('created_at')
            .gte('created_at', sixMonthsAgo.toIso8601String()),
      ]);

      // Group by month
      final Map<String, _MonthData> byMonth = {};
      for (int i = 5; i >= 0; i--) {
        final m = DateTime(now.year, now.month - i, 1);
        final key = DateFormat('MMM', 'ru').format(m);
        byMonth[key] = _MonthData(month: key);
      }

      for (final l in lessons) {
        final dt = DateTime.tryParse(l['scheduled_at'] ?? '');
        if (dt == null) continue;
        final key = DateFormat('MMM', 'ru').format(dt);
        if (byMonth.containsKey(key)) {
          byMonth[key]!.lessons++;
          if (l['status'] == 'completed') byMonth[key]!.completed++;
        }
      }

      for (final p in payments) {
        final dt = DateTime.tryParse(p['created_at'] ?? '');
        if (dt == null) continue;
        final key = DateFormat('MMM', 'ru').format(dt);
        if (byMonth.containsKey(key)) {
          byMonth[key]!.revenue += double.tryParse(p['amount'].toString()) ?? 0;
        }
      }

      for (final s in students) {
        final dt = DateTime.tryParse(s['created_at'] ?? '');
        if (dt == null) continue;
        final key = DateFormat('MMM', 'ru').format(dt);
        if (byMonth.containsKey(key)) byMonth[key]!.newStudents++;
      }

      final monthList = byMonth.values.toList();
      final totalLessons = monthList.fold<int>(0, (s, m) => s + m.lessons);
      final totalCompleted = monthList.fold<int>(0, (s, m) => s + m.completed);
      final totalRevenue = monthList.fold<double>(0, (s, m) => s + m.revenue);
      final attendanceRate = totalLessons > 0 ? (totalCompleted / totalLessons * 100) : 0.0;

      setState(() {
        _monthlyData = monthList;
        _summary = {
          'attendance': attendanceRate,
          'revenue': totalRevenue,
          'total_lessons': totalLessons,
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
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));
    }

    final fmt = NumberFormat('#,##0', 'ru');
    final maxRevenue = _monthlyData.isEmpty ? 1.0 : _monthlyData.map((m) => m.revenue).reduce((a, b) => a > b ? a : b);
    final maxLessons = _monthlyData.isEmpty ? 1 : _monthlyData.map((m) => m.lessons).reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      color: AppTheme.primaryPurple,
      onRefresh: _loadReports,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Отчёты', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('За последние 6 месяцев', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),

            // KPI Row
            Row(
              children: [
                Expanded(child: _KpiCard(
                  label: 'Посещаемость',
                  value: '${(_summary['attendance'] as double? ?? 0).toStringAsFixed(1)}%',
                  icon: Icons.trending_up_rounded,
                  color: AppTheme.success,
                )),
                const SizedBox(width: 10),
                Expanded(child: _KpiCard(
                  label: 'Выручка',
                  value: '${fmt.format(_summary['revenue'] ?? 0)} ₽',
                  icon: Icons.payments_rounded,
                  color: AppTheme.secondaryGold,
                )),
                const SizedBox(width: 10),
                Expanded(child: _KpiCard(
                  label: 'Занятий',
                  value: '${_summary['total_lessons'] ?? 0}',
                  icon: Icons.calendar_month_rounded,
                  color: AppTheme.primaryPurple,
                )),
              ],
            ),
            const SizedBox(height: 24),

            // Lessons Chart
            const Text('Занятия по месяцам', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _monthlyData.map((m) {
                  final ratio = maxLessons > 0 ? m.lessons / maxLessons : 0.0;
                  final completedRatio = m.lessons > 0 ? m.completed / m.lessons : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${m.lessons}', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Container(
                                width: double.infinity,
                                height: 120 * ratio,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryPurple.withAlpha(40),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              Container(
                                width: double.infinity,
                                height: 120 * ratio * completedRatio,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryPurple,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(m.month, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(width: 10, height: 10, color: AppTheme.primaryPurple),
                const SizedBox(width: 6),
                const Text('Завершено', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                const SizedBox(width: 16),
                Container(width: 10, height: 10, color: AppTheme.primaryPurple.withAlpha(40)),
                const SizedBox(width: 6),
                const Text('Всего запланировано', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 24),

            // Revenue Chart
            const Text('Выручка по месяцам', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _monthlyData.map((m) {
                  final ratio = maxRevenue > 0 ? m.revenue / maxRevenue : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (m.revenue > 0)
                            Text(
                              m.revenue >= 1000 ? '${(m.revenue / 1000).toStringAsFixed(0)}к' : '${m.revenue.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary),
                            ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            height: 100 * ratio,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(m.month, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Monthly table
            const Text('Детализация', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._monthlyData.reversed.map((m) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(m.month, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    _SmallStat(label: 'занятий', value: '${m.lessons}', color: AppTheme.primaryPurple),
                    const SizedBox(width: 16),
                    _SmallStat(label: 'новых', value: '${m.newStudents}', color: AppTheme.success),
                    const SizedBox(width: 16),
                    _SmallStat(label: 'выручка', value: '${fmt.format(m.revenue)} ₽', color: AppTheme.secondaryGold),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _MonthData {
  final String month;
  int lessons = 0;
  int completed = 0;
  int newStudents = 0;
  double revenue = 0;
  _MonthData({required this.month});
}

class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _KpiCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SmallStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
      ],
    );
  }
}
