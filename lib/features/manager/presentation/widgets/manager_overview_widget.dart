import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/providers/crm_section_focus_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';

part 'manager_overview_widgets.dart';

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
  /// Реальная роль текущего пользователя (KVA-239): общешкольные денежные
  /// KPI (Выручка/Ожидаемые платежи) видны только director/system_admin.
  final String role;
  const ManagerOverviewWidget({
    super.key,
    this.onTabChange,
    required this.role,
  });

  @override
  ConsumerState<ManagerOverviewWidget> createState() =>
      _ManagerOverviewWidgetState();
}

class _ManagerOverviewWidgetState extends ConsumerState<ManagerOverviewWidget> {
  // KVA-239: общешкольные денежные показатели (Выручка/Ожидаемые платежи)
  // видят только director/system_admin; у manager сервер отдаёт их null.
  bool get _canSeeFinance => crmHasSchoolFinanceAccess(widget.role);

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
            child: Center(
              child: ConstrainedBox(
                // Keep the dashboard readable instead of stretching cards and
                // KPI tiles across the whole desktop window. Matches the
                // AdminOverviewWidget constraint for cross-panel consistency.
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DashboardHeader(
                      periodLabel: window.label(),
                      loading:
                          snapshot.connectionState == ConnectionState.waiting,
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
                      expectedPayments: _canSeeFinance
                          ? _asNum(kpis['expected_payments'])
                          : null,
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
            ),
          ),
        );
      },
    );
  }

  /// Set a one-shot filter for the target section, then navigate to it. The
  /// section widget consumes the focus on open (clear-on-consume) — so «Новые
  /// лиды» opens the leads board already filtered to new leads, etc.
  void _focusAndGo(
    String section,
    Map<String, String> filters,
    int tabIndex,
  ) {
    ref
        .read(crmSectionFocusProvider.notifier)
        .focus(CrmSectionFocus(section, filters));
    widget.onTabChange?.call(tabIndex, null);
  }

  List<_KpiSpec> _kpiSpecs(Map<String, dynamic> sources) {
    return [
      if (_canSeeFinance)
        _KpiSpec(
          key: 'revenue',
          label: 'Выручка',
          icon: Icons.account_balance_wallet_rounded,
          accent: AppTheme.success,
          sourceLabel: _sourceLabel(sources['revenue'], 'Финансы'),
          format: _money,
          onTap: () => widget.onTabChange?.call(7, null),
        ),
      if (_canSeeFinance)
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
        accent: AppTheme.primaryGold,
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
        onTap: () => _focusAndGo('leads', {'status': 'new'}, 3),
      ),
      _KpiSpec(
        key: 'open_tasks',
        label: 'Открытые задачи',
        icon: Icons.task_alt_rounded,
        accent: AppTheme.warning,
        sourceLabel: _sourceLabel(sources['tasks'], 'Задачи'),
        format: _count,
        onTap: () =>
            _focusAndGo('tasks', {'due': 'all', 'status': 'open'}, 6),
      ),
      _KpiSpec(
        key: 'overdue_tasks',
        label: 'Просроченные задачи',
        icon: Icons.timer_off_rounded,
        accent: AppTheme.danger,
        sourceLabel: _sourceLabel(sources['tasks'], 'Задачи'),
        format: _count,
        onTap: () => _focusAndGo('tasks', {'due': 'overdue'}, 6),
      ),
      _KpiSpec(
        key: 'trial_lessons',
        label: 'Пробные занятия',
        icon: Icons.event_note_rounded,
        accent: AppTheme.secondaryGold,
        sourceLabel: _sourceLabel(sources['schedule'], 'Расписание'),
        format: _count,
        onTap: () => _focusAndGo('schedule', {'trial': '1'}, 2),
      ),
      _KpiSpec(
        key: 'schedule_issues',
        label: 'Конфликты расписания',
        icon: Icons.warning_amber_rounded,
        accent: AppTheme.danger,
        sourceLabel: _sourceLabel(sources['schedule'], 'Расписание'),
        format: _count,
        onTap: () => _focusAndGo('schedule', {'conflicts': '1'}, 2),
      ),
      _KpiSpec(
        key: 'room_load_lessons',
        label: 'Загрузка аудиторий',
        icon: Icons.meeting_room_rounded,
        accent: AppTheme.primaryGold,
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

