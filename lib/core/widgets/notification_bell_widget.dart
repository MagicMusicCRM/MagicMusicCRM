import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

class NotificationBellWidget extends ConsumerStatefulWidget {
  const NotificationBellWidget({super.key});

  @override
  ConsumerState<NotificationBellWidget> createState() =>
      _NotificationBellWidgetState();
}

class _NotificationBellWidgetState
    extends ConsumerState<NotificationBellWidget> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = false;

  // ── Realtime invalidation (crm.changed) ───────────────────────────────────
  Timer? _realtimeDebounce;

  /// Lets the open sheet rebuild its body when the underlying list changes,
  /// since the data/state lives on this parent widget, not in the sheet.
  VoidCallback? _sheetRefresh;

  MagicNotificationsService get _service =>
      ref.read(magicNotificationsServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    super.dispose();
  }

  void _applyState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _sheetRefresh?.call();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    _applyState(() => _isLoading = true);
    try {
      final notifications = await _service.list(limit: 50);
      if (!mounted) return;
      _applyState(() => _notifications = notifications);
    } catch (e) {
      debugPrint('Notifications load error: $e');
    } finally {
      if (mounted) _applyState(() => _isLoading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _service.markAllRead();
      if (!mounted) return;
      _applyState(() {
        _notifications = _notifications
            .map((item) => {...item, 'is_read': true})
            .toList();
      });
    } catch (e) {
      debugPrint('Notifications mark-all error: $e');
    }
  }

  Future<void> _markRead(String id) async {
    try {
      final updated = await _service.markRead(id);
      if (!mounted) return;
      _applyState(() {
        _notifications = _notifications
            .map((item) => item['id'] == id ? {...item, ...updated} : item)
            .toList();
      });
    } catch (e) {
      debugPrint('Notification mark-read error: $e');
    }
  }

  Future<void> _openNotification(
    BuildContext sheetContext,
    Map<String, dynamic> item,
  ) async {
    if (item['is_read'] == false) await _markRead(item['id'].toString());
    final data = item['data'];
    if (data is! Map) return;
    final body = _notificationBody(item);
    final fallbackName = item['type'] == 'new_lead'
        ? body.split(' — источник:').first.trim()
        : '';
    final entityName = data['entityName']?.toString().trim();
    final link = EntityLink.fromJson({
      'entityType': data['entityType'],
      'entityId': data['entityId'],
      if (entityName?.isNotEmpty == true || fallbackName.isNotEmpty)
        'presentation': {
          'primary': entityName?.isNotEmpty == true ? entityName : fallbackName,
        },
    });
    if (!link.isSupported || !mounted) return;
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    await openEntityLink(context, ref, link);
  }

  int get _unreadCount =>
      _notifications.where((item) => item['is_read'] == false).length;

  String _notificationTitle(Map<String, dynamic> item) {
    final title = item['title']?.toString();
    if (title != null && title.trim().isNotEmpty) return title.trim();

    switch (item['type']) {
      case 'new_user_registered':
        final data = item['data'];
        final email = data is Map ? data['email']?.toString() ?? '' : '';
        return 'Новый пользователь: $email';
      case 'admin_broadcast':
        return 'Сообщение от школы';
      default:
        return 'Уведомление';
    }
  }

  String _notificationBody(Map<String, dynamic> item) {
    return item['body']?.toString() ?? '';
  }

  String _formatDate(String? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return DateFormat('d MMM, HH:mm', 'ru').format(date.toLocal());
  }

  IconData _iconForType(String? type) {
    return switch (type) {
      'admin_broadcast' => Icons.campaign_rounded,
      'new_user_registered' => Icons.person_add_outlined,
      _ => Icons.notifications_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Realtime: reload notifications when a new one arrives in the user's own
    // room (recipient-scoped crm.changed → works for non-staff too).
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'notification' || !mounted) return;
      if (_isLoading) return;
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _isLoading) return;
        _loadNotifications();
      });
    });
    return IconButton(
      tooltip: 'Уведомления',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_outlined,
            color: AppColor.text2,
            size: 26,
          ),
          if (_unreadCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppColor.danger,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  _unreadCount > 9 ? '9+' : '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: () {
        _loadNotifications();
        _showNotificationsPanel(context);
      },
    );
  }

  void _showNotificationsPanel(BuildContext context) {
    showMagicSheet<void>(
      context,
      title: 'Уведомления',
      subtitle: _unreadCount > 0 ? 'Непрочитанных: $_unreadCount' : null,
      icon: Icons.notifications_outlined,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (innerContext, setSheetState) {
            // Bind the open sheet to parent-state changes so service results
            // re-render here. Cleared when the body is torn down/rebuilt.
            _sheetRefresh = () {
              if (innerContext.mounted) setSheetState(() {});
            };
            return _NotificationsBody(
              isLoading: _isLoading,
              notifications: _notifications,
              unreadCount: _unreadCount,
              iconForType: _iconForType,
              titleFor: _notificationTitle,
              bodyFor: _notificationBody,
              formatDate: _formatDate,
              onTapItem: (item) => _openNotification(sheetContext, item),
              onMarkAll: () async {
                await _markAllRead();
                if (!sheetContext.mounted) return;
                MagicToast.show(
                  sheetContext,
                  'Все уведомления прочитаны',
                  type: MagicToastType.success,
                );
              },
            );
          },
        );
      },
    ).whenComplete(() => _sheetRefresh = null);
  }
}

