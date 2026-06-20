import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/analytics_providers.dart';

// ────────────────────────────────────────────────────────────
// Public entry-point
// ────────────────────────────────────────────────────────────

class ManagementDashboardWidget extends ConsumerWidget {
  const ManagementDashboardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              _FunnelSection(),
              SizedBox(height: 16),
              _DebtsSection(),
              SizedBox(height: 16),
              _ForecastSection(),
              SizedBox(height: 16),
              _BranchesSection(),
              SizedBox(height: 16),
              _ChurnSection(),
              SizedBox(height: 16),
              _SlaSection(),
              SizedBox(height: 16),
              _LossReasonsSection(),
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Shared helpers
// ────────────────────────────────────────────────────────────

double _toDouble(Object? v) => (v as num?)?.toDouble() ?? 0.0;
int _toInt(Object? v) => (v as num?)?.toInt() ?? 0;

String _fmtMoney(double v) =>
    '${NumberFormat('#,##0', 'ru').format(v.round())} ₽';

String _fmtCount(int v) => NumberFormat.decimalPattern('ru').format(v);

/// Minimal progress indicator used in loading states.
Widget _loadingWidget() => const Padding(
  padding: EdgeInsets.symmetric(vertical: 40),
  child: Center(
    child: CircularProgressIndicator(color: AppTheme.primaryPurple),
  ),
);

/// Inline error with retry callback.
Widget _errorWidget(Object error, VoidCallback onRetry) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 18),
        const SizedBox(width: 8),
        Text(
          'Ошибка загрузки',
          style: const TextStyle(color: AppTheme.danger),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: onRetry, child: const Text('Повторить')),
      ],
    ),
  );
}

/// Shared card shell (mirrors financial_dashboard_widget.dart).
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Legend item reused from financial_dashboard_widget.dart pattern.
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// KPI card (mirrors _KpiCard in reports_widget.dart).
class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 1. Воронка
// ────────────────────────────────────────────────────────────

class _FunnelSection extends ConsumerWidget {
  const _FunnelSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsFunnelProvider);
    return _SectionCard(
      title: 'Воронка',
      child: async.when(
        loading: _loadingWidget,
        error: (e, _) => _errorWidget(e, () => ref.invalidate(analyticsFunnelProvider)),
        data: (data) => _FunnelChart(data: data),
      ),
    );
  }
}

