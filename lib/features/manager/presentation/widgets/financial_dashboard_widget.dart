import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';

class FinancialDashboardWidget extends StatefulWidget {
  const FinancialDashboardWidget({super.key});

  @override
  State<FinancialDashboardWidget> createState() => _FinancialDashboardWidgetState();
}

class _FinancialDashboardWidgetState extends State<FinancialDashboardWidget> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<_MonthlyFinancials> _chartData = [];
  List<Map<String, dynamic>> _teacherEfficiency = [];
  Map<String, int> _roomLoad = {};
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);

      final [payments, expenses, lessons, rooms] = await Future.wait([
        _supabase.from('payments').select('amount, created_at').gte('created_at', sixMonthsAgo.toIso8601String()),
        _supabase.from('expenses').select('amount, created_at').gte('created_at', sixMonthsAgo.toIso8601String()),
        _supabase.from('lessons').select('scheduled_at, status, teacher_id, room_id, teachers(profiles(first_name, last_name)), groups(price_per_lesson)').gte('scheduled_at', sixMonthsAgo.toIso8601String()),
        _supabase.from('rooms').select('id, name'),
      ]);

      // 1. Process Chart Data
      final Map<String, _MonthlyFinancials> byMonth = {};
      for (int i = 5; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        final key = DateFormat('MM.yy').format(date);
        byMonth[key] = _MonthlyFinancials(month: key);
      }

      for (var p in payments) {
        final dt = DateTime.tryParse(p['created_at'] ?? '');
        if (dt != null) {
          final key = DateFormat('MM.yy').format(dt);
          if (byMonth.containsKey(key)) byMonth[key]!.revenue += (p['amount'] as num).toDouble();
        }
      }

      for (var e in expenses) {
        final dt = DateTime.tryParse(e['created_at'] ?? '');
        if (dt != null) {
          final key = DateFormat('MM.yy').format(dt);
          if (byMonth.containsKey(key)) byMonth[key]!.expenses += (e['amount'] as num).toDouble();
        }
      }

      // 2. Teacher Efficiency & Room Load
      final Map<String, Map<String, dynamic>> tStats = {};
      final Map<String, int> rStats = {};
      final roomMap = {for (var r in rooms) r['id']: r['name']};

      for (var l in lessons) {
        // Teacher
        if (l['status'] == 'completed') {
          final tId = l['teacher_id'];
          if (tId != null) {
            tStats.putIfAbsent(tId, () => {
              'name': '${l['teachers']?['profiles']?['first_name'] ?? ''} ${l['teachers']?['profiles']?['last_name'] ?? ''}'.trim(),
              'completed': 0,
              'revenue': 0.0,
            });
            tStats[tId]!['completed']++;
            tStats[tId]!['revenue'] += (l['groups']?['price_per_lesson'] as num?)?.toDouble() ?? 0.0;
          }
        }

        // Room
        final rId = l['room_id'];
        if (rId != null) {
          final rName = roomMap[rId] ?? 'Unknown';
          rStats[rName] = (rStats[rName] ?? 0) + 1;
        }
      }

      setState(() {
        _chartData = byMonth.values.toList();
        _teacherEfficiency = tStats.values.toList()..sort((a, b) => b['revenue'].compareTo(a['revenue']));
        _roomLoad = rStats;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRevenueExpensesChart(),
          const SizedBox(height: 24),
          _buildTeacherEfficiencyCard(),
          const SizedBox(height: 24),
          _buildRoomLoadCard(),
        ],
      ),
    );
  }

  Widget _buildRevenueExpensesChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Прибыльность (6 мес)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 1.7,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _chartData.map((m) => m.revenue > m.expenses ? m.revenue : m.expenses).reduce((a, b) => a > b ? a : b) * 1.2,
                  barGroups: _chartData.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(toY: e.value.revenue, color: AppTheme.success, width: 12, borderRadius: BorderRadius.circular(4)),
                        BarChartRodData(toY: e.value.expenses, color: AppTheme.danger, width: 12, borderRadius: BorderRadius.circular(4)),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) => Text(_chartData[val.toInt()].month, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendItem(color: AppTheme.success, label: 'Доход'),
                const SizedBox(width: 20),
                _LegendItem(color: AppTheme.danger, label: 'Расход'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherEfficiencyCard() {
    final fmt = NumberFormat('#,##0', 'ru');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Эффективность преподавателей', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _teacherEfficiency.length,
              separatorBuilder: (_, _) => const Divider(height: 24),
              itemBuilder: (context, i) {
                final t = _teacherEfficiency[i];
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${t['completed']} зан.', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                    Text('${fmt.format(t['revenue'])} ₽', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.success)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomLoadCard() {
    final sortedRooms = _roomLoad.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxLoad = sortedRooms.isNotEmpty ? sortedRooms.first.value : 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Загрузка аудиторий (Lessons count)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...sortedRooms.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key, style: const TextStyle(fontSize: 13)),
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.value / maxLoad,
                      minHeight: 8,
                      backgroundColor: Colors.white10,
                      color: AppTheme.primaryPurple,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _MonthlyFinancials {
  final String month;
  double revenue = 0;
  double expenses = 0;
  _MonthlyFinancials({required this.month});
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}
