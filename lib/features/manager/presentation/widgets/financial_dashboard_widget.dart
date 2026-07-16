import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/widgets/dashboard_legend_item.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';

class FinancialDashboardWidget extends ConsumerStatefulWidget {
  const FinancialDashboardWidget({super.key});

  @override
  ConsumerState<FinancialDashboardWidget> createState() =>
      _FinancialDashboardWidgetState();
}

class _FinancialDashboardWidgetState
    extends ConsumerState<FinancialDashboardWidget> {
  bool _loading = true;
  Object? _loadError;
  List<_MonthlyFinancials> _chartData = [];
  List<Map<String, dynamic>> _teacherEfficiency = [];
  Map<String, int> _roomLoad = {};

  /// Selected reporting window. Defaults to the last 6 months → «сейчас»;
  /// the calendar lets the manager pick an arbitrary range over the archive.
  late DateTimeRange _range;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month - 5, 1),
      end: now,
    );
    _loadData();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final report = await ref
          .read(magicCrmServiceProvider)
          .getFinanceReport(
            from: _range.start.toUtc().toIso8601String(),
            to: _range.end
                .add(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
          );
      final chartData = (report['monthly'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_MonthlyFinancials.fromReport)
          .toList();
      final teachers =
          (report['teachers'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(
                (row) => {
                  'name': row['name'] ?? 'Без имени',
                  'completed': int.tryParse('${row['completed'] ?? 0}') ?? 0,
                  'revenue': double.tryParse('${row['revenue'] ?? 0}') ?? 0.0,
                },
              )
              .toList()
            ..sort(
              (a, b) =>
                  (b['revenue'] as double).compareTo(a['revenue'] as double),
            );
      final roomLoad = {
        for (final row
            in (report['rooms'] as List? ?? const [])
                .whereType<Map<String, dynamic>>())
          row['name']?.toString() ?? 'Без аудитории':
              int.tryParse('${row['lessons'] ?? 0}') ?? 0,
      };

      setState(() {
        _chartData = chartData;
        _teacherEfficiency = teachers;
        _roomLoad = roomLoad;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      );
    }

    // A failed load must not masquerade as «школа ничего не заработала» —
    // show an explicit error with retry instead of empty charts.
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppTheme.danger,
                size: 42,
              ),
              const SizedBox(height: 10),
              Text(
                'Не удалось загрузить аналитику',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '$_loadError',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _loadData,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            // Keep the dashboard readable and balanced instead of stretching
            // every card across the whole desktop width.
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRangeBar(),
                  const SizedBox(height: 12),
                  _buildRevenueExpensesChart(),
                  const SizedBox(height: 16),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildTeacherEfficiencyCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildRoomLoadCard()),
                      ],
                    )
                  else ...[
                    _buildTeacherEfficiencyCard(),
                    const SizedBox(height: 16),
                    _buildRoomLoadCard(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRangeBar() {
    final fmt = DateFormat('d MMM yyyy', 'ru');
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${fmt.format(_range.start)} — ${fmt.format(_range.end)}',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.calendar_today_rounded, size: 18),
          label: const Text('Период'),
        ),
      ],
    );
  }

  Widget _buildRevenueExpensesChart() {
    final maxY = _chartData.isEmpty
        ? 1.0
        : _chartData
                  .map((m) => m.revenue > m.expenses ? m.revenue : m.expenses)
                  .reduce((a, b) => a > b ? a : b) *
              1.2;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Прибыльность',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SizedBox(
              // Fixed, comfortable chart height — prevents the panel from
              // ballooning to full-screen height on wide desktop windows.
              height: 260,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY <= 0 ? 1 : maxY,
                  barGroups: _chartData.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.revenue,
                          color: AppTheme.success,
                          width: 12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: e.value.expenses,
                          color: AppTheme.danger,
                          width: 12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) => Text(
                          _chartData[val.toInt()].month,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
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
                DashboardLegendItem(color: AppTheme.success, label: 'Доход'),
                const SizedBox(width: 20),
                DashboardLegendItem(color: AppTheme.danger, label: 'Расход'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherEfficiencyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Эффективность преподавателей',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
                          Text(
                            t['name'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${t['completed']} зан. за период',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Money intentionally dropped here (E2) — teacher load is
                    // shown as the number of completed lessons for the period.
                    Text(
                      '${t['completed']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryGold,
                      ),
                    ),
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
    final sortedRooms = _roomLoad.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxLoad = sortedRooms.isNotEmpty ? sortedRooms.first.value : 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Загрузка аудиторий (количество занятий)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...sortedRooms.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key, style: const TextStyle(fontSize: 13)),
                        Text(
                          '${e.value}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: e.value / maxLoad,
                        minHeight: 8,
                        backgroundColor: Colors.white10,
                        color: AppTheme.primaryGold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

  factory _MonthlyFinancials.fromReport(Map<String, dynamic> row) {
    final parsed = DateTime.tryParse(row['month_start']?.toString() ?? '');
    return _MonthlyFinancials(
        month: parsed == null ? '—' : DateFormat('MM.yy').format(parsed),
      )
      ..revenue = double.tryParse('${row['revenue'] ?? 0}') ?? 0
      ..expenses = double.tryParse('${row['expenses'] ?? 0}') ?? 0;
  }
}

