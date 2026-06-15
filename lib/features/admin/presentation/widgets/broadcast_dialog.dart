import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';

class BroadcastDialog extends ConsumerStatefulWidget {
  const BroadcastDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const BroadcastDialog(),
    );
  }

  @override
  ConsumerState<BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends ConsumerState<BroadcastDialog> {
  final _messageController = TextEditingController();
  bool _sending = false;
  String _target = 'all';

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if (body.isEmpty) return;

    setState(() => _sending = true);
    try {
      final result = await ref
          .read(magicNotificationsServiceProvider)
          .adminSend(
            target: _target == 'all' ? 'all' : 'role',
            role: switch (_target) {
              'students' => 'client',
              'teachers' => 'teacher',
              _ => null,
            },
            title: 'Сообщение от школы',
            body: body,
            data: const {'route': 'notifications'},
          );

      if (!mounted) return;
      Navigator.pop(context);
      final count = result['recipientCount'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Рассылка отправлена: $count получателей')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка при рассылке: $e')));
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
    return AlertDialog(
      title: const Text('Массовая рассылка'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'all',
                label: Text('Всем'),
                icon: Icon(Icons.people_alt_rounded),
              ),
              ButtonSegment(
                value: 'students',
                label: Text('Ученикам'),
                icon: Icon(Icons.school_rounded),
              ),
              ButtonSegment(
                value: 'teachers',
                label: Text('Преподавателям'),
                icon: Icon(Icons.person_rounded),
              ),
            ],
            selected: {_target},
            onSelectionChanged: (value) =>
                setState(() => _target = value.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: 'Введите текст сообщения...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded),
          label: const Text('Отправить'),
        ),
      ],
    );
  }
}
