import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/utils/money_format.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_state_view.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_presentation.dart';

typedef ReportingOpenDrilldown =
    void Function(Map<String, dynamic> rawLink, {int? expectedCount});
typedef ReportingExportCallback =
    void Function(String reportKey, String format);

class ReportingSummaryView extends StatelessWidget {
  const ReportingSummaryView({
    super.key,
    required this.state,
    required this.canReadSchoolFinance,
    required this.scrollController,
    required this.onRefresh,
    required this.onRetry,
    required this.onOpenDrilldown,
    required this.onOpenEntity,
    required this.onSelectFinance,
    required this.onExport,
    this.exporting = false,
    this.exportStatus,
    this.exportError,
  });

  final ReportingState state;
  final bool canReadSchoolFinance;
  final ScrollController scrollController;
  final RefreshCallback onRefresh;
  final ValueChanged<ReportingSectionKey> onRetry;
  final ReportingOpenDrilldown onOpenDrilldown;
  final ValueChanged<EntityLink> onOpenEntity;
  final ValueChanged<Map<String, dynamic>> onSelectFinance;
  final ReportingExportCallback onExport;
  final bool exporting;
  final String? exportStatus;
  final Object? exportError;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Center(
        key: ValueKey('reporting-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (state.forbidden) {
      return const EntityLinkStateView(
        key: ValueKey('reporting-forbidden'),
        state: EntityRouteState.forbidden,
      );
    }

    final lessonData = state.lessons.data ?? const {};
    final statusItems = reportingMapList(state.status.data?['items']);
    final taskData = state.tasks.data ?? const {};
    final financeRows = reportingMapList(state.finance.data?['rows']);
    final showFinance = canReadSchoolFinance && !state.finance.forbidden;

    return MagicDesktopScrollbar(
      axis: Axis.vertical,
      controller: scrollController,
      builder: (context, controller) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          key: const ValueKey('reporting-content'),
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            _ReportingHeader(
              canReadSchoolFinance: showFinance,
              exporting: exporting,
              onExport: onExport,
            ),
            const SizedBox(height: 16),
            _ReportingSectionCard(
              key: const ValueKey('dashboard-lessons-section'),
              title: 'Занятия',
              subtitle: 'Успешность за выбранный период и филиал',
              section: state.lessons,
              onRetry: () => onRetry(ReportingSectionKey.lessons),
              child: _LessonSummaryCard(
                data: lessonData,
                onOpenDrilldown: onOpenDrilldown,
              ),
            ),
            const SizedBox(height: 16),
            _ReportingSectionCard(
              key: const ValueKey('dashboard-clients-section'),
              title: 'Клиенты и воронка',
              subtitle: 'Статусы с теми же периодом и филиалом',
              section: state.status,
              onRetry: () => onRetry(ReportingSectionKey.status),
              child: statusItems.isEmpty
                  ? const Text('За выбранный период клиентов нет')
                  : Column(
                      children: statusItems
                          .map(
                            (item) => _StatusSummaryCard(
                              item: item,
                              onOpenDrilldown: onOpenDrilldown,
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 16),
            _ReportingSectionCard(
              key: const ValueKey('dashboard-tasks-section'),
              title: 'Задачи',
              subtitle:
                  'Текущая очередь · период и филиал к этому показателю не применяются',
              section: state.tasks,
              onRetry: () => onRetry(ReportingSectionKey.tasks),
              child: _TaskSummaryCard(data: taskData, onOpen: onOpenEntity),
            ),
            if (showFinance) ...[
              const SizedBox(height: 16),
              _ReportingSectionCard(
                key: const ValueKey('dashboard-finance-section'),
                title: 'Финансы школы',
                subtitle: 'Выручка и расходы за выбранный период и филиал',
                section: state.finance,
                onRetry: () => onRetry(ReportingSectionKey.finance),
                child: financeRows.isEmpty
                    ? const Text('За выбранный период финансовых данных нет')
                    : _FinanceSummaryChart(
                        rows: financeRows,
                        onSelect: onSelectFinance,
                      ),
              ),
            ],
            if (exportStatus != null) ...[
              const SizedBox(height: 12),
              Text(
                exportStatus!,
                key: const ValueKey('report-export-progress'),
              ),
            ],
            if (exportError != null) ...[
              const SizedBox(height: 12),
              Text(
                userErrorMessage(
                  exportError!,
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
}

class ReportingFinanceDetailView extends StatelessWidget {
  const ReportingFinanceDetailView({
    super.key,
    required this.row,
    required this.onBack,
  });

  final Map<String, dynamic> row;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final revenue =
        BigInt.tryParse(row['revenueMinor']?.toString() ?? '') ?? BigInt.zero;
    final expenses =
        BigInt.tryParse(row['expensesMinor']?.toString() ?? '') ?? BigInt.zero;
    final currency = row['currencyCode']?.toString() ?? 'RUB';
    return ListView(
      key: const ValueKey('reporting-finance-detail'),
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
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
          trailing: Text(formatPaymentMinor(revenue, currencyCode: currency)),
        ),
        ListTile(
          leading: const Icon(Icons.trending_down),
          title: const Text('Расходы'),
          trailing: Text(formatPaymentMinor(expenses, currencyCode: currency)),
        ),
        ListTile(
          leading: const Icon(Icons.event_available_outlined),
          title: const Text('Успешно завершённые занятия'),
          trailing: Text('${reportingInt(row['successfulLessons'])}'),
        ),
      ],
    );
  }
}

class _ReportingHeader extends StatelessWidget {
  const _ReportingHeader({
    required this.canReadSchoolFinance,
    required this.exporting,
    required this.onExport,
  });

  final bool canReadSchoolFinance;
  final bool exporting;
  final ReportingExportCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Единая сводка', style: Theme.of(context).textTheme.headlineSmall),
        OutlinedButton.icon(
          onPressed: exporting ? null : () => onExport('client_status', 'xlsx'),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('XLSX'),
        ),
        OutlinedButton.icon(
          onPressed: exporting ? null : () => onExport('client_status', 'csv'),
          icon: const Icon(Icons.download_outlined),
          label: const Text('CSV'),
        ),
        if (canReadSchoolFinance)
          OutlinedButton.icon(
            onPressed: exporting
                ? null
                : () => onExport('school_finance', 'xlsx'),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Финансы XLSX'),
          ),
      ],
    );
  }
}

class _ReportingSectionCard extends StatelessWidget {
  const _ReportingSectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.section,
    required this.onRetry,
    required this.child,
  });

