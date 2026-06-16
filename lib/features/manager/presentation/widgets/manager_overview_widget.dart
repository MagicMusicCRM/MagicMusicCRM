import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';

enum _DashboardPeriod { week, month, quarter }

class _DashboardWindow {
  final DateTime from;
  final DateTime toExclusive;

  const _DashboardWindow({required this.from, required this.toExclusive});

  String get fromIso => from.toUtc().toIso8601String();
  String get toIso => toExclusive.toUtc().toIso8601String();

  String label() {
    final visibleTo = toExclusive.subtract(const Duration(days: 1));
    final sameMonth =
        from.year == visibleTo.year && from.month == visibleTo.month;
    final fromFmt = DateFormat(sameMonth ? 'd' : 'd MMM', 'ru');
    final toFmt = DateFormat('d MMM', 'ru');
    return '${fromFmt.format(from)} - ${toFmt.format(visibleTo)}';
  }
}

extension _DashboardPeriodBounds on _DashboardPeriod {
  String get label {
    return switch (this) {
      _DashboardPeriod.week => '7 дней',
      _DashboardPeriod.month => 'Месяц',
      _DashboardPeriod.quarter => 'Квартал',
    };
  }

  _DashboardWindow window(DateTime now) {
    final todayEnd = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    return switch (this) {
      _DashboardPeriod.week => _DashboardWindow(
        from: DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6)),
        toExclusive: todayEnd,
      ),
      _DashboardPeriod.month => _DashboardWindow(
        from: DateTime(now.year, now.month),
        toExclusive: todayEnd,
      ),
      _DashboardPeriod.quarter => _DashboardWindow(
        from: DateTime(now.year, now.month - 2),
        toExclusive: todayEnd,
      ),
    };
  }
}

class ManagerOverviewWidget extends ConsumerStatefulWidget {
  final Function(int index, int? subIndex)? onTabChange;
  const ManagerOverviewWidget({super.key, this.onTabChange});

  @override
  ConsumerState<ManagerOverviewWidget> createState() =>
      _ManagerOverviewWidgetState();
}

