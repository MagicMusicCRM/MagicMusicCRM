import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/context_transition_registry.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_state_view.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/management_dashboard_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reporting_v4_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/subscription_catalog_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';

part 'reports_widget_widgets.dart';

class ReportsWidget extends ConsumerStatefulWidget {
  const ReportsWidget({
    super.key,
    this.initialTab = 0,
    required this.role,
    this.initialLink,
    this.initialViewState,
    this.accessSnapshot,
  });

  final int initialTab;
  final String role;
  final EntityLink? initialLink;
  final ContextViewState? initialViewState;
  final CapabilitySnapshot? accessSnapshot;

  @override
  ConsumerState<ReportsWidget> createState() => _ReportsWidgetState();
}

class _ReportsWidgetState extends ConsumerState<ReportsWidget>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late DashboardFilter _dashboardFilter;
  List<Map<String, dynamic>> _branches = const [];
  Object? _branchesError;
  bool _branchesLoading = true;
  int _dashboardRevision = 0;
  Timer? _realtimeDebounce;

  bool get _canSeeFinance =>
      widget.accessSnapshot?.allows('commerce.school_finance.read') ??
      crmHasSchoolFinanceAccess(widget.role);

  bool get _canSeeStatus =>
      widget.accessSnapshot?.allows('report.status.read') ??
      (widget.role == 'manager' ||
          widget.role == 'director' ||
          widget.role == 'system_admin');

  bool get _canSeeTeacherRates => crmHasTeacherRatesAccess(widget.role);

  List<int> get _visibleReportTabs => [
    if (_canSeeStatus) 0,
    2,
    3,
    4,
    if (_canSeeTeacherRates) 5,
  ];

  int _positionForCanonicalTab(int canonical) {
    if (canonical == 1 || canonical == 6) canonical = 0;
    final position = _visibleReportTabs.indexOf(canonical.clamp(0, 6));
    return position < 0 ? 0 : position;
  }

  @override
  void initState() {
    super.initState();
    _dashboardFilter = DashboardFilter.fromContext(
      widget.initialViewState,
      widget.initialLink?.optionalFocus?.filter,
    );
    _tabController = TabController(
      length: _visibleReportTabs.length,
      vsync: this,
      initialIndex: _positionForCanonicalTab(widget.initialTab),
    );
    if (_canSeeStatus) {
      unawaited(_loadBranches());
    } else {
      _branchesLoading = false;
    }
  }

  @override
  void didUpdateWidget(covariant ReportsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      final nextTab = _positionForCanonicalTab(widget.initialTab);
      if (nextTab != _tabController.index) _tabController.index = nextTab;
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _branchesLoading = true;
      _branchesError = null;
    });
    try {
      final branches = await ref
          .read(magicCrmServiceProvider)
          .listBranches(limit: 100);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchesLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _branchesError = error;
        _branchesLoading = false;
      });
    }
  }

  void _setDashboardFilter(DashboardFilter filter) {
    if (filter == _dashboardFilter) return;
    setState(() => _dashboardFilter = filter);
    final scope = WorkspaceNavigationScope.maybeOf(context);
    if (scope != null) {
      scope.controller.updateCurrentView(
        scope.controller.state.activeTabId,
        filter.toContextViewState(),
      );
    }
  }

  Future<void> _pickDashboardPeriod() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _dashboardFilter.from,
        end: _dashboardFilter.to,
      ),
    );
    if (range != null && mounted) {
      _setDashboardFilter(_dashboardFilter.copyWithRange(range));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canSeeStatus) {
      return const EntityLinkStateView(
        key: ValueKey('reports-forbidden'),
        state: EntityRouteState.forbidden,
      );
    }
    ref.listen(crmRealtimeProvider, (previous, next) {
      final event = next.value;
      if (event == null || event.isFallbackPoll || !_canSeeStatus) return;
      if (event.entity != 'finance' &&
          event.entity != 'lesson' &&
          event.entity != 'expense' &&
          event.entity != 'task') {
        return;
      }
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _dashboardRevision++);
      });
    });
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
            if (_canSeeStatus) const Tab(text: 'Аналитика'),
            const Tab(text: 'Активность'),
            const Tab(text: 'Управление'),
            const Tab(text: 'Абонементы'),
            if (_canSeeTeacherRates) const Tab(text: 'Преподаватели'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              if (_canSeeStatus) _buildUnifiedDashboard(),
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

  Widget _buildUnifiedDashboard() {
    final colors = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('dd.MM.yyyy');
    return Column(
      key: const ValueKey('unified-dashboard'),
      children: [
        Material(
          color: colors.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Обзор школы',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                OutlinedButton.icon(
                  key: const ValueKey('dashboard-period'),
                  onPressed: _pickDashboardPeriod,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    '${dateFormat.format(_dashboardFilter.from)} — '
                    '${dateFormat.format(_dashboardFilter.to)}',
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    key: const ValueKey('dashboard-scope'),
                    initialValue: _dashboardFilter.branchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Филиал',
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          _canSeeFinance
                              ? 'Вся школа'
                              : 'Все доступные филиалы',
                        ),
                      ),
                      if (_dashboardFilter.branchId != null &&
                          !_branches.any(
                            (branch) =>
                                branch['id']?.toString() ==
                                _dashboardFilter.branchId,
                          ))
                        DropdownMenuItem<String?>(
                          value: _dashboardFilter.branchId,
                          child: const Text('Выбранный филиал'),
                        ),
                      ..._branches.map(
                        (branch) => DropdownMenuItem<String?>(
                          value: branch['id']?.toString(),
                          child: Text(
                            branch['name']?.toString() ?? 'Без названия',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _branchesLoading
                        ? null
                        : (value) => _setDashboardFilter(
                            _dashboardFilter.copyWithBranch(value),
                          ),
                  ),
                ),
                if (_branchesLoading)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_branchesError != null)
                  TextButton.icon(
                    onPressed: _loadBranches,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Повторить загрузку филиалов'),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ReportingV4Panel(
            role: widget.role,
            filter: _dashboardFilter,
            reloadToken: _dashboardRevision,
            accessSnapshot: widget.accessSnapshot,
          ),
        ),
      ],
    );
  }
}
