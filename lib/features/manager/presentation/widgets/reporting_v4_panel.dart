import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_state_view.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_coordinator.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

export 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart'
    show
        ReportFileOpener,
        ReportFileOpenResult,
        reportFileOpenerProvider,
        validateReportExportBytes;
export 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart'
    show DashboardFilter;

typedef _ReportingAccessInput = ({
  String? accountId,
  int? accessVersion,
  String? snapshotRole,
  String fallbackRole,
  bool canReadStatus,
  bool canReadSchoolFinance,
});

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
  late ReportingController _controller;
  late _ReportingAccessInput _controllerAccess;
  ProviderSubscription<ReportingDataSource>? _dataSourceSubscription;
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
  int _inputGeneration = 0;
  int _drilldownOperation = 0;
  int _exportOperation = 0;

  bool get _canReadStatus =>
      widget.accessSnapshot?.allows('report.status.read') ??
      (widget.role == 'manager' ||
          widget.role == 'director' ||
          widget.role == 'system_admin');

  bool get _canReadSchoolFinance =>
      widget.accessSnapshot?.allows('commerce.school_finance.read') ??
      (widget.role == 'director' || widget.role == 'system_admin');

  DashboardFilter get _filter => widget.filter ?? DashboardFilter.defaults();

  _ReportingAccessInput get _accessInput {
    final snapshot = widget.accessSnapshot;
    return (
      accountId: snapshot?.accountId,
      accessVersion: snapshot?.accessVersion,
      snapshotRole: snapshot?.role,
      fallbackRole: widget.role,
      canReadStatus: _canReadStatus,
      canReadSchoolFinance: _canReadSchoolFinance,
    );
  }

  ReportingDataSource get _dataSource => _controller.dataSource;

  ReportingState get _reporting => _controller.state;

  Map<String, dynamic> get _statusSummary => _reporting.status.data ?? const {};

  Map<String, dynamic> get _lessonSuccess =>
      _reporting.lessons.data ?? const {};

  Map<String, dynamic> get _tasks => _reporting.tasks.data ?? const {};

  Map<String, dynamic>? get _schoolFinance => _reporting.finance.data;

  @override
  void initState() {
    super.initState();
    _controllerAccess = _accessInput;
    _controller = _createController(
      ref.read(reportingDataSourceProvider),
      _controllerAccess,
    );
    _controller.addListener(_onReportingChanged);
    _dataSourceSubscription = ref.listenManual(reportingDataSourceProvider, (
      previous,
      next,
    ) {
      if (_disposed || identical(next, _controller.dataSource)) return;
      _replaceController(next, _accessInput);
      unawaited(_load());
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ReportingV4Panel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final access = _accessInput;
    if (access != _controllerAccess) {
      _replaceController(ref.read(reportingDataSourceProvider), access);
      unawaited(_load());
    } else if (oldWidget.filter != widget.filter ||
        oldWidget.reloadToken != widget.reloadToken) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _dataSourceSubscription?.close();
    _controller.removeListener(_onReportingChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ReportingController _createController(
    ReportingDataSource dataSource,
    _ReportingAccessInput access,
  ) {
    return ReportingController(
      dataSource: dataSource,
      canReadStatus: access.canReadStatus,
      canReadSchoolFinance: access.canReadSchoolFinance,
    );
  }

  void _replaceController(
    ReportingDataSource dataSource,
    _ReportingAccessInput access,
  ) {
    _inputGeneration++;
    _drilldownOperation++;
    _exportOperation++;
    _clearAccessSensitiveState();
    _controller.removeListener(_onReportingChanged);
    _controller.dispose();
    _controllerAccess = access;
    _controller = _createController(dataSource, access);
    _controller.addListener(_onReportingChanged);
  }

  void _clearAccessSensitiveState() {
    _financeDetail = null;
    _drilldownLink = null;
    _drilldown = null;
    _lessonDrilldown = false;
    _drilldownLoading = false;
    _drilldownError = null;
    _exporting = false;
    _exportStatus = null;
    _exportError = null;
  }

  void _onReportingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() => _controller.load(_filter);

  Future<void> _reloadSection(ReportingSectionKey key) =>
      _controller.reloadSection(key, _filter);

  Future<void> _openDrilldown(
    Map<String, dynamic> rawLink, {
    int? expectedCount,
  }) async {
    final inputGeneration = _inputGeneration;
    final operation = ++_drilldownOperation;
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
    setState(() {
      _drilldownLink = link;
      _lessonDrilldown = lessonDrilldown;
      _drilldownLoading = true;
      _drilldownError = null;
    });
    try {
      final response = await _dataSource.loadDrilldown(link, _filter);
      if (!_isCurrentDrilldown(inputGeneration, operation)) return;
      if (expectedCount != null && _int(response['total']) != expectedCount) {
        throw StateError('Количество в карточке и детализации не совпадает.');
      }
      setState(() {
        _drilldown = response;
        _drilldownLoading = false;
      });
    } catch (error) {
      if (!_isCurrentDrilldown(inputGeneration, operation)) return;
      setState(() {
        _drilldownError = error;
        _drilldownLoading = false;
      });
    }
  }

  Future<void> _startExport(String reportKey, String format) async {
    if (_exporting) return;
    final inputGeneration = _inputGeneration;
    final operation = ++_exportOperation;
    setState(() {
      _exporting = true;
      _exportError = null;
      _exportStatus = 'Подготавливаем файл…';
    });
    try {
      final filter = {
        ..._filter.apiFilter,
        ...?_drilldownLink?.optionalFocus?.filter,
      };
      final outcome =
          await ReportExportCoordinator(
            dataSource: _dataSource,
            opener: ref.read(reportFileOpenerProvider),
            isCancelled: () => _isExportCancelled(inputGeneration, operation),
          ).export(
            reportKey: reportKey,
            format: format,
            filter: filter,
            onProgress: (progress) =>
                _updateExportProgress(progress, inputGeneration, operation),
          );
      if (_isExportCancelled(inputGeneration, operation)) return;
      setState(() {
        _exportStatus = outcome.opened
            ? 'Файл открыт: ${outcome.filename}'
            : 'Файл сохранён: ${outcome.path}';
      });
    } catch (error) {
      if (_isExportCancelled(inputGeneration, operation)) return;
      setState(() {
        _exportError = error;
        _exportStatus = null;
      });
    } finally {
      if (!_isExportCancelled(inputGeneration, operation)) {
        setState(() => _exporting = false);
      }
    }
  }

  void _updateExportProgress(
    ReportExportProgress progress,
    int inputGeneration,
    int operation,
  ) {
    if (_isExportCancelled(inputGeneration, operation)) return;
    final status = switch (progress.stage) {
      ReportExportProgressStage.requesting => 'Подготавливаем файл…',
      ReportExportProgressStage.queued =>
        'В очереди: ${progress.rowCount} строк',
      ReportExportProgressStage.polling => _jobStatusLabel(progress.job!),
      ReportExportProgressStage.downloading ||
      ReportExportProgressStage.opening => null,
    };
    if (status != null) setState(() => _exportStatus = status);
  }

  bool _isCurrentDrilldown(int inputGeneration, int operation) =>
      mounted &&
      !_disposed &&
      inputGeneration == _inputGeneration &&
      operation == _drilldownOperation;

  bool _isExportCancelled(int inputGeneration, int operation) =>
      _disposed ||
      inputGeneration != _inputGeneration ||
      operation != _exportOperation;

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
    if (_reporting.loading) {
      return const Center(
        key: ValueKey('reporting-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_reporting.forbidden) {
      return const EntityLinkStateView(
        key: ValueKey('reporting-forbidden'),
        state: EntityRouteState.forbidden,
      );
    }
    if (_financeDetail != null &&
        _canReadSchoolFinance &&
        !_reporting.finance.forbidden) {
      return _buildFinanceDetail(context);
    }
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
              loading: _reporting.lessons.loading,
              error: _reporting.lessons.error,
              onRetry: () => _reloadSection(ReportingSectionKey.lessons),
              child: _lessonCard(),
            ),
            const SizedBox(height: 16),
            _section(
              key: const ValueKey('dashboard-clients-section'),
              title: 'Клиенты и воронка',
              subtitle: 'Статусы с теми же периодом и филиалом',
              loading: _reporting.status.loading,
              error: _reporting.status.error,
              onRetry: () => _reloadSection(ReportingSectionKey.status),
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
              loading: _reporting.tasks.loading,
              error: _reporting.tasks.error,
              onRetry: () => _reloadSection(ReportingSectionKey.tasks),
              child: _taskSummary(),
            ),
            if (_canReadSchoolFinance) ...[
              const SizedBox(height: 16),
              _section(
                key: const ValueKey('dashboard-finance-section'),
                title: 'Финансы школы',
                subtitle: 'Выручка и расходы за выбранный период и филиал',
                loading: _reporting.finance.loading,
                error: _reporting.finance.error,
                onRetry: () => _reloadSection(ReportingSectionKey.finance),
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
                userErrorMessage(
                  _exportError!,
                  fallback: 'Не удалось подготовить файл.',
                ),
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
    if (!_canReadSchoolFinance || _reporting.finance.forbidden) return;
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
        Text('Единая сводка', style: Theme.of(context).textTheme.headlineSmall),
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
          Text(
            userErrorMessage(error, fallback: 'Не удалось загрузить отчёт.'),
            textAlign: TextAlign.center,
          ),
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
