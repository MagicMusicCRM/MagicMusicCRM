import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/sales_clients_data_source.dart';

class SalesClientsPanel extends ConsumerStatefulWidget {
  const SalesClientsPanel({
    super.key,
    required this.filter,
    required this.canReadSchoolFinance,
    required this.onOpenEntity,
    this.reloadToken = 0,
  });

  final DashboardFilter filter;
  final bool canReadSchoolFinance;
  final ValueChanged<EntityLink> onOpenEntity;
  final int reloadToken;

  @override
  ConsumerState<SalesClientsPanel> createState() => _SalesClientsPanelState();
}

class _SalesClientsPanelState extends ConsumerState<SalesClientsPanel> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _stalledPreview;
  Map<String, dynamic>? _detail;
  String? _detailSegment;
  String? _detailSourceId;
  String? _detailTitle;
  Object? _error;
  Object? _detailError;
  bool _loading = true;
  bool _detailLoading = false;
  int _operation = 0;

  SalesClientsDataSource get _source =>
      ref.read(salesClientsDataSourceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SalesClientsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.reloadToken != widget.reloadToken) {
      _detailSegment = null;
      _detail = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final operation = ++_operation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _source.loadSummary(widget.filter),
        _source.loadClients(widget.filter, segment: 'stalled', limit: 8),
      ]);
      if (!mounted || operation != _operation) return;
      setState(() {
        _summary = result[0];
        _stalledPreview = result[1];
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

  Future<void> _openSegment(
    String segment,
    String title, {
    String? sourceId,
  }) async {
    final operation = ++_operation;
    setState(() {
      _detailSegment = segment;
      _detailSourceId = sourceId;
      _detailTitle = title;
      _detail = null;
      _detailError = null;
      _detailLoading = true;
    });
    try {
      final result = await _source.loadClients(
        widget.filter,
        segment: segment,
        sourceId: sourceId,
      );
      if (!mounted || operation != _operation) return;
      setState(() {
        _detail = result;
        _detailLoading = false;
      });
    } catch (error) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _detailError = error;
        _detailLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_detailSegment != null) return _buildDetail(context);
    if (_loading && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _summary == null) {
      return _ErrorState(error: _error!, onRetry: _load);
    }
    final summary = _summary ?? const <String, dynamic>{};
    final funnel = _map(summary['funnel']);
    final speed = _map(summary['speed']);
    final sources = _list(summary['sources']);
    final observationDays = _int(summary['observationDays']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          Text(
            'Когорта обращений',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Клиенты, обратившиеся в выбранный период. '
            'Их пробные, покупки и первые фактические оплаты '
            'наблюдаются ${observationDays == 0 ? 90 : observationDays} дней.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColor.text2),
          ),
          const SizedBox(height: AppSpace.lg),
          _FunnelGrid(
            funnel: funnel,
            onOpen: (segment, title) => unawaited(_openSegment(segment, title)),
          ),
          const SizedBox(height: AppSpace.lg),
          _SpeedCard(speed: speed),
          const SizedBox(height: AppSpace.xl),
          _SectionHeader(
            title: 'Требуют следующего действия',
            subtitle:
                'Без первой фактической оплаты в 90-дневном окне; '
                'это рабочий список, а не автоматически присвоенный отказ.',
            actionLabel: 'Показать всех',
            onAction: () =>
                unawaited(_openSegment('stalled', 'Без первой оплаты')),
          ),
          const SizedBox(height: AppSpace.sm),
          _ClientList(
            data: _stalledPreview,
            compact: true,
            onOpenEntity: widget.onOpenEntity,
          ),
          const SizedBox(height: AppSpace.xl),
          _SectionHeader(
            title: 'Эффективность источников',
            subtitle: widget.canReadSchoolFinance
                ? 'Обращения, первые плательщики и сумма именно первых оплат.'
                : 'Обращения и первые плательщики. Денежные суммы скрыты по правам.',
          ),
          const SizedBox(height: AppSpace.sm),
          if (sources.isEmpty)
            const _EmptyCard(message: 'В выбранной когорте нет обращений.')
          else
            ...sources.map(
              (raw) => _SourceCard(
                source: _map(raw),
                showAmount: widget.canReadSchoolFinance,
                onTap: () {
                  final source = _map(raw);
                  final label =
                      source['label']?.toString() ?? 'Источник не указан';
                  unawaited(
                    _openSegment(
                      'inquiries',
                      'Источник: $label',
                      sourceId: source['sourceId']?.toString() ?? 'none',
                    ),
                  );
                },
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            _InlineError(error: _error!, onRetry: _load),
          ],
        ],
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    return Column(
      children: [
        Material(
          color: AppColor.surfaceSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.sm,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Назад к воронке',
                  onPressed: () {
                    _operation++;
                    setState(() {
                      _detailSegment = null;
                      _detailSourceId = null;
                      _detailTitle = null;
                      _detail = null;
                      _detailError = null;
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    _detailTitle ?? 'Клиенты',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: () => unawaited(
                    _openSegment(
                      _detailSegment!,
                      _detailTitle ?? 'Клиенты',
                      sourceId: _detailSourceId,
                    ),
                  ),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _detailLoading
              ? const Center(child: CircularProgressIndicator())
              : _detailError != null
              ? _ErrorState(
                  error: _detailError!,
                  onRetry: () => _openSegment(
                    _detailSegment!,
                    _detailTitle ?? 'Клиенты',
                    sourceId: _detailSourceId,
                  ),
                )
              : _ClientList(data: _detail, onOpenEntity: widget.onOpenEntity),
        ),
      ],
    );
  }
}

class _FunnelGrid extends StatelessWidget {
  const _FunnelGrid({required this.funnel, required this.onOpen});

  final Map<String, dynamic> funnel;
  final void Function(String segment, String title) onOpen;

  @override
  Widget build(BuildContext context) {
    final stages = <({String key, String segment, String title, String hint})>[
      (
        key: 'inquiries',
        segment: 'inquiries',
        title: 'Обращения',
        hint: 'Все клиенты когорты',
      ),
      (
        key: 'trialBooked',
        segment: 'trial_booked',
        title: 'Записаны на пробное',
        hint: 'Есть реальная запись',
      ),
      (
        key: 'trialAttended',
        segment: 'trial_attended',
        title: 'Посетили пробное',
        hint: '${_percent(funnel['conversionToTrial'])} от обращений',
      ),
      (
        key: 'purchases',
        segment: 'purchases',
        title: 'Оформлен абонемент',
        hint: 'Покупка и оплата разделены',
      ),
      (
        key: 'firstPaidSales',
        segment: 'first_paid',
        title: 'Первая оплата',
        hint: '${_percent(funnel['conversionToFirstPayment'])} от обращений',
      ),
      (
        key: 'withoutTrialSales',
        segment: 'without_trial',
        title: 'Оплата без пробного',
        hint: 'Отдельная реальная ветка',
      ),
      (
        key: 'stalled',
        segment: 'stalled',
        title: 'Без первой оплаты',
        hint: 'Нужен следующий шаг',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * AppSpace.md) / columns;
        return Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.md,
          children: [
            for (final stage in stages)
              SizedBox(
                width: width,
                child: _MetricCard(
                  key: ValueKey(
                    'sales-stage-${stage.segment.replaceAll('_', '-')}',
                  ),
                  title: stage.title,
                  value: _int(funnel[stage.key]).toString(),
                  hint: stage.hint,
                  onTap: () => onOpen(stage.segment, stage.title),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.hint,
    required this.onTap,
  });

  final String title;
  final String value;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
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
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpace.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hint,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColor.text2),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColor.text3),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({required this.speed});

  final Map<String, dynamic> speed;

  @override
  Widget build(BuildContext context) {
    final toTrial = _nullableDouble(speed['averageDaysToTrial']);
    final toPayment = _nullableDouble(speed['averageDaysToFirstPayment']);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Wrap(
          spacing: AppSpace.xxl,
          runSpacing: AppSpace.sm,
          children: [
            Text(
              'Скорость пути',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('До посещения пробного: ${_days(toTrial)}'),
            Text('До первой оплаты: ${_days(toPayment)}'),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.showAmount,
    required this.onTap,
  });

  final Map<String, dynamic> source;
  final bool showAmount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount = source['firstPaymentAmountMinor']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source['label']?.toString() ?? 'Источник не указан',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      '${_int(source['inquiries'])} обращений · '
                      '${_int(source['trialAttended'])} пробных · '
                      '${_int(source['firstPaidSales'])} первых оплат · '
                      '${_percent(source['conversionToFirstPayment'])}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColor.text2),
                    ),
                    if (showAmount && amount != null) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Сумма первых оплат: ${_money(amount)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColor.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientList extends StatelessWidget {
  const _ClientList({
    required this.data,
    required this.onOpenEntity,
    this.compact = false,
  });

  final Map<String, dynamic>? data;
  final ValueChanged<EntityLink> onOpenEntity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = _list(data?['items']);
    if (items.isEmpty) {
      return const _EmptyCard(
        message: 'Клиентов, требующих действия, сейчас нет.',
      );
    }
    final children = items.map((raw) {
      final item = _map(raw);
      final id = item['id']?.toString() ?? '';
      final nextTask = item['nextTask'] is Map ? _map(item['nextTask']) : null;
      final clientLink = EntityLink.fromJson(_map(item['entityLink']));
      return Card(
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        child: ListTile(
          key: ValueKey('sales-client-$id'),
          onTap: clientLink.isSupported ? () => onOpenEntity(clientLink) : null,
          title: Text(item['displayName']?.toString() ?? 'Без имени'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item['stageLabel'] ?? 'Без этапа'} · '
                '${item['sourceLabel'] ?? 'Источник не указан'}',
              ),
              Text(
                'Без движения: ${_int(item['waitingDays'])} дн.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (nextTask == null)
                Text(
                  'Следующая задача не назначена',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColor.warning),
                )
              else
                TextButton.icon(
                  onPressed: () {
                    final link = EntityLink.fromJson(
                      _map(nextTask['entityLink']),
                    );
                    if (link.isSupported) onOpenEntity(link);
                  },
                  icon: const Icon(Icons.task_alt, size: 18),
                  label: Text(nextTask['title']?.toString() ?? 'Задача'),
                ),
            ],
          ),
          trailing: const Icon(Icons.open_in_new, size: 20),
          isThreeLine: true,
        ),
      );
    }).toList();
    return compact
        ? Column(children: children)
        : ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: children,
          );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpace.xs),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColor.text2),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Text(message),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColor.danger),
          const SizedBox(width: AppSpace.sm),
          const Expanded(child: Text('Не удалось обновить данные аналитики.')),
          TextButton(
            onPressed: () => unawaited(onRetry()),
            child: const Text('Повторить'),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColor.danger, size: 36),
          const SizedBox(height: AppSpace.sm),
          const Text('Не удалось загрузить аналитику продаж.'),
          const SizedBox(height: AppSpace.sm),
          FilledButton.tonal(
            onPressed: () => unawaited(onRetry()),
            child: const Text('Повторить'),
          ),
        ],
      ),
    ),
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

double? _nullableDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

String _percent(Object? value) {
  final number = _nullableDouble(value) ?? 0;
  return NumberFormat.percentPattern('ru').format(number);
}

String _days(double? value) {
  if (value == null) return 'нет данных';
  return '${NumberFormat('0.#', 'ru').format(value)} дн.';
}

String _money(String minor) {
  final amount = (BigInt.tryParse(minor) ?? BigInt.zero).toDouble() / 100;
  return NumberFormat.currency(
    locale: 'ru',
    symbol: '₽',
    decimalDigits: 0,
  ).format(amount);
}
