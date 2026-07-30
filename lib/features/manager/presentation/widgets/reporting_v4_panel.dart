import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_state_view.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
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
          await getExternalStorageDirectory() ??
          await getTemporaryDirectory();
    } else {
      directory = await getTemporaryDirectory();
    }
    await directory.create(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}$filename';
    await File(path).writeAsBytes(bytes, flush: true);
    await OpenFilex.open(path);
  };
});

class ReportingV4Panel extends ConsumerStatefulWidget {
  const ReportingV4Panel({
    super.key,
    required this.role,
    this.onOpenEntity,
  });

  final String role;
  final ValueChanged<EntityLink>? onOpenEntity;

  @override
  ConsumerState<ReportingV4Panel> createState() => _ReportingV4PanelState();
}

class _ReportingV4PanelState extends ConsumerState<ReportingV4Panel> {
  bool _loading = true;
  bool _forbidden = false;
  Object? _error;
  Map<String, dynamic> _statusSummary = const {};
  Map<String, dynamic> _lessonSuccess = const {};
  Map<String, dynamic>? _schoolFinance;
  EntityLink? _drilldownLink;
  Map<String, dynamic>? _drilldown;
  bool _drilldownLoading = false;
  Object? _drilldownError;
  String? _exportStatus;
  Object? _exportError;
  bool _exporting = false;
  bool _disposed = false;

  bool get _canReadStatus =>
      widget.role == 'manager' ||
      widget.role == 'director' ||
      widget.role == 'system_admin';

  bool get _canReadSchoolFinance =>
      widget.role == 'director' || widget.role == 'system_admin';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _disposed = true;
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
      _loading = true;
      _forbidden = false;
      _error = null;
    });
    try {
      final service = ref.read(magicCrmServiceProvider);
      final results = await Future.wait<Map<String, dynamic>>([
        service.getV4ClientStatusSummary(),
        service.getV4LessonSuccess(),
        if (_canReadSchoolFinance) service.getV4SchoolFinance(),
      ]);
      if (!mounted) return;
      setState(() {
        _statusSummary = results[0];
        _lessonSuccess = results[1];
        _schoolFinance = _canReadSchoolFinance ? results[2] : null;
        _loading = false;
      });
    } on MagicApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _forbidden = error.statusCode == 403;
        _error = error;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openDrilldown(Map<String, dynamic> rawLink) async {
    final link = EntityLink.fromJson(rawLink);
    final resolution = EntityRouteRegistry().resolve(link, _snapshot);
    if (!resolution.canOpen) {
      setState(() {
        _drilldownLink = link;
        _drilldown = null;
        _drilldownError = resolution.state;
      });
      return;
    }
    final filter = link.optionalFocus?.filter ?? const <String, dynamic>{};
    setState(() {
      _drilldownLink = link;
      _drilldownLoading = true;
      _drilldownError = null;
    });
    try {
      final response = await ref
          .read(magicCrmServiceProvider)
          .getV4ClientStatusList(filter: filter);
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
      final filter =
          _drilldownLink?.optionalFocus?.filter ?? const <String, dynamic>{};
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
    if (_error != null) {
      return _ReportingError(error: _error!, onRetry: _load);
    }
    if (_drilldownLink != null) return _buildDrilldown(context);

    final statusItems = _mapList(_statusSummary['items']);
    final lessonTotal = _int(_lessonSuccess['totalLessons']);
    final financeRows = _mapList(_schoolFinance?['rows']);
    final isEmpty =
        statusItems.isEmpty && lessonTotal == 0 && financeRows.isEmpty;
    if (isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const ValueKey('reporting-empty'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.query_stats, size: 40),
            SizedBox(height: 12),
            Center(child: Text('За выбранный период данных нет')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const ValueKey('reporting-content'),
        padding: const EdgeInsets.all(16),
        children: [
          _header(context),
          const SizedBox(height: 16),
          _lessonCard(),
          const SizedBox(height: 16),
          Text(
            'Статусы клиентов',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...statusItems.map(_statusCard),
          if (_canReadSchoolFinance) ...[
            const SizedBox(height: 20),
            Text(
              'Финансы школы',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...financeRows.map(_financeRow),
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
    );
  }

  Widget _header(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Отчёты', style: Theme.of(context).textTheme.headlineSmall),
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
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available_outlined),
        title: const Text('Успешно завершённые занятия'),
        subtitle: Text('$success из $total'),
        trailing: Text('${rate.toStringAsFixed(1)}%'),
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
        onTap: rawLink.isEmpty ? null : () => _openDrilldown(rawLink),
      ),
    );
  }

  Widget _financeRow(Map<String, dynamic> row) {
    final revenue =
        BigInt.tryParse(row['revenueMinor']?.toString() ?? '') ?? BigInt.zero;
    final expenses =
        BigInt.tryParse(row['expensesMinor']?.toString() ?? '') ?? BigInt.zero;
    final formatter = NumberFormat.currency(
      locale: 'ru',
      symbol: '₽',
      decimalDigits: 2,
    );
    return Card(
      child: ListTile(
        title: Text(row['monthStart']?.toString() ?? ''),
        subtitle: Text(
          'Выручка ${formatter.format(revenue.toDouble() / 100)} · '
          'Расходы ${formatter.format(expenses.toDouble() / 100)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final link = EntityLink.fromJson(_stringMap(row['link']));
          widget.onOpenEntity?.call(link);
        },
      ),
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
                _drilldownError = null;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('К отчёту'),
          ),
        ),
        Text(
          'Клиенты: ${_int(_drilldown?['total'])}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('Список пуст')),
          ),
        ...items.map((item) {
          final link = EntityLink.fromJson(_stringMap(item['entityLink']));
          return ListTile(
            title: Text(item['displayName']?.toString() ?? 'Без имени'),
            subtitle: Text(item['statusLabel']?.toString() ?? ''),
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
    final route = EntityRouteRegistry().resolve(link, _snapshot);
    if (route.canOpen) context.push(route.location!);
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
