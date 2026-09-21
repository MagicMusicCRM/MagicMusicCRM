import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

class NotificationDeliveryJournalPanel extends ConsumerStatefulWidget {
  const NotificationDeliveryJournalPanel({
    super.key,
    required this.filter,
    required this.onOpenEntity,
    this.reloadToken = 0,
  });

  final DashboardFilter filter;
  final ValueChanged<EntityLink> onOpenEntity;
  final int reloadToken;

  @override
  ConsumerState<NotificationDeliveryJournalPanel> createState() =>
      _NotificationDeliveryJournalPanelState();
}

class _NotificationDeliveryJournalPanelState
    extends ConsumerState<NotificationDeliveryJournalPanel> {
  static const _pageSize = 100;
  List<Map<String, dynamic>> _items = const [];
  int _total = 0;
  String? _channel;
  String? _status;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  void didUpdateWidget(covariant NotificationDeliveryJournalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.reloadToken != widget.reloadToken) {
      unawaited(_load(reset: true));
    }
  }

  Future<void> _load({required bool reset}) async {
    final operation = ++_operation;
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final offset = reset ? 0 : _items.length;
      final response = await ref
          .read(magicNotificationsServiceProvider)
          .listDeliveryJournal(
            from: widget.filter.from,
            toExclusive: widget.filter.to.add(const Duration(days: 1)),
            branchId: widget.filter.branchId,
            channel: _channel,
            status: _status,
            limit: _pageSize,
            offset: offset,
          );
      if (!mounted || operation != _operation) return;
      final rawItems = response['items'];
      final next = rawItems is List
          ? rawItems.whereType<Map<String, dynamic>>().toList(growable: false)
          : const <Map<String, dynamic>>[];
      setState(() {
        _items = reset ? next : [..._items, ...next];
        _total = _asInt(response['total']);
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: AppDropdownButtonFormField<String?>(
                  menuMaxHeight: 256,
                  key: const ValueKey('delivery-journal-channel'),
                  initialValue: _channel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Канал',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Все каналы')),
                    DropdownMenuItem(
                      value: 'in_app',
                      child: Text('В приложении'),
                    ),
                    DropdownMenuItem(value: 'push', child: Text('Push')),
                    DropdownMenuItem(value: 'email', child: Text('Email')),
                  ],
                  onChanged: (value) {
                    setState(() => _channel = value);
                    unawaited(_load(reset: true));
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: AppDropdownButtonFormField<String?>(
                  menuMaxHeight: 256,
                  key: const ValueKey('delivery-journal-status'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Статус доставки',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Все статусы')),
                    DropdownMenuItem(value: 'sent', child: Text('Доставлено')),
                    DropdownMenuItem(value: 'queued', child: Text('В очереди')),
                    DropdownMenuItem(value: 'failed', child: Text('Ошибка')),
                    DropdownMenuItem(
                      value: 'skipped',
                      child: Text('Пропущено'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _status = value);
                    unawaited(_load(reset: true));
                  },
                ),
              ),
              Text('Показано ${_items.length} из $_total'),
              IconButton(
                tooltip: 'Обновить журнал',
                onPressed: () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить журнал доставки.'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => unawaited(_load(reset: true)),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('За выбранный период доставок не зафиксировано.'),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + (_items.length < _total ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Center(
              child: OutlinedButton.icon(
                onPressed: _loadingMore
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: const Text('Показать ещё'),
              ),
            );
          }
          return _DeliveryCard(
            item: _items[index],
            onOpenEntity: widget.onOpenEntity,
          );
        },
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.item, required this.onOpenEntity});

  final Map<String, dynamic> item;
  final ValueChanged<EntityLink> onOpenEntity;

  @override
  Widget build(BuildContext context) {
    final status = item['status']?.toString() ?? 'queued';
    final statusView = _statusView(status);
    final sourceLink = _link(item['entityType'], item['entityId']);
    final recipientLink = _link(
      item['recipientEntityType'],
      item['recipientEntityId'],
    );
    final updatedAt = DateTime.tryParse(item['updatedAt']?.toString() ?? '');
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColor.borderSoft),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(statusView.$1, color: statusView.$2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title']?.toString() ?? 'Уведомление',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_channelLabel(item['channel'])} · ${statusView.$3} · '
                    '${item['branchName'] ?? 'Филиал не указан'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Получатель: ${item['recipientName'] ?? 'Без имени'}'
                    '${updatedAt == null ? '' : ' · ${DateFormat('dd.MM.yyyy HH:mm').format(updatedAt.toLocal())}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (status == 'failed' &&
                      item['lastError']?.toString().trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        item['lastError'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColor.danger),
                      ),
                    ),
                ],
              ),
            ),
            if (sourceLink != null)
              IconButton(
                tooltip: 'Открыть связанную запись',
                onPressed: () => onOpenEntity(sourceLink),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            if (recipientLink != null)
              IconButton(
                tooltip: 'Открыть карточку получателя',
                onPressed: () => onOpenEntity(recipientLink),
                icon: const Icon(Icons.badge_outlined),
              ),
          ],
        ),
      ),
    );
  }

  static EntityLink? _link(Object? type, Object? id) {
    final entityType = type?.toString().trim() ?? '';
    final entityId = id?.toString().trim() ?? '';
    if (entityType.isEmpty || entityId.isEmpty) return null;
    final link = EntityLink.fromJson({
      'entityType': entityType,
      'entityId': entityId,
    });
    return link.isSupported ? link : null;
  }
}

(IconData, Color, String) _statusView(String status) => switch (status) {
  'sent' => (
    Icons.check_circle_outline_rounded,
    AppColor.success,
    'Доставлено',
  ),
  'failed' => (Icons.error_outline_rounded, AppColor.danger, 'Ошибка'),
  'skipped' => (Icons.block_rounded, AppColor.text2, 'Пропущено'),
  _ => (Icons.schedule_rounded, AppColor.warning, 'В очереди'),
};

String _channelLabel(Object? value) => switch (value?.toString()) {
  'in_app' => 'В приложении',
  'email' => 'Email',
  _ => 'Push',
};

int _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