/// v7 body for the notifications sheet: a card list with a gold unread dot,
/// theme-aware surfaces, and a flat gold «Прочитать все» action.
class _NotificationsBody extends StatelessWidget {
  const _NotificationsBody({
    required this.isLoading,
    required this.notifications,
    required this.unreadCount,
    required this.iconForType,
    required this.titleFor,
    required this.bodyFor,
    required this.formatDate,
    required this.onTapItem,
    required this.onMarkAll,
  });

  final bool isLoading;
  final List<Map<String, dynamic>> notifications;
  final int unreadCount;
  final IconData Function(String? type) iconForType;
  final String Function(Map<String, dynamic> item) titleFor;
  final String Function(Map<String, dynamic> item) bodyFor;
  final String Function(String? value) formatDate;
  final Future<void> Function(Map<String, dynamic>) onTapItem;
  final Future<void> Function() onMarkAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (isLoading && notifications.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: AppColor.gold)),
      );
    }

    if (notifications.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColor.goldSoft,
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                  border: Border.all(color: AppColor.goldLine),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: AppColor.gold,
                  size: 26,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Нет уведомлений',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unreadCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Align(
              alignment: Alignment.centerRight,
              child: _MarkAllButton(onPressed: onMarkAll),
            ),
          ),
        for (var i = 0; i < notifications.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          _NotificationCard(
            item: notifications[i],
            scheme: scheme,
            iconForType: iconForType,
            titleFor: titleFor,
            bodyFor: bodyFor,
            formatDate: formatDate,
            onTap: onTapItem,
          ),
        ],
      ],
    );
  }
}

/// Flat gold «Прочитать все» pill — no shadow (per v7 button rules).
class _MarkAllButton extends StatelessWidget {
  const _MarkAllButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.done_all_rounded, size: 18),
      label: const Text('Прочитать все'),
      style: TextButton.styleFrom(
        backgroundColor: AppColor.gold,
        foregroundColor: AppColor.onGold,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: 10,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
    );
  }
}

/// A single notification rendered as a v7 card. Unread cards carry a gold-soft
/// fill + gold hairline and a trailing gold dot; read cards sit on the theme
/// surface.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.scheme,
    required this.iconForType,
    required this.titleFor,
    required this.bodyFor,
    required this.formatDate,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final ColorScheme scheme;
  final IconData Function(String? type) iconForType;
  final String Function(Map<String, dynamic> item) titleFor;
  final String Function(Map<String, dynamic> item) bodyFor;
  final String Function(String? value) formatDate;
  final Future<void> Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    final isUnread = item['is_read'] == false;
    final body = bodyFor(item);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => onTap(item),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: isUnread
                ? AppColor.goldSoft
                : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: isUnread ? AppColor.goldLine : scheme.outlineVariant,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColor.goldSoft,
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                  border: Border.all(color: AppColor.goldLine),
                ),
                child: Icon(
                  iconForType(item['type']?.toString()),
                  color: AppColor.gold,
                  size: 19,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleFor(item),
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: isUnread
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      formatDate(item['created_at']?.toString()),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                  margin: const EdgeInsets.only(left: AppSpace.sm, top: 4),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColor.gold,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
