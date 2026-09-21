import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/utils/money_format.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/finance_debt_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

class FinanceDebtPanel extends ConsumerStatefulWidget {
  const FinanceDebtPanel({
    super.key,
    required this.filter,
    required this.onOpenEntity,
    this.reloadToken = 0,
  });

  final DashboardFilter filter;
  final ValueChanged<EntityLink> onOpenEntity;
  final int reloadToken;

  @override
  ConsumerState<FinanceDebtPanel> createState() => _FinanceDebtPanelState();
}

class _FinanceDebtPanelState extends ConsumerState<FinanceDebtPanel> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _detail;
  String? _segment;
  String? _detailTitle;
  Object? _error;
  bool _loading = true;
  int _operation = 0;

  FinanceDebtDataSource get _source => ref.read(financeDebtDataSourceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSummary());
  }

  @override
  void didUpdateWidget(covariant FinanceDebtPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.reloadToken != widget.reloadToken) {
      _segment = null;
      _detail = null;
      unawaited(_loadSummary());
    }
  }

  Future<void> _loadSummary() async {
    final operation = ++_operation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _source.loadSummary(widget.filter);
      if (!mounted || operation != _operation) return;
      setState(() {
        _summary = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openSegment(String segment, String title) async {
    final operation = ++_operation;
    setState(() {
      _segment = segment;
      _detailTitle = title;
      _detail = null;
      _loading = true;
      _error = null;
    });
    try {
      final result = await _source.loadItems(widget.filter, segment: segment);
      if (!mounted || operation != _operation) return;
      setState(() {
        _detail = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_segment != null) return _buildDetail();
    if (_loading && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _summary == null) return _errorState();
    final summary = _summary ?? const <String, dynamic>{};
    final currency = summary['currencyCode']?.toString() ?? 'RUB';
    return RefreshIndicator(
      onRefresh: _loadSummary,
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          Text(
            'Деньги и задолженность',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpace.xs),
          const Text(
            'Фактические поступления отделены от обязательств, реальной '
            'просрочки и прогнозов рассрочки.',
            style: TextStyle(color: AppColor.text2),
          ),
          const SizedBox(height: AppSpace.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * AppSpace.md) /
                  columns;
              final metrics = [
                (
                  key: 'receipts',
                  title: 'Получено за период',
                  value: _money(summary['receiptsMinor'], currency),
                  hint: 'Оплаты минус возвраты и корректировки',
                  segment: null,
                ),
                (
                  key: 'remaining',
                  title: 'Осталось по покупкам',
                  value: _money(summary['remainingMinor'], currency),
                  hint: 'Обязательство минус фактическая оплата',
                  segment: 'remaining',
                ),
                (
                  key: 'overdue',
                  title: 'Реальная просрочка',
                  value: _money(summary['overdueMinor'], currency),
                  hint: '${_integer(summary['overdueClients'])} клиентов',
                  segment: 'overdue',
                ),
                (
                  key: 'forecast',
                  title: 'Прогноз следующего взноса',
                  value: _money(summary['forecastMinor'], currency),
                  hint: 'Не считается долгом до фактического срока',
                  segment: 'forecast',
                ),
                (
                  key: 'paid-unused',
                  title: 'Оплачено, не использовано',
                  value: '${summary['paidUnusedUnits'] ?? '0'} ед.',
                  hint: 'Оплачено − израсходовано − зарезервировано',
                  segment: 'paid_unused',
                ),
              ];
              return Wrap(
                spacing: AppSpace.md,
                runSpacing: AppSpace.md,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: _FinanceMetricCard(
                        key: Key('finance-metric-${metric.key}'),
                        title: metric.title,
                        value: metric.value,
                        hint: metric.hint,
                        onTap: metric.segment == null
                            ? null
                            : () => unawaited(
                                _openSegment(metric.segment!, metric.title),
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.lg),
            _errorState(compact: true),
          ],
        ],
      ),
    );
  }

  Widget _buildDetail() {
    final items = (_detail?['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return Column(
      children: [
        Material(
          color: AppColor.surfaceSoft,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Назад к показателям',
                  onPressed: () => setState(() {
                    _operation++;
                    _segment = null;
                    _detail = null;
                    _error = null;
                    _loading = false;
                  }),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    _detailTitle ?? 'Обязательства',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: () => unawaited(
                    _openSegment(_segment!, _detailTitle ?? 'Обязательства'),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _errorState()
              : items.isEmpty
              ? const Center(child: Text('Записей по этому показателю нет'))
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpace.sm),
                  itemBuilder: (context, index) => _FinanceDebtRow(
                    item: items[index],
                    onOpenEntity: widget.onOpenEntity,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _errorState({bool compact = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Не удалось загрузить финансовую аналитику'),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton(
            onPressed: _segment == null
                ? _loadSummary
                : () =>
                      _openSegment(_segment!, _detailTitle ?? 'Обязательства'),
            child: const Text('Повторить'),
          ),
        ],
      ),
    ),
  );
}

class _FinanceMetricCard extends StatelessWidget {
  const _FinanceMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.hint,
    this.onTap,
  });

  final String title;
  final String value;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpace.sm),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpace.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    hint,
                    style: const TextStyle(color: AppColor.text2),
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColor.text3,
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _FinanceDebtRow extends StatelessWidget {
  const _FinanceDebtRow({required this.item, required this.onOpenEntity});

  final Map<String, dynamic> item;
  final ValueChanged<EntityLink> onOpenEntity;

  @override
  Widget build(BuildContext context) {
    final id = item['subscriptionId']?.toString() ?? '';
    final due = DateTime.tryParse(item['nextDueAt']?.toString() ?? '');
    final forecast = item['nextDueIsForecast'] == true;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['displayName']?.toString() ?? 'Клиент',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(item['packageName']?.toString() ?? 'Абонемент'),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.lg,
              runSpacing: AppSpace.xs,
              children: [
                Text('Осталось: ${_money(item['remainingMinor'], 'RUB')}'),
                Text('Просрочено: ${_money(item['overdueMinor'], 'RUB')}'),
                Text('Прогноз: ${_money(item['forecastMinor'], 'RUB')}'),
                Text('Не использовано: ${item['paidUnusedUnits'] ?? '0'} ед.'),
              ],
            ),
            if (due != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                forecast
                    ? 'Прогноз срока: ${DateFormat('dd.MM.yyyy').format(due.toLocal())}'
                    : 'Это фактический срок: ${DateFormat('dd.MM.yyyy').format(due.toLocal())}',
                style: TextStyle(
                  color: forecast ? AppColor.warning : AppColor.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                _linkButton(
                  key: Key('finance-client-$id'),
                  label: 'Карточка клиента',
                  raw: item['clientLink'],
                ),
                _linkButton(
                  key: Key('finance-subscription-$id'),
                  label: 'Абонемент',
                  raw: item['subscriptionLink'],
                ),
                if (item['paymentLink'] != null)
                  _linkButton(
                    key: Key('finance-payment-$id'),
                    label: 'Последняя оплата',
                    raw: item['paymentLink'],
                  ),
                if (item['nextTask'] is Map)
                  _linkButton(
                    key: Key('finance-task-$id'),
                    label:
                        (item['nextTask'] as Map)['title']?.toString() ??
                        'Следующая задача',
                    raw: (item['nextTask'] as Map)['entityLink'],
                  ),
                if (item['owner'] is Map)
                  _linkButton(
                    key: Key('finance-owner-$id'),
                    label:
                        (item['owner'] as Map)['name']?.toString() ??
                        'Ответственный',
                    raw: (item['owner'] as Map)['entityLink'],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkButton({
    required Key key,
    required String label,
    required Object? raw,
  }) {
    final link = raw is Map
        ? EntityLink.fromJson(Map<String, dynamic>.from(raw))
        : null;
    return TextButton.icon(
      key: key,
      onPressed: link?.isSupported == true ? () => onOpenEntity(link!) : null,
      icon: const Icon(Icons.open_in_new_rounded, size: 16),
      label: Text(label),
    );
  }
}

String _money(Object? value, String currency) {
  final minor = BigInt.tryParse(value?.toString() ?? '') ?? BigInt.zero;
  return formatPaymentMinor(minor, currencyCode: currency);
}

int _integer(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
