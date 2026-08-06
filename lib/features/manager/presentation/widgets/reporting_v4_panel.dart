import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_state_view.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

typedef ReportFileOpener =
    Future<void> Function(List<int> bytes, String filename);

final reportFileOpenerProvider = Provider<ReportFileOpener>((ref) {
  return (bytes, filename) async {
    Directory directory;
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      directory = downloads;
    } else if (Platform.isAndroid) {
      directory =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    } else {
      directory = await getTemporaryDirectory();
    }
    await directory.create(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}$filename';
    await File(path).writeAsBytes(bytes, flush: true);
    await OpenFilex.open(path);
  };
});

@immutable
class DashboardFilter {
  const DashboardFilter({required this.from, required this.to, this.branchId});

  factory DashboardFilter.defaults() {
    final now = DateTime.now();
    return DashboardFilter(
      from: DateTime(now.year, now.month - 5, 1),
      to: DateTime(now.year, now.month, now.day),
    );
  }

  factory DashboardFilter.fromContext(
    ContextViewState? state,
    Map<String, dynamic>? directFilter,
  ) {
    final fallback = DashboardFilter.defaults();
    final raw = <String, dynamic>{...?state?.filters, ...?directFilter};
    final from = DateTime.tryParse(
      raw['dashboardFrom']?.toString() ?? raw['from']?.toString() ?? '',
    );
    final to = DateTime.tryParse(
      raw['dashboardTo']?.toString() ?? raw['to']?.toString() ?? '',
    );
    final branch = raw['branchId']?.toString().trim();
    if (from == null || to == null || from.isAfter(to)) return fallback;
    return DashboardFilter(
      from: DateTime(from.year, from.month, from.day),
      to: DateTime(to.year, to.month, to.day),
      branchId: branch == null || branch.isEmpty ? null : branch,
    );
  }

  final DateTime from;
  final DateTime to;
  final String? branchId;

  Map<String, dynamic> get apiFilter => {
    'from': from.toUtc().toIso8601String(),
    'to': to.add(const Duration(days: 1)).toUtc().toIso8601String(),
    if (branchId != null) 'branchId': branchId,
  };

  ContextViewState toContextViewState() => ContextViewState(
    filters: {
      'dashboardFrom': from.toIso8601String(),
      'dashboardTo': to.toIso8601String(),
      if (branchId != null) 'branchId': branchId,
    },
  );

  DashboardFilter copyWithRange(DateTimeRange range) => DashboardFilter(
    from: DateTime(range.start.year, range.start.month, range.start.day),
    to: DateTime(range.end.year, range.end.month, range.end.day),
    branchId: branchId,
  );

  DashboardFilter copyWithBranch(String? value) =>
      DashboardFilter(from: from, to: to, branchId: value);

  @override
  bool operator ==(Object other) =>
      other is DashboardFilter &&
      other.from == from &&
      other.to == to &&
      other.branchId == branchId;

  @override
  int get hashCode => Object.hash(from, to, branchId);
}

class ReportingV4Panel extends ConsumerStatefulWidget {
  const ReportingV4Panel({
    super.key,
    required this.role,
    this.onOpenEntity,
    this.filter,
    this.reloadToken = 0,
    this.accessSnapshot,
  });

  final String role;
  final ValueChanged<EntityLink>? onOpenEntity;
  final DashboardFilter? filter;
  final int reloadToken;
  final CapabilitySnapshot? accessSnapshot;

  @override
  ConsumerState<ReportingV4Panel> createState() => _ReportingV4PanelState();
}

class _ReportingV4PanelState extends ConsumerState<ReportingV4Panel> {
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _forbidden = false;
  bool _statusLoading = true;
  bool _lessonLoading = true;
  bool _tasksLoading = true;
  bool _financeLoading = true;
  Object? _statusError;
  Object? _lessonError;
  Object? _tasksError;
  Object? _financeError;
  Map<String, dynamic> _statusSummary = const {};
  Map<String, dynamic> _lessonSuccess = const {};
  Map<String, dynamic> _tasks = const {};
  Map<String, dynamic>? _schoolFinance;
  EntityLink? _drilldownLink;
  Map<String, dynamic>? _drilldown;
  bool _lessonDrilldown = false;
  Map<String, dynamic>? _financeDetail;
  bool _drilldownLoading = false;
  Object? _drilldownError;
  String? _exportStatus;
  Object? _exportError;
  bool _exporting = false;
  bool _disposed = false;

