import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class MassNotificationWidget extends ConsumerStatefulWidget {
  const MassNotificationWidget({super.key});

  @override
  ConsumerState<MassNotificationWidget> createState() =>
      _MassNotificationWidgetState();
}

class _MassNotificationWidgetState
    extends ConsumerState<MassNotificationWidget> {
  String _selectedAudience = 'students';
  bool _sending = false;
  final TextEditingController _messageController = TextEditingController();

  final List<({String key, String label, String target, String? role})>
  _audiences = [
    (key: 'students', label: 'Все ученики', target: 'role', role: 'client'),
    (
      key: 'teachers',
      label: 'Все преподаватели',
      target: 'role',
      role: 'teacher',
    ),
    (key: 'all', label: 'Все пользователи', target: 'all', role: null),
  ];

  Future<void> _sendNotification() async {
    final body = _messageController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите текст уведомления')),
      );
      return;
    }
    final audience = _audiences.firstWhere(
      (item) => item.key == _selectedAudience,
      orElse: () => _audiences.first,
    );
    setState(() => _sending = true);

    try {
      final result = await ref
          .read(magicNotificationsServiceProvider)
          .adminSend(
            target: audience.target,
            role: audience.role,
            title: 'Сообщение от школы',
            body: body,
            channels: const ['in_app', 'push'],
            data: const {'route': 'notifications'},
          );
      if (!mounted) return;
      final count = result['recipientCount'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Уведомление отправлено: $count получателей'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.success,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      _messageController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка отправки уведомления: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.danger,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Массовые уведомления',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Отправка мобильных уведомлений ученикам и преподавателям',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Получатели:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedAudience,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.group_rounded),
            ),
            items: _audiences
                .map(
                  (audience) => DropdownMenuItem(
                    value: audience.key,
                    child: Text(audience.label),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedAudience = val);
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Текст сообщения:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Введите текст сообщения...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _sendNotification,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Отправка...' : 'Отправить уведомление'),
            ),
          ),
        ],
      ),
    );
  }
}
