import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BroadcastDialog extends StatefulWidget {
  const BroadcastDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const BroadcastDialog(),
    );
  }

  @override
  State<BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends State<BroadcastDialog> {
  final _messageController = TextEditingController();
  bool _sending = false;
  String _target = 'all'; // 'all', 'students', 'teachers'

  Future<void> _send() async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() => _sending = true);
    try {
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      // In a real app, this might call an Edge Function for efficiency.
      // Here we'll do it by inserting messages.
      
      List<String> receiverIds = [];
      
      if (_target == 'all' || _target == 'students') {
        final students = await supabase.from('students').select('profile_id');
        receiverIds.addAll(students.map((s) => s['profile_id'] as String));
      }
      
      if (_target == 'all' || _target == 'teachers') {
        final teachers = await supabase.from('teachers').select('profile_id');
        receiverIds.addAll(teachers.map((t) => t['profile_id'] as String));
      }

      // Remove duplicates and self
      receiverIds = receiverIds.toSet().toList();
      receiverIds.remove(currentUser.id);

      final messages = receiverIds.map((id) => {
        'sender_id': currentUser.id,
        'receiver_id': id,
        'content': _messageController.text.trim(),
        'is_read': false,
      }).toList();

      if (messages.isNotEmpty) {
        // Supabase allows bulk insert
        await supabase.from('messages').insert(messages);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Рассылка отправлена (${messages.length} получателей)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при рассылке: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
              ButtonSegment(value: 'all', label: Text('Всем'), icon: Icon(Icons.people_alt_rounded)),
              ButtonSegment(value: 'students', label: Text('Ученикам'), icon: Icon(Icons.school_rounded)),
              ButtonSegment(value: 'teachers', label: Text('Преп.'), icon: Icon(Icons.person_rounded)),
            ],
            selected: {_target},
            onSelectionChanged: (set) => setState(() => _target = set.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Введите текст сообщения...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending 
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send_rounded),
          label: const Text('Отправить'),
        ),
      ],
    );
  }
}