  bool get _canReadStatus =>
      widget.accessSnapshot?.allows('report.status.read') ??
      (widget.role == 'manager' ||
          widget.role == 'director' ||
          widget.role == 'system_admin');

  bool get _canReadSchoolFinance =>
      widget.accessSnapshot?.allows('commerce.school_finance.read') ??
      (widget.role == 'director' || widget.role == 'system_admin');

  DashboardFilter get _filter => widget.filter ?? DashboardFilter.defaults();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ReportingV4Panel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.reloadToken != widget.reloadToken ||
        oldWidget.role != widget.role ||
        oldWidget.accessSnapshot?.accessVersion !=
            widget.accessSnapshot?.accessVersion) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_canReadStatus) {
      setState(() {
        _forbidden = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = false;
      _forbidden = false;
      _statusLoading = true;
      _lessonLoading = true;
      _tasksLoading = true;
      _financeLoading = _canReadSchoolFinance;
      _statusError = null;
      _lessonError = null;
      _tasksError = null;
      _financeError = null;
    });
    await Future.wait([
      _loadStatus(),
      _loadLessons(),
      _loadTasks(),
      if (_canReadSchoolFinance) _loadFinance(),
    ]);
  }

  Future<void> _loadStatus() {
    final filter = _filter.apiFilter;
    return _loadSection(
      () => ref
          .read(magicCrmServiceProvider)
          .getV4ClientStatusSummary(
            branchId: filter['branchId']?.toString(),
            from: filter['from']?.toString(),
            to: filter['to']?.toString(),
          ),
      (value) => _statusSummary = value,
      (value) => _statusError = value,
      (value) => _statusLoading = value,
    );
  }

  Future<void> _loadLessons() {
    final filter = _filter.apiFilter;
    return _loadSection(
      () => ref
          .read(magicCrmServiceProvider)
          .getV4LessonSuccess(
            branchId: filter['branchId']?.toString(),
            from: filter['from']?.toString(),
            to: filter['to']?.toString(),
          ),
      (value) => _lessonSuccess = value,
      (value) => _lessonError = value,
      (value) => _lessonLoading = value,
    );
  }

  Future<void> _loadTasks() => _loadSection(
    () => ref
        .read(magicCrmServiceProvider)
        .listSharedTasks(state: 'open', limit: 1),
    (value) => _tasks = value,
    (value) => _tasksError = value,
    (value) => _tasksLoading = value,
  );

  Future<void> _loadFinance() {
    final filter = _filter.apiFilter;
    return _loadSection(
      () => ref
          .read(magicCrmServiceProvider)
          .getV4SchoolFinance(
            branchId: filter['branchId']?.toString(),
            from: filter['from']?.toString(),
            to: filter['to']?.toString(),
          ),
      (value) => _schoolFinance = value,
      (value) => _financeError = value,
      (value) => _financeLoading = value,
    );
  }

  Future<void> _loadSection(
    Future<Map<String, dynamic>> Function() load,
    void Function(Map<String, dynamic>) apply,
    void Function(Object?) setError,
    void Function(bool) setLoading,
  ) async {
    if (mounted) {
      setState(() {
        setError(null);
        setLoading(true);
      });
    }
    try {
      final value = await load();
      if (!mounted) return;
      setState(() {
        apply(value);
        setError(null);
        setLoading(false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        setError(error);
        setLoading(false);
      });
    }
  }

  Future<void> _openDrilldown(
    Map<String, dynamic> rawLink, {
    int? expectedCount,
  }) async {
    final link = EntityLink.fromJson(rawLink);
    final lessonDrilldown = link.rawEntityType == 'lesson_list';
    final resolution = EntityRouteRegistry().resolve(link, _snapshot);
    if (!resolution.canOpen) {
      setState(() {
        _drilldownLink = link;
        _drilldown = null;
        _drilldownError = resolution.state;
      });
      return;
    }
    final filter = {..._filter.apiFilter, ...?link.optionalFocus?.filter};
    setState(() {
      _drilldownLink = link;
      _lessonDrilldown = lessonDrilldown;
      _drilldownLoading = true;
      _drilldownError = null;
    });
    try {
      final service = ref.read(magicCrmServiceProvider);
      final response = lessonDrilldown
          ? await service.getV4LessonSuccessList(filter: filter)
          : await service.getV4ClientStatusList(filter: filter);
      if (expectedCount != null && _int(response['total']) != expectedCount) {
        throw StateError('Количество в карточке и детализации не совпадает.');
      }
      if (!mounted) return;
      setState(() {
        _drilldown = response;
        _drilldownLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _drilldownError = error;
        _drilldownLoading = false;
      });
    }
  }

  Future<void> _startExport(String reportKey, String format) async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportError = null;
      _exportStatus = 'Подготавливаем файл…';
    });
    try {
      final service = ref.read(magicCrmServiceProvider);
      final filter = {
        ..._filter.apiFilter,
        ...?_drilldownLink?.optionalFocus?.filter,
      };
      final requested = await service.requestV4ReportExport(
        reportKey: reportKey,
        format: format,
        filter: filter,
      );
      if (!requested.isAsync) {
        await ref.read(reportFileOpenerProvider)(
          requested.bytes!,
          requested.filename!,
        );
        if (!mounted) return;
        setState(() => _exportStatus = 'Файл готов');
        return;
      }

      final jobId = requested.jobId!;
      if (mounted) {
        setState(() {
          _exportStatus = 'В очереди: ${requested.rowCount} строк';
        });
      }
      for (var attempt = 0; attempt < 120 && !_disposed; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final job = await service.getV4ReportExportJob(jobId);
        if (_disposed) return;
        if (mounted) {
          setState(() => _exportStatus = _jobStatusLabel(job));
        }
        if (job.status == 'failed' || job.status == 'expired') {
          throw StateError(job.errorCode ?? 'Экспорт недоступен');
        }
        if (job.downloadReady) {
          final bytes = await service.downloadV4ReportExport(jobId);
          await ref.read(reportFileOpenerProvider)(
            bytes,
            job.filename ?? 'report.$format',
          );
          if (mounted) setState(() => _exportStatus = 'Файл готов');
          return;
        }
      }
      throw TimeoutException('Экспорт занимает слишком много времени.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _exportError = error;
        _exportStatus = null;
      });
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  CapabilitySnapshot get _snapshot {
    if (widget.accessSnapshot != null) return widget.accessSnapshot!;
    final serverSnapshot = ref.read(capabilitySnapshotProvider).value;
    if (serverSnapshot != null) return serverSnapshot;
    return CapabilitySnapshot(
      accountId: 'active',
      role: widget.role,
      accessVersion: 1,
      capabilities: {
        if (_canReadStatus) 'report.status.read',
        if (_canReadSchoolFinance) 'commerce.school_finance.read',
        if (_canReadStatus) 'crm.client.read.basic',
      },
      scopes: const {},
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        key: ValueKey('reporting-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_forbidden) {
      return const EntityLinkStateView(
        key: ValueKey('reporting-forbidden'),
        state: EntityRouteState.forbidden,
      );
    }
    if (_financeDetail != null) return _buildFinanceDetail(context);
    if (_drilldownLink != null) return _buildDrilldown(context);

    final statusItems = _mapList(_statusSummary['items']);
    final financeRows = _mapList(_schoolFinance?['rows']);

    return MagicDesktopScrollbar(
      axis: Axis.vertical,
      controller: _scrollController,
      builder: (context, controller) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const ValueKey('reporting-content'),
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            _header(context),
            const SizedBox(height: 16),
            _section(
              key: const ValueKey('dashboard-lessons-section'),
              title: 'Занятия',
              subtitle: 'Успешность за выбранный период и филиал',
              loading: _lessonLoading,
              error: _lessonError,
              onRetry: _loadLessons,
              child: _lessonCard(),
            ),
            const SizedBox(height: 16),
            _section(
              key: const ValueKey('dashboard-clients-section'),
              title: 'Клиенты и воронка',
              subtitle: 'Статусы с теми же периодом и филиалом',
              loading: _statusLoading,
              error: _statusError,
              onRetry: _loadStatus,
              child: statusItems.isEmpty
                  ? const Text('За выбранный период клиентов нет')
                  : Column(children: statusItems.map(_statusCard).toList()),
            ),
            const SizedBox(height: 16),
            _section(
              key: const ValueKey('dashboard-tasks-section'),
              title: 'Задачи',
              subtitle:
                  'Текущая очередь · период и филиал к этому показателю не применяются',
              loading: _tasksLoading,
              error: _tasksError,
              onRetry: _loadTasks,
              child: _taskSummary(),
            ),
            if (_canReadSchoolFinance) ...[
              const SizedBox(height: 16),
              _section(
                key: const ValueKey('dashboard-finance-section'),
                title: 'Финансы школы',
                subtitle: 'Выручка и расходы за выбранный период и филиал',
                loading: _financeLoading,
                error: _financeError,
                onRetry: _loadFinance,
                child: financeRows.isEmpty
                    ? const Text('За выбранный период финансовых данных нет')
                    : _financeChart(financeRows),
              ),
            ],
            if (_exportStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                _exportStatus!,
                key: const ValueKey('report-export-progress'),
              ),
            ],
            if (_exportError != null) ...[
              const SizedBox(height: 12),
              Text(
                'Ошибка экспорта: $_exportError',
                key: const ValueKey('report-export-error'),
                style: const TextStyle(color: AppColor.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section({
    required Key key,
    required String title,
    required String subtitle,
    required bool loading,
    required Object? error,
    required Future<void> Function() onRetry,
    required Widget child,
  }) {
    return Card(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (error != null)
              Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColor.danger),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Не удалось загрузить раздел')),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Повторить'),
                  ),
                ],
              )
            else
              child,
          ],
        ),
      ),
    );
  }

  Widget _taskSummary() {
    final counters = _stringMap(_tasks['counters']);
    final open = _int(counters['open']);
    final overdue = _int(counters['overdue']);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('Открыто: $open · Просрочено: $overdue'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openEntity(
        EntityLink.typed(
          entityType: EntityLinkType.task,
          entityId: '__section__',
          optionalFocus: EntityLinkFocus(
            focus: 'section',
            filter: const {'state': 'open'},
          ),
        ),
      ),
    );
  }

  Widget _financeChart(List<Map<String, dynamic>> rows) {
    final max = rows
        .map((row) {
          final revenue =
              BigInt.tryParse(row['revenueMinor']?.toString() ?? '') ??
              BigInt.zero;
          final expenses =
              BigInt.tryParse(row['expensesMinor']?.toString() ?? '') ??
              BigInt.zero;
          return revenue > expenses ? revenue : expenses;
        })
        .fold<BigInt>(BigInt.one, (value, item) => item > value ? item : value);
    return Column(
      children: rows.map((row) {
        final revenue =
            BigInt.tryParse(row['revenueMinor']?.toString() ?? '') ??
            BigInt.zero;
        final expenses =
            BigInt.tryParse(row['expensesMinor']?.toString() ?? '') ??
            BigInt.zero;
        double ratio(BigInt value) => value.toDouble() / max.toDouble();
        return InkWell(
          onTap: () => _openFinanceRow(row),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(row['monthStart']?.toString() ?? '')),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                const SizedBox(height: 6),
                Semantics(
                  label: 'Выручка $revenue копеек',
                  child: LinearProgressIndicator(
                    value: ratio(revenue),
                    minHeight: 8,
                    color: AppColor.success,
                  ),
                ),
                const SizedBox(height: 4),
                Semantics(
                  label: 'Расходы $expenses копеек',
                  child: LinearProgressIndicator(
                    value: ratio(expenses),
                    minHeight: 8,
                    color: AppColor.danger,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _openFinanceRow(Map<String, dynamic> row) {
    final link = EntityLink.fromJson(_stringMap(row['link']));
    if (widget.onOpenEntity != null) {
      widget.onOpenEntity!(link);
    } else {
      setState(() => _financeDetail = row);
    }
  }

  Widget _header(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Единый dashboard',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        OutlinedButton.icon(
          onPressed: _exporting
              ? null
              : () => _startExport('client_status', 'xlsx'),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('XLSX'),
        ),
        OutlinedButton.icon(
          onPressed: _exporting
              ? null
              : () => _startExport('client_status', 'csv'),
          icon: const Icon(Icons.download_outlined),
          label: const Text('CSV'),
        ),
        if (_canReadSchoolFinance)
          OutlinedButton.icon(
            onPressed: _exporting
                ? null
                : () => _startExport('school_finance', 'xlsx'),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Финансы XLSX'),
          ),
      ],
    );
  }

  Widget _lessonCard() {
    final total = _int(_lessonSuccess['totalLessons']);
    final success = _int(_lessonSuccess['successfulLessons']);
    final rate = ((_lessonSuccess['successRate'] as num?) ?? 0) * 100;
    final drilldown = _stringMap(_lessonSuccess['drilldown']);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available_outlined),
        title: const Text('Успешно завершённые занятия'),
        subtitle: Text('$success из $total'),
        trailing: Text('${rate.toStringAsFixed(1)}%'),
        onTap: drilldown.isEmpty
            ? null
            : () => _openDrilldown(drilldown, expectedCount: success),
      ),
    );
  }

  Widget _statusCard(Map<String, dynamic> item) {
    final rawLink = _stringMap(item['drilldown']);
    return Card(
      child: ListTile(
        title: Text(item['label']?.toString() ?? 'Без статуса'),
        subtitle: Text(item['clientType']?.toString() ?? ''),
        trailing: Text('${_int(item['count'])}'),
        onTap: rawLink.isEmpty
            ? null
            : () => _openDrilldown(rawLink, expectedCount: _int(item['count'])),
      ),
    );
  }

  Widget _buildFinanceDetail(BuildContext context) {
    final row = _financeDetail!;
    final revenue =
        BigInt.tryParse(row['revenueMinor']?.toString() ?? '') ?? BigInt.zero;
    final expenses =
        BigInt.tryParse(row['expensesMinor']?.toString() ?? '') ?? BigInt.zero;
    final formatter = NumberFormat.currency(
      locale: 'ru',
      symbol: '₽',
      decimalDigits: 2,
    );
    return ListView(
      key: const ValueKey('reporting-finance-detail'),
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _financeDetail = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('К отчёту'),
          ),
        ),
        Text(
          'Финансы за ${row['monthStart'] ?? ''}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.trending_up),
          title: const Text('Фактическая выручка'),
          trailing: Text(formatter.format(revenue.toDouble() / 100)),
        ),
        ListTile(
          leading: const Icon(Icons.trending_down),
          title: const Text('Расходы'),
          trailing: Text(formatter.format(expenses.toDouble() / 100)),
        ),
        ListTile(
          leading: const Icon(Icons.event_available_outlined),
          title: const Text('Успешно завершённые занятия'),
          trailing: Text('${_int(row['successfulLessons'])}'),
        ),
      ],
    );
  }

  Widget _buildDrilldown(BuildContext context) {
    if (_drilldownLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_drilldownError is EntityRouteState) {
      return EntityLinkStateView(state: _drilldownError! as EntityRouteState);
    }
    if (_drilldownError != null) {
      return _ReportingError(
        error: _drilldownError!,
        onRetry: () => _openDrilldown(_drilldownLink!.toJson()),
      );
    }
    final items = _mapList(_drilldown?['items']);
    return ListView(
      key: const ValueKey('reporting-drilldown'),
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _drilldownLink = null;
                _drilldown = null;
                _lessonDrilldown = false;
                _drilldownError = null;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('К отчёту'),
          ),
        ),
        Text(
          '${_lessonDrilldown ? 'Занятия' : 'Клиенты'}: '
          '${_int(_drilldown?['total'])}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('Список пуст')),
          ),
        ...items.map((item) {
          final parsed = EntityLink.fromJson(_stringMap(item['entityLink']));
          final displayName = item['displayName']?.toString().trim() ?? '';
          final link = displayName.isEmpty
              ? parsed
              : parsed.withPresentation(
                  EntityPresentationReference(primary: displayName),
                );
          return ListTile(
            title: Text(item['displayName']?.toString() ?? 'Без имени'),
            subtitle: Text(
              (_lessonDrilldown ? item['subtitle'] : item['statusLabel'])
                      ?.toString() ??
                  '',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openEntity(link),
          );
        }),
      ],
    );
  }

  void _openEntity(EntityLink link) {
    if (widget.onOpenEntity != null) {
      widget.onOpenEntity!(link);
      return;
    }
    unawaited(navigateEntityLink(context, _snapshot, link));
  }
}

class _ReportingError extends StatelessWidget {
  const _ReportingError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('reporting-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 36),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

String _jobStatusLabel(V4ReportExportJob job) {
  return switch (job.status) {
    'queued' => 'Экспорт в очереди: ${job.rowCount} строк',
    'processing' => 'Формируем файл: ${job.rowCount} строк',
    'ready' => 'Файл готов',
    'expired' => 'Срок хранения файла истёк',
    _ => 'Не удалось сформировать файл',
  };
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
