import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

class ChatSlaPanel extends ConsumerStatefulWidget {
  const ChatSlaPanel({
    super.key,
    required this.filter,
    required this.onOpenEntity,
    this.reloadToken = 0,
  });

  final DashboardFilter filter;
  final ValueChanged<EntityLink> onOpenEntity;
  final int reloadToken;

  @override
  ConsumerState<ChatSlaPanel> createState() => _ChatSlaPanelState();
}

class _ChatSlaPanelState extends ConsumerState<ChatSlaPanel> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = true;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ChatSlaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.reloadToken != widget.reloadToken) {
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
      final result = await ref
          .read(magicCrmServiceProvider)
          .getAnalyticsChatSla(
            from: widget.filter.from.toUtc().toIso8601String(),
            to: widget.filter.to
                .add(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
            branchId: widget.filter.branchId,
          );
      if (!mounted || operation != _operation) return;
      setState(() {
        _data = result;
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
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить SLA обращений.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final data = _data ?? const <String, dynamic>{};
    final slow = data['slowChats'] is List
        ? (data['slowChats'] as List).whereType<Map<String, dynamic>>().toList(
            growable: false,
          )
        : const <Map<String, dynamic>>[];
    final inbound = _number(data['inboundCount']);
    final responded = _number(data['respondedCount']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Скорость ответа на входящие обращения',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Одно обращение начинается первым сообщением клиента после ответа '
            'сотрудника. Время считается до первого следующего ответа школы.',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 900
                  ? (constraints.maxWidth - 32) / 3
                  : constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _Metric(width: width, label: 'Входящие', value: '$inbound'),
                  _Metric(
                    width: width,
                    label: 'С ответом',
                    value: '$responded',
                  ),
                  _Metric(
                    width: width,
                    label: 'Доля ответов',
                    value: '${(_number(data['responseRate']) * 100).round()}%',
                  ),
                  _Metric(
                    width: width,
                    label: 'Среднее время',
                    value: _minutes(data['avgMinutes']),
                  ),
                  _Metric(
                    width: width,
                    label: 'Медиана',
                    value: _minutes(data['medianMinutes']),
                  ),
                  _Metric(
                    width: width,
                    label: '90-й процентиль',
                    value: _minutes(data['p90Minutes']),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Самые долгие ответы',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (slow.isEmpty)
            const Text('В выбранном периоде отвеченных обращений нет.')
          else
            ...slow.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item['clientName']?.toString() ?? 'Клиент'),
                  subtitle: Text(_slowSubtitle(item)),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () {
                    final id = item['chatId']?.toString().trim() ?? '';
                    if (id.isEmpty) return;
                    widget.onOpenEntity(
                      EntityLink.typed(
                        entityType: EntityLinkType.chat,
                        entityId: id,
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Не всё обновилось — повторить'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.surfaceSoft,
        border: Border.all(color: AppColor.borderSoft),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

String _slowSubtitle(Map<String, dynamic> item) {
  final inbound = DateTime.tryParse(item['inboundAt']?.toString() ?? '');
  final date = inbound == null
      ? 'Время не указано'
      : DateFormat('dd.MM.yyyy HH:mm').format(inbound.toLocal());
  return '$date · ответ через ${_minutes(item['minutes'])}';
}

String _minutes(Object? value) {
  final minutes = _number(value);
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final rest = (minutes - hours * 60).round();
    return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
  }
  return '${minutes.round()} мин';
}

num _number(Object? value) =>
    value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;
