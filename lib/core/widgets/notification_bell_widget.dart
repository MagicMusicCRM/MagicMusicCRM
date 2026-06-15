import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

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

  MagicNotificationsService get _service =>
      ref.read(magicNotificationsServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final notifications = await _service.list(limit: 50);
      if (!mounted) return;
      setState(() => _notifications = notifications);
    } catch (e) {
      debugPrint('Notifications load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _service.markAllRead();
      if (!mounted) return;
      setState(() {
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
      setState(() {
        _notifications = _notifications
            .map((item) => item['id'] == id ? {...item, ...updated} : item)
            .toList();
      });
    } catch (e) {
      debugPrint('Notification mark-read error: $e');
    }
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
    return IconButton(
      tooltip: 'Уведомления',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_outlined,
            color: Colors.white,
            size: 26,
          ),
          if (_unreadCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppTheme.danger,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1A29),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(60),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Уведомления',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      if (_unreadCount > 0)
                        TextButton(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _markAllRead();
                            navigator.pop();
                          },
                          child: const Text(
                            'Прочитать все',
                            style: TextStyle(color: AppTheme.primaryGold),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primaryGold,
                          ),
                        )
                      : _notifications.isEmpty
                      ? Center(
                          child: Text(
                            'Нет уведомлений',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 15,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _notifications.length,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemBuilder: (_, index) {
                            final item = _notifications[index];
                            final isUnread = item['is_read'] == false;
                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: isUnread
                                  ? () => _markRead(item['id'].toString())
                                  : null,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isUnread
                                      ? AppTheme.primaryGold.withAlpha(28)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surface.withAlpha(150),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isUnread
                                        ? AppTheme.primaryGold.withAlpha(90)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryGold.withAlpha(
                                          45,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _iconForType(item['type']?.toString()),
                                        color: AppTheme.primaryGold,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _notificationTitle(item),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: isUnread
                                                  ? FontWeight.w700
                                                  : FontWeight.w400,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (_notificationBody(
                                            item,
                                          ).isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _notificationBody(item),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDate(
                                              item['created_at']?.toString(),
                                            ),
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isUnread)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primaryGold,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
