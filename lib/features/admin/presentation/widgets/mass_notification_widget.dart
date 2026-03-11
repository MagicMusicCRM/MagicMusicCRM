import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class MassNotificationWidget extends StatefulWidget {
  const MassNotificationWidget({super.key});

  @override
  State<MassNotificationWidget> createState() => _MassNotificationWidgetState();
}

class _MassNotificationWidgetState extends State<MassNotificationWidget> {
  String _selectedAudience = 'Все ученики';
  bool _sending = false;
  final TextEditingController _messageController = TextEditingController();

  final List<String> _audiences = [
    'Все ученики',
    'Все преподаватели',
    'Все пользователи',
    'Только Сокол',
    'Только Спортивная',
  ];

  Future<void> _sendNotification() async {
    if (_messageController.text.trim().isEmpty) return;
    setState(() => _sending = true);

    // Simulate send delay
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Уведомление отправлено: $_selectedAudience'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.success,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _messageController.clear();
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
          const Text('Массовые уведомления', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Отправка push-уведомлений ученикам и преподавателям',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 24),
          const Text('Получатели:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedAudience,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.group_rounded)),
            items: _audiences.map((aud) => DropdownMenuItem(value: aud, child: Text(aud))).toList(),
            onChanged: (val) { if (val != null) setState(() => _selectedAudience = val); },
          ),
          const SizedBox(height: 20),
          const Text('Текст сообщения:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Отправка...' : 'Отправить уведомление'),
            ),
          ),
        ],
      ),
    );
  }
}