class _FunnelChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _FunnelChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final stages = (data['stages'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    if (stages.isEmpty) {
      return Center(
        child: Text(
          'Нет данных',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final maxY = stages
        .map((s) => _toDouble(s['leadsEntered']))
        .fold(1.0, (a, b) => a > b ? a : b) *
        1.2;

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY <= 0 ? 1 : maxY,
              barGroups: stages.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: _toDouble(e.value['leadsEntered']),
                      color: AppTheme.primaryPurple,
                      width: 18,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }).toList(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (val, _) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= stages.length) {
                        return const SizedBox.shrink();
                      }
                      final stage = stages[idx];
                      final ratio = _toDouble(stage['ratioToPrevStage']);
                      final name = stage['name']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (ratio > 0)
                              Text(
                                '${ratio.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.success,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendItem(color: AppTheme.primaryPurple, label: 'Лиды в стадии'),
          ],
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 2. Долги по срокам
// ────────────────────────────────────────────────────────────

class _DebtsSection extends ConsumerWidget {
  const _DebtsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsDebtsProvider);
    return _SectionCard(
      title: 'Долги по срокам',
      child: async.when(
        loading: _loadingWidget,
        error: (e, _) => _errorWidget(e, () => ref.invalidate(analyticsDebtsProvider)),
        data: (data) => _DebtsContent(data: data),
      ),
    );
  }
}

class _DebtsContent extends StatelessWidget {
  final Map<String, dynamic> data;

  const _DebtsContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final buckets = (data['buckets'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final distinctStudents = _toInt(data['distinctStudents']);
    final totalAmount = _toDouble(data['totalAmount']);

    return Column(
      children: [
        // KPI row
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Должников',
                value: _fmtCount(distinctStudents),
                icon: Icons.people_outline_rounded,
                color: AppTheme.danger,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: 'Общий долг',
                value: _fmtMoney(totalAmount),
                icon: Icons.account_balance_wallet_outlined,
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (buckets.isNotEmpty) ...[
          _DebtsChart(buckets: buckets),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendItem(color: AppTheme.danger, label: 'Должников'),
            ],
          ),
          const SizedBox(height: 12),
          // Per-bucket amount list (honest real values, not scaled)
          ...buckets.map((b) {
            final label = b['bucket']?.toString() ?? '—';
            final students = _toInt(b['students']);
            final amount = _toDouble(b['amount']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$label: $students уч. · ${_fmtMoney(amount)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }),
        ] else
          Center(
            child: Text(
              'Нет данных',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _DebtsChart extends StatelessWidget {
  final List<Map<String, dynamic>> buckets;

  const _DebtsChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final maxStudents = buckets
        .map((b) => _toDouble(b['students']))
        .fold(1.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxStudents * 1.2,
          barGroups: buckets.asMap().entries.map((e) {
            final b = e.value;
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: _toDouble(b['students']),
                  color: AppTheme.danger,
                  width: 22,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, _) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= buckets.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      buckets[idx]['bucket']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
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
    );
  }
}

// ────────────────────────────────────────────────────────────
// 3. Прогноз выручки
// ────────────────────────────────────────────────────────────

class _ForecastSection extends ConsumerWidget {
  const _ForecastSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsForecastProvider);
    return _SectionCard(
      title: 'Прогноз выручки',
      child: async.when(
        loading: _loadingWidget,
        error: (e, _) => _errorWidget(e, () => ref.invalidate(analyticsForecastProvider)),
        data: (data) => _ForecastContent(data: data),
      ),
    );
  }
}

class _ForecastContent extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ForecastContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final next7 = _toDouble(data['next7']);
    final next14 = _toDouble(data['next14']);
    final next30 = _toDouble(data['next30']);

    if (next7 == 0 && next14 == 0 && next30 == 0) {
      return Center(
        child: Text(
          'Нет данных',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: '7 дней',
            value: _fmtMoney(next7),
            icon: Icons.event_rounded,
            color: AppTheme.primaryPurple,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            label: '14 дней',
            value: _fmtMoney(next14),
            icon: Icons.event_note_rounded,
            color: AppTheme.secondaryGold,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            label: '30 дней',
            value: _fmtMoney(next30),
            icon: Icons.calendar_month_rounded,
            color: AppTheme.success,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 4. Сравнение филиалов
// ────────────────────────────────────────────────────────────

class _BranchesSection extends ConsumerWidget {
  const _BranchesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsBranchesProvider);
    return _SectionCard(
      title: 'Сравнение филиалов',
      child: async.when(
        loading: _loadingWidget,
        error: (e, _) => _errorWidget(e, () => ref.invalidate(analyticsBranchesProvider)),
        data: (data) => _BranchesContent(data: data),
      ),
    );
  }
}

class _BranchesContent extends StatelessWidget {
  final Map<String, dynamic> data;

  const _BranchesContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final branches = (data['branches'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    if (branches.isEmpty) {
      return Center(
        child: Text(
          'Нет данных',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final maxRevenue = branches
        .map((b) => _toDouble(b['revenue']))
        .fold(1.0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxRevenue * 1.2,
              barGroups: branches.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: _toDouble(e.value['revenue']),
                      color: AppTheme.success,
                      width: 18,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }).toList(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (val, _) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= branches.length) {
                        return const SizedBox.shrink();
                      }
                      final name = branches[idx]['name']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 36,
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    },
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
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendItem(color: AppTheme.success, label: 'Выручка'),
          ],
        ),
        const SizedBox(height: 16),
        // Per-branch detail rows
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: branches.length,
          separatorBuilder: (_, _) => const Divider(height: 16),
          itemBuilder: (context, i) {
            final b = branches[i];
            final fmt = NumberFormat('#,##0', 'ru');
            return Row(
              children: [
                Expanded(
                  child: Text(
                    b['name']?.toString() ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _SmallStat(
                  label: 'выручка',
                  value: '${fmt.format(_toDouble(b['revenue']).round())} ₽',
                  color: AppTheme.success,
                ),
                const SizedBox(width: 12),
                _SmallStat(
                  label: 'учеников',
                  value: '${_toInt(b['activeStudents'])}',
                  color: AppTheme.primaryPurple,
                ),
                const SizedBox(width: 12),
                _SmallStat(
                  label: 'лидов',
                  value: '${_toInt(b['newLeads'])}',
                  color: AppTheme.warning,
                ),
                const SizedBox(width: 12),
                _SmallStat(
                  label: 'занятий',
                  value: '${_toInt(b['completedLessons'])}',
                  color: AppTheme.secondaryGold,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SmallStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SmallStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 5. Риск оттока
// ────────────────────────────────────────────────────────────

class _ChurnSection extends ConsumerWidget {
  const _ChurnSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsChurnProvider);
    return _SectionCard(
      title: 'Риск оттока',
      child: async.when(
        loading: _loadingWidget,
        error: (e, _) => _errorWidget(e, () => ref.invalidate(analyticsChurnProvider)),
        data: (data) => _ChurnContent(data: data),
      ),
    );
  }
}


class _ChurnContent extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ChurnContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final totalAtRisk = _toInt(data['totalAtRisk']);
    final inactiveDays = _toInt(data['inactiveDays']);
    final students = (data['students'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .take(10)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (inactiveDays > 0) ...[
          Text(
            'Неактивны более $inactiveDays дней',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _KpiCard(
          label: 'Под риском оттока',
          value: _fmtCount(totalAtRisk),
          icon: Icons.person_off_rounded,
          color: AppTheme.danger,
        ),
        if (students.isNotEmpty) ...[
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: students.length,
            separatorBuilder: (_, _) => const Divider(height: 12),
            itemBuilder: (context, i) {
              final s = students[i];
              final days = _toInt(s['daysSinceLast']);
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      s['name']?.toString() ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$days дн.',
                      style: const TextStyle(
                        color: AppTheme.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 6. SLA чатов
// ────────────────────────────────────────────────────────────

class _SlaSection extends ConsumerWidget {
  const _SlaSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsChatSlaProvider);
    return _SectionCard(
      title: 'SLA чатов',
      child: async.when(
        loading: _loadingWidget,
        error: (e, _) => _errorWidget(e, () => ref.invalidate(analyticsChatSlaProvider)),
        data: (data) => _SlaContent(data: data),
      ),
    );
  }
}

class _SlaContent extends StatelessWidget {
  final Map<String, dynamic> data;

  const _SlaContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final responseRate = _toDouble(data['responseRate']);
    final avgMinutes = _toDouble(data['avgMinutes']);
    final medianMinutes = _toDouble(data['medianMinutes']);
    final p90Minutes = _toDouble(data['p90Minutes']);

    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: 'Ответили %',
            value: '${responseRate.toStringAsFixed(1)}%',
            icon: Icons.check_circle_outline_rounded,
            color: responseRate >= 80 ? AppTheme.success : AppTheme.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'Среднее мин.',
            value: avgMinutes.toStringAsFixed(1),
            icon: Icons.timer_outlined,
            color: AppTheme.primaryPurple,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'Медиана мин.',
            value: medianMinutes.toStringAsFixed(1),
            icon: Icons.timelapse_rounded,
            color: AppTheme.secondaryGold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'P90 мин.',
            value: p90Minutes.toStringAsFixed(1),
            icon: Icons.speed_rounded,
            color: p90Minutes > 60 ? AppTheme.danger : AppTheme.success,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 7. Причины потерь
// ────────────────────────────────────────────────────────────

class _LossReasonsSection extends ConsumerWidget {
  const _LossReasonsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsLossReasonsProvider);
    return _SectionCard(
      title: 'Причины потерь',
      child: async.when(
        loading: _loadingWidget,
        error: (e, _) => _errorWidget(
          e,
          () => ref.invalidate(analyticsLossReasonsProvider),
        ),
        data: (data) => _LossReasonsContent(data: data),
      ),
    );
  }
}

class _LossReasonsContent extends StatelessWidget {
  final Map<String, dynamic> data;

  const _LossReasonsContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final reasons = (data['reasons'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => _toInt(b['leads']).compareTo(_toInt(a['leads'])));
    final unspecified = _toInt(data['unspecifiedCount']);

    if (reasons.isEmpty && unspecified == 0) {
      return Center(
        child: Text(
          'Нет данных',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final maxLeads = reasons.isEmpty
        ? 1
        : reasons.map((r) => _toInt(r['leads'])).reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        ...reasons.map((r) {
          final leads = _toInt(r['leads']);
          final ratio = maxLeads > 0 ? leads / maxLeads : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        r['name']?.toString() ?? '—',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$leads лид.',
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
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.white10,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ),
          );
        }),
        if (unspecified > 0) ...[
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Не указана причина',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              Text(
                '$unspecified лид.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
