import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';

import 'package:magic_music_crm/features/manager/presentation/widgets/financial_dashboard_widget.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/management_dashboard_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/subscription_catalog_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';

part 'reports_widget_widgets.dart';
part 'reports_widget_cards.dart';

class ReportsWidget extends ConsumerStatefulWidget {
  final int initialTab;

  /// Реальная роль текущего пользователя (KVA-239): гейтит финансовую
  /// аналитику (саб-табы «Аналитика»/«Финансы») — только director/system_admin.
  final String role;
  const ReportsWidget({super.key, this.initialTab = 0, required this.role});

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

  // KVA-239: обще-суммарная аналитика (саб-табы «Аналитика»/«Финансы») —
  // только director/system_admin.
  bool get _canSeeFinance => crmHasSchoolFinanceAccess(widget.role);

  // Поразрезные финансы: ставки/ЗП педагогов. ✔ Решение владельца 16.07 —
  // доступны и Администратору, и Управляющему.
  bool get _canSeeTeacherRates => crmHasTeacherRatesAccess(widget.role);

  /// Canonical sub-tab indices (0 Аналитика · 1 Финансы · 2 Активность ·
  /// 3 Управление · 4 Абонементы · 5 Преподаватели/ЗП) visible to the current
  /// role. «Преподаватели» — зарплатный модуль (KVA-238): это ставки
  /// конкретных педагогов, а не обще-суммарная сводка, поэтому он открыт
  /// Администратору и Управляющему. Без этого получалась нестыковка: массово
  /// проставить «входит в оклад» Управляющий мог, а открыть отчёт, из которого
  /// это делается, — нет.
  List<int> get _visibleReportTabs => [
    if (_canSeeFinance) ...[0, 1],
    2,
    3,
    4,
    if (_canSeeTeacherRates) 5,
  ];

  int _positionForCanonicalTab(int canonical) {
    final pos = _visibleReportTabs.indexOf(canonical.clamp(0, 5));
    return pos < 0 ? 0 : pos;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _visibleReportTabs.length,
      vsync: this,
      initialIndex: _positionForCanonicalTab(widget.initialTab),
    );
    if (_canSeeFinance) {
      _loadReports();
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant ReportsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Jump ONLY when the parent actually asks for a different tab (e.g. an
    // overview tile deep-links here). Comparing against `_tabController.index`
    // fired on EVERY parent rebuild — and this widget is rebuilt inline by
    // MessengerScreen, which rebuilds on every realtime `crm.changed` event
    // (it invalidates the unseen-counter provider). So any payment/lesson event
    // anywhere yanked the user out of whatever sub-tab they were reading and
    // back to `initialTab` (Активность for managers). Gate on the actual change.
    if (widget.initialTab != oldWidget.initialTab) {
      final nextTab = _positionForCanonicalTab(widget.initialTab);
      if (nextTab != _tabController.index) {
        _tabController.index = nextTab;
      }
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports({bool background = false}) async {
    if (!_canSeeFinance) return;
    // Background (realtime-driven) refresh keeps the current report on screen
    // instead of blanking every tab to a full-screen spinner — otherwise a
    // payment/lesson/expense event elsewhere throws the user out of the sub-tab.
    if (!background) {
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
    }
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
    // Realtime: client-finance writes arrive as recipient-scoped
    // `finance.changed`; lessons and expenses keep their existing CRM events.
    // Reports are heavy → longer (800ms) debounce.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || !mounted) return;
      if (event.isFallbackPoll) return;
      if (event.entity != 'finance' &&
          event.entity != 'lesson' &&
          event.entity != 'expense') {
        return;
      }
      if (!_canSeeFinance) return;
      if (_loading) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 800), () {
        if (!mounted || _loading) return;
        _loadReports(background: true);
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
          tabs: [
            if (_canSeeFinance) const Tab(text: 'Аналитика'),
            if (_canSeeFinance) const Tab(text: 'Финансы'),
            const Tab(text: 'Активность'),
            const Tab(text: 'Управление'),
            const Tab(text: 'Абонементы'),
            // KVA-238 «Статистика преподавателей» — ставки конкретных
            // педагогов, не обще-суммарная сводка → админ и управляющий тоже.
            if (_canSeeTeacherRates) const Tab(text: 'Преподаватели'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              if (_canSeeFinance) _buildOverviewTab(),
              if (_canSeeFinance) const FinancialDashboardWidget(),
              const _ActivityLogTab(),
              ManagementDashboardWidget(role: widget.role),
              SubscriptionCatalogWidget(role: widget.role),
              if (_canSeeTeacherRates) const TeacherStatsWidget(),
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
}
