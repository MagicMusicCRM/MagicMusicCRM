import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'package:magic_music_crm/features/manager/presentation/widgets/financial_dashboard_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/management_dashboard_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/subscription_catalog_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';

class ReportsWidget extends ConsumerStatefulWidget {
  final int initialTab;
  const ReportsWidget({super.key, this.initialTab = 0});

  @override
  ConsumerState<ReportsWidget> createState() => _ReportsWidgetState();
}

class _ReportsWidgetState extends ConsumerState<ReportsWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<_MonthData> _monthlyData = [];
  bool _loading = true;
  Object? _loadError;
  Map<String, dynamic> _summary = {};
  // How many months back the analytics cover (inclusive of the current month).
  int _monthsBack = 6;

  // ── Extra analytics cards (KVA-198): four previously-orphaned endpoints ─────
  // Each loads with the same period (_monthsBack) as the rest of the overview
  // tab and tracks its own state so one failing card never breaks the view.
  Map<String, dynamic>? _sources;
  bool _sourcesError = false;
  Map<String, dynamic>? _dataQuality;
  bool _dataQualityError = false;
  Map<String, dynamic>? _responsible;
  bool _responsibleError = false;
  Map<String, dynamic>? _financeMonthly;
  bool _financeMonthlyError = false;

  // ── Realtime invalidation (crm.changed) ───────────────────────────────────
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 5),
    );
    _loadReports();
  }

  @override
  void didUpdateWidget(covariant ReportsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTab = widget.initialTab.clamp(0, 5);
    if (nextTab != _tabController.index) {
      _tabController.index = nextTab;
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _loadError = null;
      // Reset the extra analytics cards to their loading state.
      _sources = null;
      _sourcesError = false;
      _dataQuality = null;
      _dataQualityError = false;
      _responsible = null;
      _responsibleError = false;
      _financeMonthly = null;
      _financeMonthlyError = false;
    });
    try {
      final now = DateTime.now();
      final periodStart = DateTime(now.year, now.month - (_monthsBack - 1), 1);
      final fromIso = periodStart.toUtc().toIso8601String();
      final toIso = now.add(const Duration(days: 1)).toUtc().toIso8601String();
      final report = await ref
          .read(magicCrmServiceProvider)
          .getFinanceReport(from: fromIso, to: toIso);
      // Kick off the four extra analytics cards with the SAME period/branch
      // filter; they update independently and never abort the main load.
      unawaited(_loadExtraAnalytics(from: fromIso, to: toIso));
      final monthList = (report['monthly'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_MonthData.fromReport)
          .toList();
      final summary = report['summary'] is Map<String, dynamic>
          ? report['summary'] as Map<String, dynamic>
          : const <String, dynamic>{};

      setState(() {
        _monthlyData = monthList;
        _summary = {
          'attendance': summary['attendance'] ?? 0.0,
          'revenue': summary['revenue'] ?? 0,
          'total_lessons': summary['total_lessons'] ?? 0,
        };
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// Loads the four supplementary analytics cards (KVA-198). Each call is
  /// guarded on its own so a single failing endpoint degrades to a graceful
  /// empty card instead of crashing the whole reports view. Honours the same
  /// period (from/to) as the rest of the overview tab; branchId is unset here,
  /// matching the other getAnalytics* calls in this widget.
  Future<void> _loadExtraAnalytics({
    required String from,
    required String to,
  }) async {
    final service = ref.read(magicCrmServiceProvider);

    Future<void> run(
      Future<Map<String, dynamic>> Function() fetch,
      void Function(Map<String, dynamic>? data, bool error) apply,
    ) async {
      try {
        final data = await fetch();
        if (mounted) setState(() => apply(data, false));
      } catch (_) {
        if (mounted) setState(() => apply(null, true));
      }
    }

    await Future.wait([
      run(() => service.getAnalyticsSources(from: from, to: to), (data, error) {
        _sources = data;
        _sourcesError = error;
      }),
      run(() => service.getAnalyticsDataQuality(), (data, error) {
        _dataQuality = data;
        _dataQualityError = error;
      }),
      run(() => service.getAnalyticsResponsible(from: from, to: to), (
        data,
        error,
      ) {
        _responsible = data;
        _responsibleError = error;
      }),
      run(() => service.getAnalyticsFinanceMonthly(from: from, to: to), (
        data,
        error,
      ) {
        _financeMonthly = data;
        _financeMonthlyError = error;
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: refresh the current report when another staff member changes a
    // payment, lesson, or expense. Reports are heavy → longer (800ms) debounce.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || !mounted) return;
      if (event.isFallbackPoll) return;
      if (event.entity != 'payment' &&
          event.entity != 'lesson' &&
          event.entity != 'expense') {
        return;
      }
      if (_loading) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 800), () {
        if (!mounted || _loading) return;
        _loadReports();
      });
    });
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColor.gold),
      );
    }
    if (_loadError != null) {
      return _ReportsError(error: _loadError, onRetry: _loadReports);
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColor.gold,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: AppColor.gold,
          tabs: const [
            Tab(text: 'Аналитика'),
            Tab(text: 'Финансы'),
            Tab(text: 'Активность'),
            Tab(text: 'Управление'),
            Tab(text: 'Абонементы'),
            // KVA-238: отчёт «Статистика преподавателей» (зарплатный модуль).
            Tab(text: 'Преподаватели'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              const FinancialDashboardWidget(),
              const _ActivityLogTab(),
              const ManagementDashboardWidget(),
              const SubscriptionCatalogWidget(),
              const TeacherStatsWidget(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final fmt = NumberFormat('#,##0', 'ru');
    final maxRevenue = _monthlyData.isEmpty
        ? 1.0
        : _monthlyData.map((m) => m.revenue).reduce((a, b) => a > b ? a : b);
    final maxLessons = _monthlyData.isEmpty
        ? 1
        : _monthlyData.map((m) => m.lessons).reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      color: AppColor.gold,
      onRefresh: _loadReports,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Отчёты',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'За последние $_monthsBack мес.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 3, label: Text('3 мес')),
                        ButtonSegment(value: 6, label: Text('6 мес')),
                        ButtonSegment(value: 12, label: Text('12 мес')),
                      ],
                      selected: {_monthsBack},
                      onSelectionChanged: (s) {
                        setState(() => _monthsBack = s.first);
                        _loadReports();
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? AppColor.goldSoft
                              : Colors.transparent,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? AppColor.gold
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // KPI Row
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        label: 'Посещаемость',
                        value:
                            '${_asDouble(_summary['attendance']).toStringAsFixed(1)}%',
                        icon: Icons.trending_up_rounded,
                        color: AppColor.success,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _KpiCard(
                        label: 'Выручка',
                        value: '${fmt.format(_summary['revenue'] ?? 0)} ₽',
                        icon: Icons.payments_rounded,
                        color: AppTheme.secondaryGold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _KpiCard(
                        label: 'Занятий',
                        value: '${_summary['total_lessons'] ?? 0}',
                        icon: Icons.calendar_month_rounded,
                        color: AppColor.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Lessons Chart
                const Text(
                  'Занятия по месяцам',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 176,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _monthlyData.map((m) {
                      final ratio = maxLessons > 0
                          ? m.lessons / maxLessons
                          : 0.0;
                      final completedRatio = m.lessons > 0
                          ? m.completed / m.lessons
                          : 0.0;
                      final plannedHeight = m.lessons > 0
                          ? math.max(8.0, 116 * ratio)
                          : 2.0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 18,
                                child: Text(
                                  '${m.lessons}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: plannedHeight,
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondaryGold.withAlpha(
                                        34,
                                      ),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    height: plannedHeight * completedRatio,
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondaryGold,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                m.month,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
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
                    Container(
                      width: 10,
                      height: 10,
                      color: AppTheme.secondaryGold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Завершено',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 10,
                      height: 10,
                      color: AppTheme.secondaryGold.withAlpha(34),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Всего запланировано',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Revenue Chart
                const Text(
                  'Выручка по месяцам',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 158,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _monthlyData.map((m) {
                      final ratio = maxRevenue > 0
                          ? m.revenue / maxRevenue
                          : 0.0;
                      final barHeight = m.revenue > 0
                          ? math.max(8.0, 96 * ratio)
                          : 2.0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 18,
                                child: Text(
                                  m.revenue >= 1000
                                      ? '${(m.revenue / 1000).toStringAsFixed(0)}к'
                                      : m.revenue.toStringAsFixed(0),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: m.revenue > 0
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurface
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryGold,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                m.month,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // Monthly table
                const Text(
                  'Детализация',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ..._monthlyData.reversed.map(
                  (m) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withAlpha(90),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            m.month,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          _SmallStat(
                            label: 'занятий',
                            value: '${m.lessons}',
                            color: AppColor.gold,
                          ),
                          const SizedBox(width: 16),
                          _SmallStat(
                            label: 'новых',
                            value: '${m.newStudents}',
                            color: AppColor.success,
                          ),
                          const SizedBox(width: 16),
                          _SmallStat(
                            label: 'выручка',
                            value: '${fmt.format(m.revenue)} ₽',
                            color: AppTheme.secondaryGold,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── KVA-198: four previously-orphaned analytics endpoints ─────────
                const SizedBox(height: 24),
                _buildSourcesCard(),
                const SizedBox(height: 24),
                _buildDataQualityCard(),
                const SizedBox(height: 24),
                _buildResponsibleCard(),
                const SizedBox(height: 24),
                _buildFinanceMonthlyCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── KVA-198 card builders ───────────────────────────────────────────────────

  /// «Источники» — lead-source breakdown with an optional share bar.
  Widget _buildSourcesCard() {
    return _AnalyticsCard(
      title: 'Источники',
      icon: Icons.call_split_rounded,
      isLoading: _sources == null && !_sourcesError,
      isError: _sourcesError,
      isEmpty: _readList(_sources, const ['sources', 'items']).isEmpty,
      child: Builder(
        builder: (context) {
          final rows = _readList(_sources, const ['sources', 'items']);
          final colors = Theme.of(context).colorScheme;
          final fmt = NumberFormat('#,##0', 'ru');
          final maxCount = rows.fold<num>(0, (m, r) {
            final c = _asDouble(_pick(r, const ['leads', 'count', 'total']));
            return c > m ? c : m;
          });
          return Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _pick(r, const [
                                    'displayName',
                                    'display_name',
                                    'source',
                                    'name',
                                  ])?.toString() ??
                                  '(не указан)',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            fmt.format(
                              _asDouble(
                                _pick(r, const ['leads', 'count', 'total']),
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColor.gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: maxCount <= 0
                              ? 0
                              : (_asDouble(
                                          _pick(r, const [
                                            'leads',
                                            'count',
                                            'total',
                                          ]),
                                        ) /
                                        maxCount)
                                    .clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: colors.surfaceContainerHighest
                              .withAlpha(60),
                          valueColor: const AlwaysStoppedAnimation(
                            AppTheme.secondaryGold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// «Качество данных» — missing-field / quality metrics as labelled stat rows.
  Widget _buildDataQualityCard() {
    return _AnalyticsCard(
      title: 'Качество данных',
      icon: Icons.verified_outlined,
      isLoading: _dataQuality == null && !_dataQualityError,
      isError: _dataQualityError,
      isEmpty: _dataQuality == null || _dataQuality!.isEmpty,
      child: Builder(
        builder: (context) {
          final data = _dataQuality ?? const <String, dynamic>{};
          final leads = data['leads'] is Map
              ? Map<String, dynamic>.from(data['leads'] as Map)
              : const <String, dynamic>{};
          final students = data['students'] is Map
              ? Map<String, dynamic>.from(data['students'] as Map)
              : const <String, dynamic>{};
          final metrics = <(String, Object?)>[
            ('Лиды всего', _pick(leads, const ['total'])),
            (
              'Лиды без телефона',
              _pick(leads, const ['missingPhone', 'missing_phone']),
            ),
            (
              'Лиды без филиала',
              _pick(leads, const ['missingBranch', 'missing_branch']),
            ),
            ('Ученики всего', _pick(students, const ['total'])),
            (
              'Ученики без филиала',
              _pick(students, const ['missingBranch', 'missing_branch']),
            ),
            (
              'Ученики без направления',
              _pick(students, const [
                'missingDiscipline',
                'missing_discipline',
              ]),
            ),
          ].where((m) => m.$2 != null).toList();

          // Fallback: if the response shape is flatter than expected, render
          // whatever numeric top-level keys it does contain.
          final rows = metrics.isNotEmpty
              ? metrics
              : data.entries
                    .where((e) => e.value is num)
                    .map((e) => (e.key, e.value as Object?))
                    .toList();

          return Column(
            children: [
              for (final m in rows)
                _StatRow(
                  label: m.$1,
                  value: NumberFormat('#,##0', 'ru').format(_asDouble(m.$2)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// «Ответственные» — per-manager lead distribution.
  Widget _buildResponsibleCard() {
    final rows = _readList(_responsible, const ['responsibles', 'items']);
    final hasUnassigned =
        _responsible != null &&
        _pick(_responsible, const ['unassignedLeads', 'unassigned_leads']) !=
            null;
    return _AnalyticsCard(
      title: 'Ответственные',
      icon: Icons.people_alt_outlined,
      isLoading: _responsible == null && !_responsibleError,
      isError: _responsibleError,
      isEmpty: rows.isEmpty && !hasUnassigned,
      child: Builder(
        builder: (context) {
          final fmt = NumberFormat('#,##0', 'ru');
          final unassigned = _asDouble(
            _pick(_responsible, const ['unassignedLeads', 'unassigned_leads']),
          );
          return Column(
            children: [
              for (final r in rows)
                _StatRow(
                  label:
                      _pick(r, const [
                        'name',
                        'fullName',
                        'full_name',
                      ])?.toString() ??
                      '—',
                  value: fmt.format(
                    _asDouble(_pick(r, const ['leads', 'count', 'total'])),
                  ),
                  valueColor: AppColor.gold,
                ),
              if (hasUnassigned)
                _StatRow(
                  label: 'Без ответственного',
                  value: fmt.format(unassigned),
                  valueColor: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            ],
          );
        },
      ),
    );
  }

  /// «Финансы по месяцам» — compact monthly income / expense / net table.
  Widget _buildFinanceMonthlyCard() {
    final rows = _readList(_financeMonthly, const ['items', 'monthly']);
    return _AnalyticsCard(
      title: 'Финансы по месяцам',
      icon: Icons.account_balance_wallet_outlined,
      isLoading: _financeMonthly == null && !_financeMonthlyError,
      isError: _financeMonthlyError,
      isEmpty: rows.isEmpty,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          final fmt = NumberFormat('#,##0', 'ru');
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: SizedBox.shrink()),
                    _financeHeaderCell('Доход', colors),
                    _financeHeaderCell('Расход', colors),
                    _financeHeaderCell('Итог', colors),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final r in rows) _buildFinanceRow(r, fmt, colors),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFinanceRow(
    Map<String, dynamic> r,
    NumberFormat fmt,
    ColorScheme colors,
  ) {
    final revenue = _asDouble(
      _pick(r, const ['revenue', 'income', 'incomeTotal']),
    );
    final expenses = _asDouble(
      _pick(r, const ['expenses', 'expense', 'expensesTotal']),
    );
    // Use server-provided net if present, otherwise derive it defensively.
    final netRaw = _pick(r, const ['net', 'profit', 'balance']);
    final net = netRaw != null ? _asDouble(netRaw) : revenue - expenses;
    final monthLabel = _financeMonthLabel(
      _pick(r, const ['monthStart', 'month_start', 'month']),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              monthLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          _financeValueCell(fmt.format(revenue), AppColor.success),
          _financeValueCell(fmt.format(expenses), AppColor.danger),
          _financeValueCell(
            fmt.format(net),
            net >= 0 ? AppTheme.secondaryGold : AppColor.danger,
          ),
        ],
      ),
    );
  }

  Widget _financeHeaderCell(String label, ColorScheme colors) {
    return Expanded(
      flex: 2,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _financeValueCell(String value, Color color) {
    return Expanded(
      flex: 2,
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ReportsError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ReportsError({required this.error, required this.onRetry});

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
              color: AppColor.danger,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Не удалось загрузить отчеты',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// Returns the first non-null value found under any of [keys] in [map].
/// Used to read analytics responses defensively across camelCase / snake_case.
Object? _pick(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return null;
  for (final k in keys) {
    final v = map[k];
    if (v != null) return v;
  }
  return null;
}

/// Reads a list of maps from [source] under the first matching key in [keys].
/// Tolerates the response itself being a bare list. Returns [] when missing.
List<Map<String, dynamic>> _readList(
  Map<String, dynamic>? source,
  List<String> keys,
) {
  if (source == null) return const [];
  for (final k in keys) {
    final v = source[k];
    if (v is List) {
      return v.whereType<Map<String, dynamic>>().toList();
    }
  }
  return const [];
}

/// Formats a month label from an ISO date / month string, defensively.
String _financeMonthLabel(Object? raw) {
  final text = raw?.toString() ?? '';
  final parsed = DateTime.tryParse(text);
  if (parsed != null) {
    return DateFormat('LLL yyyy', 'ru').format(parsed);
  }
  return text.isEmpty ? '—' : text;
}

class _MonthData {
  final String month;
  int lessons = 0;
  int completed = 0;
  int newStudents = 0;
  double revenue = 0;
  _MonthData({required this.month});

  factory _MonthData.fromReport(Map<String, dynamic> row) {
    final parsed = DateTime.tryParse(row['month_start']?.toString() ?? '');
    return _MonthData(
        month: parsed == null ? '—' : _shortMonthName(parsed.month),
      )
      ..lessons = int.tryParse('${row['lessons'] ?? 0}') ?? 0
      ..completed = int.tryParse('${row['completed'] ?? 0}') ?? 0
      ..newStudents = int.tryParse('${row['new_students'] ?? 0}') ?? 0
      ..revenue = double.tryParse('${row['revenue'] ?? 0}') ?? 0;
  }

  static String _shortMonthName(int month) {
    const names = [
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    return names[(month - 1).clamp(0, names.length - 1)];
  }
}

class _KpiCard extends StatelessWidget {
  final String label, value;
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outlineVariant.withAlpha(90)),
      ),
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

/// Shared chrome for the KVA-198 analytics cards. Renders a titled v7 surface
/// (matching the card styling used elsewhere in this file) and resolves the
/// loading / error / empty / content states so each builder only supplies its
/// populated body.
class _AnalyticsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isLoading;
  final bool isError;
  final bool isEmpty;
  final Widget child;

  const _AnalyticsCard({
    required this.title,
    required this.icon,
    required this.isLoading,
    required this.isError,
    required this.isEmpty,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget body;
    if (isLoading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColor.gold,
            ),
          ),
        ),
      );
    } else if (isError) {
      body = _AnalyticsCardHint(
        icon: Icons.cloud_off_rounded,
        text: 'Не удалось загрузить',
        color: colors.onSurfaceVariant,
      );
    } else if (isEmpty) {
      body = _AnalyticsCardHint(
        icon: Icons.inbox_outlined,
        text: 'Нет данных за период',
        color: colors.onSurfaceVariant,
      );
    } else {
      body = child;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outlineVariant.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColor.gold),
                const SizedBox(width: AppSpace.sm),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            body,
          ],
        ),
      ),
    );
  }
}

class _AnalyticsCardHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _AnalyticsCardHint({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: AppSpace.sm),
            Text(text, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A labelled stat row (label on the left, value on the right) used by the
/// data-quality and responsible cards.
class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: valueColor ?? colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SmallStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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

class _ActivityLogTab extends ConsumerStatefulWidget {
  const _ActivityLogTab();

  @override
  ConsumerState<_ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends ConsumerState<_ActivityLogTab> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  Object? _loadError;
  String _period = 'week';
  String _entityType = 'all';
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadActivity();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadActivity();
    });
  }

  Future<void> _loadActivity() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final bounds = _activityBounds(_period);
      final items = await ref
          .read(magicCrmServiceProvider)
          .listActivityLog(
            q: _searchCtrl.text,
            entityType: _entityType == 'all' ? null : _entityType,
            from: bounds.$1,
            to: bounds.$2,
            limit: 100,
          );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  void _setFilter(void Function() update) {
    setState(update);
    _loadActivity();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340, minWidth: 240),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Поиск действий',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              _ReportFilterDropdown(
                label: 'Период',
                value: _period,
                icon: Icons.event_rounded,
                options: const [
                  ('week', '7 дней'),
                  ('month', 'Месяц'),
                  ('quarter', 'Квартал'),
                ],
                onChanged: (value) => _setFilter(() => _period = value),
              ),
              _ReportFilterDropdown(
                label: 'Объект',
                value: _entityType,
                icon: Icons.link_rounded,
                options: const [
                  ('all', 'Все объекты'),
                  ('student', 'Ученики'),
                  ('lead', 'Лиды'),
                  ('teacher', 'Учителя'),
                  ('staff', 'Сотрудники'),
                  ('lesson', 'Занятия'),
                  ('task', 'Задачи'),
                ],
                onChanged: (value) => _setFilter(() => _entityType = value),
              ),
              if (_searchCtrl.text.isNotEmpty || _entityType != 'all')
                TextButton.icon(
                  onPressed: () {
                    _searchDebounce?.cancel();
                    setState(() {
                      _searchCtrl.clear();
                      _searchDebounce?.cancel();
                      _entityType = 'all';
                    });
                    _loadActivity();
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Сбросить'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColor.gold),
                )
              : _loadError != null
              ? _ReportsError(error: _loadError, onRetry: _loadActivity)
              : _items.isEmpty
              ? Center(
                  child: Text(
                    'Нет действий за период',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColor.gold,
                  onRefresh: _loadActivity,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _ActivityLogTile(item: _items[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ActivityLogTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ActivityLogTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
    final dateText = createdAt == null
        ? ''
        : DateFormat('d MMM, HH:mm', 'ru').format(createdAt.toLocal());
    final actor = item['actor_name']?.toString().trim();
    final description = item['description']?.toString().trim();
    final action = item['action']?.toString() ?? '';
    final entityType = item['entity_type']?.toString();
    final historyType = item['history_type']?.toString();
    final role = item['actor_role']?.toString();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withAlpha(90),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _activityColor(action).withAlpha(28),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _activityIcon(action),
                color: _activityColor(action),
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          description == null || description.isEmpty
                              ? _activityLabel(action)
                              : description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (dateText.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          dateText,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (actor != null && actor.isNotEmpty)
                        _ReportTag(label: actor, color: AppTheme.secondaryGold),
                      if (role != null && role.isNotEmpty)
                        _ReportTag(
                          label: _activityRoleLabel(role),
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      if (entityType != null && entityType.isNotEmpty)
                        _ReportTag(
                          label: _activityEntityLabel(entityType),
                          color: AppColor.gold,
                        ),
                      if (historyType != null && historyType.isNotEmpty)
                        _ReportTag(
                          label: _activityHistoryLabel(historyType),
                          color: AppColor.success,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportFilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  const _ReportFilterDropdown({
    required this.label,
    required this.value,
    required this.icon,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = options.any((option) => option.$1 == value)
        ? value
        : options.first.$1;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220, minWidth: 170),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$normalized'),
        initialValue: normalized,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.$1,
                child: Text(option.$2, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _ReportTag extends StatelessWidget {
  final String label;
  final Color color;

  const _ReportTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

(String?, String?) _activityBounds(String period) {
  final now = DateTime.now();
  final todayEnd = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));
  final from = switch (period) {
    'month' => DateTime(now.year, now.month),
    'quarter' => DateTime(now.year, now.month - 2),
    _ => DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6)),
  };
  return (from.toUtc().toIso8601String(), todayEnd.toUtc().toIso8601String());
}

IconData _activityIcon(String action) {
  if (action.contains('delete')) return Icons.delete_outline_rounded;
  if (action.contains('update') || action.contains('updated')) {
    return Icons.edit_note_rounded;
  }
  if (action.contains('created') || action.contains('create')) {
    return Icons.add_circle_outline_rounded;
  }
  return Icons.history_rounded;
}

Color _activityColor(String action) {
  if (action.contains('delete')) return AppTheme.danger;
  if (action.contains('update') || action.contains('updated')) {
    return AppTheme.secondaryGold;
  }
  if (action.contains('created') || action.contains('create')) {
    return AppTheme.success;
  }
  return AppTheme.primaryGold;
}

String _activityLabel(String action) {
  if (action.contains('student')) return 'Изменение ученика';
  if (action.contains('lead')) return 'Изменение лида';
  if (action.contains('lesson')) return 'Изменение занятия';
  if (action.contains('task')) return 'Изменение задачи';
  if (action.contains('comment')) return 'Комментарий';
  return 'Действие';
}

String _activityEntityLabel(String entityType) {
  return switch (entityType) {
    'student' => 'Ученик',
    'lead' => 'Лид',
    'teacher' => 'Учитель',
    'staff' => 'Сотрудник',
    'lesson' => 'Занятие',
    'task' => 'Задача',
    'comment' => 'Комментарий',
    _ => entityType,
  };
}

String _activityHistoryLabel(String historyType) {
  return switch (historyType) {
    'comment' => 'Комментарий',
    'task' => 'Задача',
    'status' => 'Статус',
    'payment' => 'Платёж',
    'lesson' => 'Занятие',
    _ => historyType,
  };
}

String _activityRoleLabel(String role) {
  return switch (role) {
    'admin' => 'Администратор',
    'system_admin' => 'Администратор системы',
    'manager' => 'Управляющий',
    'teacher' => 'Учитель',
    'client' => 'Клиент',
    _ => role,
  };
}