class _ManagerOverviewWidgetState extends ConsumerState<ManagerOverviewWidget> {
  _DashboardPeriod _period = _DashboardPeriod.month;
  String? _branchId;
  late Future<List<Map<String, dynamic>>> _branchesFuture;
  late Future<Map<String, dynamic>> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _branchesFuture = ref.read(magicCrmServiceProvider).listBranches();
    _dashboardFuture = _loadDashboard();
  }

  Future<Map<String, dynamic>> _loadDashboard() {
    final window = _period.window(DateTime.now());
    return ref
        .read(magicCrmServiceProvider)
        .getManagerDashboard(
          from: window.fromIso,
          to: window.toIso,
          branchId: _branchId,
        );
  }

  void _reloadDashboard({bool refreshBranches = false}) {
    setState(() {
      if (refreshBranches) {
        _branchesFuture = ref.read(magicCrmServiceProvider).listBranches();
      }
      _dashboardFuture = _loadDashboard();
    });
  }

  Future<void> _refresh() async {
    _reloadDashboard(refreshBranches: true);
    try {
      await _dashboardFuture;
    } catch (_) {
      // Error state is rendered by FutureBuilder.
    }
  }

  void _setPeriod(_DashboardPeriod period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _dashboardFuture = _loadDashboard();
    });
  }

  void _setBranch(String? branchId) {
    final next = branchId?.trim().isEmpty == true ? null : branchId;
    if (_branchId == next) return;
    setState(() {
      _branchId = next;
      _dashboardFuture = _loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const DashboardStatsSkeleton(count: 11);
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return _DashboardError(
            error: snapshot.error,
            onRetry: () => _reloadDashboard(refreshBranches: true),
          );
        }

        final dashboard = snapshot.data ?? const <String, dynamic>{};
        final kpis = dashboard['kpis'] is Map<String, dynamic>
            ? dashboard['kpis'] as Map<String, dynamic>
            : const <String, dynamic>{};
        final sources = dashboard['sources'] is Map<String, dynamic>
            ? dashboard['sources'] as Map<String, dynamic>
            : const <String, dynamic>{};
        final window = _period.window(DateTime.now());

        return RefreshIndicator(
          color: AppTheme.secondaryGold,
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DashboardHeader(
                  periodLabel: window.label(),
                  loading: snapshot.connectionState == ConnectionState.waiting,
                ),
                const SizedBox(height: 14),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _branchesFuture,
                  builder: (context, branchesSnapshot) {
                    return _DashboardFilters(
                      period: _period,
                      branchId: _branchId,
                      branches: branchesSnapshot.data ?? const [],
                      branchesLoading:
                          branchesSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          !branchesSnapshot.hasData,
                      onPeriodChanged: _setPeriod,
                      onBranchChanged: _setBranch,
                    );
                  },
                ),
                const SizedBox(height: 14),
                _AttentionPanel(
                  overdueTasks: _asNum(kpis['overdue_tasks']),
                  scheduleIssues: _asNum(kpis['schedule_issues']),
                  debtStudents: _asNum(kpis['debt_students']),
                  expectedPayments: _asNum(kpis['expected_payments']),
                  onTasksTap: () => widget.onTabChange?.call(6, null),
                  onScheduleTap: () => widget.onTabChange?.call(2, null),
                  onDebtsTap: () => widget.onTabChange?.call(5, null),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final tileWidth = constraints.maxWidth >= 1040
                        ? (constraints.maxWidth - 20) / 3
                        : constraints.maxWidth >= 680
                        ? (constraints.maxWidth - 10) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _kpiSpecs(sources).map((spec) {
                        return SizedBox(
                          width: tileWidth,
                          child: _KpiTile(
                            icon: spec.icon,
                            label: spec.label,
                            value: spec.format(kpis[spec.key]),
                            accent: spec.accent,
                            sourceLabel: spec.sourceLabel,
                            onTap: spec.onTap,
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_KpiSpec> _kpiSpecs(Map<String, dynamic> sources) {
    return [
      _KpiSpec(
        key: 'revenue',
        label: 'Выручка',
        icon: Icons.account_balance_wallet_rounded,
        accent: AppTheme.success,
        sourceLabel: _sourceLabel(sources['revenue'], 'Финансы'),
        format: _money,
        onTap: () => widget.onTabChange?.call(7, null),
      ),
      _KpiSpec(
        key: 'expected_payments',
        label: 'Ожидаемые платежи',
        icon: Icons.event_available_rounded,
        accent: AppTheme.secondaryGold,
        sourceLabel: _sourceLabel(sources['expectedPayments'], 'Платежи'),
        format: _money,
        onTap: () => widget.onTabChange?.call(5, null),
      ),
      _KpiSpec(
        key: 'debt_students',
        label: 'Ученики с долгом',
        icon: Icons.priority_high_rounded,
        accent: AppTheme.danger,
        sourceLabel: _sourceLabel(sources['debtStudents'], 'Балансы'),
        format: _count,
        onTap: () => widget.onTabChange?.call(5, null),
      ),
      _KpiSpec(
        key: 'active_students',
        label: 'Активные ученики',
        icon: Icons.school_rounded,
        accent: AppTheme.primaryPurple,
        sourceLabel: 'CRM',
        format: _count,
        onTap: () => widget.onTabChange?.call(4, null),
      ),
      _KpiSpec(
        key: 'new_leads',
        label: 'Новые лиды',
        icon: Icons.person_add_rounded,
        accent: AppTheme.warning,
        sourceLabel: _sourceLabel(sources['newLeads'], 'Лиды'),
        format: _count,
        onTap: () => widget.onTabChange?.call(3, null),
      ),
      _KpiSpec(
        key: 'open_tasks',
        label: 'Открытые задачи',
        icon: Icons.task_alt_rounded,
        accent: AppTheme.warning,
        sourceLabel: _sourceLabel(sources['tasks'], 'Задачи'),
        format: _count,
        onTap: () => widget.onTabChange?.call(6, null),
      ),
      _KpiSpec(
        key: 'overdue_tasks',
        label: 'Просроченные задачи',
        icon: Icons.timer_off_rounded,
        accent: AppTheme.danger,
        sourceLabel: _sourceLabel(sources['tasks'], 'Задачи'),
        format: _count,
        onTap: () => widget.onTabChange?.call(6, null),
      ),
      _KpiSpec(
        key: 'trial_lessons',
        label: 'Пробные занятия',
        icon: Icons.event_note_rounded,
        accent: AppTheme.secondaryGold,
        sourceLabel: _sourceLabel(sources['schedule'], 'Расписание'),
        format: _count,
        onTap: () => widget.onTabChange?.call(2, null),
      ),
      _KpiSpec(
        key: 'schedule_issues',
        label: 'Конфликты расписания',
        icon: Icons.warning_amber_rounded,
        accent: AppTheme.danger,
        sourceLabel: _sourceLabel(sources['schedule'], 'Расписание'),
        format: _count,
        onTap: () => widget.onTabChange?.call(2, null),
      ),
      _KpiSpec(
        key: 'room_load_lessons',
        label: 'Загрузка аудиторий',
        icon: Icons.meeting_room_rounded,
        accent: AppTheme.primaryPurple,
        sourceLabel: _sourceLabel(sources['schedule'], 'Расписание'),
        format: _count,
        onTap: () => widget.onTabChange?.call(7, null),
      ),
      _KpiSpec(
        key: 'staff_activity',
        label: 'Действия сотрудников',
        icon: Icons.manage_history_rounded,
        accent: AppTheme.secondaryGold,
        sourceLabel: _sourceLabel(sources['activity'], 'Активность'),
        format: _count,
        onTap: () => widget.onTabChange?.call(7, 2),
      ),
    ];
  }
}

class _DashboardHeader extends StatelessWidget {
  final String periodLabel;
  final bool loading;

  const _DashboardHeader({required this.periodLabel, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Сводка менеджера',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                periodLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: loading ? 1 : 0,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }
}

class _DashboardFilters extends StatelessWidget {
  final _DashboardPeriod period;
  final String? branchId;
  final List<Map<String, dynamic>> branches;
  final bool branchesLoading;
  final ValueChanged<_DashboardPeriod> onPeriodChanged;
  final ValueChanged<String?> onBranchChanged;

  const _DashboardFilters({
    required this.period,
    required this.branchId,
    required this.branches,
    required this.branchesLoading,
    required this.onPeriodChanged,
    required this.onBranchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<_DashboardPeriod>(
          segments: _DashboardPeriod.values
              .map(
                (period) =>
                    ButtonSegment(value: period, label: Text(period.label)),
              )
              .toList(),
          selected: {period},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onPeriodChanged(selection.first),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, minWidth: 220),
          child: DropdownButtonFormField<String>(
            key: ValueKey(branchId ?? 'all-branches'),
            initialValue: branchId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Филиал',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            hint: Text(branchesLoading ? 'Загрузка...' : 'Все филиалы'),
            items: branches
                .map(
                  (branch) => DropdownMenuItem<String>(
                    value: branch['id']?.toString(),
                    child: Text(
                      branch['name']?.toString() ?? 'Без названия',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: branchesLoading ? null : onBranchChanged,
          ),
        ),
        if (branchId != null)
          TextButton.icon(
            onPressed: () => onBranchChanged(null),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Все филиалы'),
          ),
      ],
    );
  }
}

class _AttentionPanel extends StatelessWidget {
  final num overdueTasks;
  final num scheduleIssues;
  final num debtStudents;
  final num expectedPayments;
  final VoidCallback? onTasksTap;
  final VoidCallback? onScheduleTap;
  final VoidCallback? onDebtsTap;

  const _AttentionPanel({
    required this.overdueTasks,
    required this.scheduleIssues,
    required this.debtStudents,
    required this.expectedPayments,
    required this.onTasksTap,
    required this.onScheduleTap,
    required this.onDebtsTap,
  });

  @override
  Widget build(BuildContext context) {
    final rows = [
      _AttentionRowData(
        icon: Icons.timer_off_rounded,
        label: 'Просроченные задачи',
        value: _count(overdueTasks),
        accent: overdueTasks > 0 ? AppTheme.danger : AppTheme.success,
        onTap: onTasksTap,
      ),
      _AttentionRowData(
        icon: Icons.warning_amber_rounded,
        label: 'Конфликты расписания',
        value: _count(scheduleIssues),
        accent: scheduleIssues > 0 ? AppTheme.danger : AppTheme.success,
        onTap: onScheduleTap,
      ),
      _AttentionRowData(
        icon: Icons.priority_high_rounded,
        label: 'Ученики с долгом',
        value: _count(debtStudents),
        accent: debtStudents > 0 ? AppTheme.warning : AppTheme.success,
        onTap: onDebtsTap,
      ),
      _AttentionRowData(
        icon: Icons.event_available_rounded,
        label: 'Ожидаемые платежи',
        value: _money(expectedPayments),
        accent: AppTheme.secondaryGold,
        onTap: onDebtsTap,
      ),
    ];

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withAlpha(10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Требует внимания',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final rowWidth = constraints.maxWidth >= 780
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: rows
                      .map(
                        (row) => SizedBox(
                          width: rowWidth,
                          child: _AttentionRow(data: row),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  final _AttentionRowData data;

  const _AttentionRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withAlpha(10)),
          ),
          child: Row(
            children: [
              Icon(data.icon, color: data.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                data.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: data.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final String sourceLabel;
  final VoidCallback? onTap;

  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.sourceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 86,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withAlpha(10)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _DashboardError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppTheme.danger,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              'Ошибка загрузки: $error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _KpiSpec {
  final String key;
  final String label;
  final IconData icon;
  final Color accent;
  final String sourceLabel;
  final String Function(Object? value) format;
  final VoidCallback? onTap;

  const _KpiSpec({
    required this.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.sourceLabel,
    required this.format,
    required this.onTap,
  });
}

class _AttentionRowData {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;

  const _AttentionRowData({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
  });
}

num _asNum(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

String _count(Object? value) {
  return NumberFormat.decimalPattern('ru').format(_asNum(value).round());
}

String _money(Object? value) {
  return '${NumberFormat('#,##0', 'ru').format(_asNum(value).round())} ₽';
}

String _sourceLabel(Object? source, String fallback) {
  final raw = source?.toString() ?? '';
  if (raw.contains('finance')) return 'Финансы';
  if (raw.contains('expected-payments')) return 'Платежи';
  if (raw.contains('student-balances')) return 'Балансы';
  if (raw.contains('leads')) return 'Лиды';
  if (raw.contains('tasks')) return 'Задачи';
  if (raw.contains('schedule')) return 'Расписание';
  if (raw.contains('activity')) return 'Активность';
  return fallback;
}
