import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class NotificationBellWidget extends StatefulWidget {
  const NotificationBellWidget({super.key});

  @override
  State<NotificationBellWidget> createState() => _NotificationBellWidgetState();
}

class _NotificationBellWidgetState extends State<NotificationBellWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToNotifications();
  }

  void _subscribeToNotifications() {
    _supabase
        .channel('notifications_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            _loadNotifications();
          },
        )
        .subscribe();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      // fail silently
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('is_read', false);
      setState(() {
        _notifications = _notifications.map((n) => {...n, 'is_read': true}).toList();
      });
    } catch (_) {}
  }

  int get _unreadCount => _notifications.where((n) => n['is_read'] == false).length;

  String _notificationTitle(Map<String, dynamic> n) {
    switch (n['type']) {
      case 'new_user_registered':
        final email = (n['data'] as Map?)?['email'] ?? '';
        return 'Новый пользователь: $email';
      default:
        return n['type'] ?? 'Уведомление';
    }
  }

  String _formatDate(String? dt) {
    if (dt == null) return '';
    try {
      final d = DateTime.parse(dt).toLocal();
      return DateFormat('d MMM, HH:mm', 'ru').format(d);
    } catch (_) {
      return dt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Уведомления',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_outlined, color: Colors.white, size: 26),
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
      onPressed: () => _showNotificationsPanel(context),
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
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(60),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
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
                            final nav = Navigator.of(context);
                            await _markAllRead();
                            nav.pop();
                          },
                          child: Text(
                            'Прочитать все',
                            style: TextStyle(color: AppTheme.primaryPurple),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12),
                // List
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primaryPurple,
                          ),
                        )
                      : _notifications.isEmpty
                          ? Center(
                              child: Text(
                                'Нет уведомлений',
                                style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 15),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _notifications.length,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemBuilder: (_, i) {
                                final n = _notifications[i];
                                final isUnread = n['is_read'] == false;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isUnread
                                        ? AppTheme.primaryPurple.withAlpha(30)
                                        : Theme.of(context!).colorScheme.surface.withAlpha(150),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isUnread
                                          ? AppTheme.primaryPurple.withAlpha(80)
                                          : Colors.transparent,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryPurple.withAlpha(50),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.person_add_outlined,
                                          color: AppTheme.primaryPurple,
                                          size: 18,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _notificationTitle(n),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: isUnread
                                                    ? FontWeight.w700
                                                    : FontWeight.w400,
                                                fontSize: 14,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              _formatDate(n['created_at']),
                                              style: TextStyle(
                                                color: Theme.of(context!).colorScheme.onSurfaceVariant,
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
                                            color: AppTheme.primaryPurple,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
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