  final String title;
  final String subtitle;
  final ReportingSection<Map<String, dynamic>> section;
  final VoidCallback onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
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
            if (section.loading)
              const Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (section.error != null)
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
}

class _TaskSummaryCard extends StatelessWidget {
  const _TaskSummaryCard({required this.data, required this.onOpen});

  final Map<String, dynamic> data;
  final ValueChanged<EntityLink> onOpen;

  @override
  Widget build(BuildContext context) {
    final counters = reportingStringMap(data['counters']);
    final open = reportingInt(counters['open']);
    final overdue = reportingInt(counters['overdue']);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('Открыто: $open · Просрочено: $overdue'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onOpen(
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
}

class _FinanceSummaryChart extends StatelessWidget {
  const _FinanceSummaryChart({required this.rows, required this.onSelect});

  final List<Map<String, dynamic>> rows;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
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
          onTap: () => onSelect(row),
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
}

class _LessonSummaryCard extends StatelessWidget {
  const _LessonSummaryCard({required this.data, required this.onOpenDrilldown});

  final Map<String, dynamic> data;
  final ReportingOpenDrilldown onOpenDrilldown;

  @override
  Widget build(BuildContext context) {
    final total = reportingInt(data['totalLessons']);
    final success = reportingInt(data['successfulLessons']);
    final rate = ((data['successRate'] as num?) ?? 0) * 100;
    final drilldown = reportingStringMap(data['drilldown']);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available_outlined),
        title: const Text('Успешно завершённые занятия'),
        subtitle: Text('$success из $total'),
        trailing: Text('${rate.toStringAsFixed(1)}%'),
        onTap: drilldown.isEmpty
            ? null
            : () => onOpenDrilldown(drilldown, expectedCount: success),
      ),
    );
  }
}

class _StatusSummaryCard extends StatelessWidget {
  const _StatusSummaryCard({required this.item, required this.onOpenDrilldown});

  final Map<String, dynamic> item;
  final ReportingOpenDrilldown onOpenDrilldown;

  @override
  Widget build(BuildContext context) {
    final rawLink = reportingStringMap(item['drilldown']);
    return Card(
      child: ListTile(
        title: Text(item['label']?.toString() ?? 'Без статуса'),
        subtitle: Text(item['clientType']?.toString() ?? ''),
        trailing: Text('${reportingInt(item['count'])}'),
        onTap: rawLink.isEmpty
            ? null
            : () => onOpenDrilldown(
                rawLink,
                expectedCount: reportingInt(item['count']),
              ),
      ),
    );
  }
}
