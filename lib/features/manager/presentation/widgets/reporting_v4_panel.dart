import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_coordinator.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_drilldown_view.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_presentation.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_summary_view.dart';

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
        _drilldownError = _reportingLinkState(resolution.state);
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
      if (expectedCount != null &&
          reportingInt(response['total']) != expectedCount) {
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
    final summary = ReportingSummaryView(
      state: _reporting,
      canReadSchoolFinance: _canReadSchoolFinance,
      scrollController: _scrollController,
      exporting: _exporting,
      exportStatus: _exportStatus,
      exportError: _exportError,
      onRefresh: _load,
      onRetry: (key) => unawaited(_reloadSection(key)),
      onOpenDrilldown: (rawLink, {expectedCount}) =>
          unawaited(_openDrilldown(rawLink, expectedCount: expectedCount)),
      onOpenEntity: _openEntity,
      onSelectFinance: _openFinanceRow,
      onExport: (reportKey, format) =>
          unawaited(_startExport(reportKey, format)),
    );
    if (_reporting.loading || _reporting.forbidden) return summary;
    if (_financeDetail != null &&
        _canReadSchoolFinance &&
        !_reporting.finance.forbidden) {
      return ReportingFinanceDetailView(
        row: _financeDetail!,
        onBack: () => setState(() => _financeDetail = null),
      );
    }
    if (_drilldownLink != null) {
      return ReportingDrilldownView(
        loading: _drilldownLoading,
        error: _drilldownError,
        data: _drilldown,
        lessonDrilldown: _lessonDrilldown,
        onRetry: () => unawaited(_openDrilldown(_drilldownLink!.toJson())),
        onBack: () {
          setState(() {
            _drilldownLink = null;
            _drilldown = null;
            _lessonDrilldown = false;
            _drilldownError = null;
          });
        },
        onOpenEntity: _openEntity,
      );
    }
    return summary;
  }

  void _openFinanceRow(Map<String, dynamic> row) {
    if (!_canReadSchoolFinance || _reporting.finance.forbidden) return;
    final link = EntityLink.fromJson(reportingStringMap(row['link']));
    if (widget.onOpenEntity != null) {
      widget.onOpenEntity!(link);
    } else {
      setState(() => _financeDetail = row);
    }
  }

  void _openEntity(EntityLink link) {
    if (widget.onOpenEntity != null) {
      widget.onOpenEntity!(link);
      return;
    }
    unawaited(navigateEntityLink(context, _snapshot, link));
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

ReportingLinkState _reportingLinkState(EntityRouteState state) =>
    switch (state) {
      EntityRouteState.resolved => ReportingLinkState.resolved,
      EntityRouteState.forbidden => ReportingLinkState.forbidden,
      EntityRouteState.archived => ReportingLinkState.archived,
      EntityRouteState.deleted => ReportingLinkState.deleted,
      EntityRouteState.unknown => ReportingLinkState.unknown,
    };
