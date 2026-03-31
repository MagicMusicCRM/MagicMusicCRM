import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class CreateRoomDialog extends StatefulWidget {
  final Map<String, dynamic>? room; // if null, create mode; otherwise, edit mode

  const CreateRoomDialog({super.key, this.room});

  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController(text: '1');
  String? _selectedBranch;
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.room != null) {
      _nameController.text = widget.room!['name'] ?? '';
      _capacityController.text = widget.room!['capacity']?.toString() ?? '1';
      _selectedBranch = widget.room!['branch_id'];
    }
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    final res = await Supabase.instance.client.from('branches').select('id, name');
    setState(() {
      _branches = List<Map<String, dynamic>>.from(res);
      if (_branches.isNotEmpty && _selectedBranch == null) {
        _selectedBranch = _branches.first['id'].toString();
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedBranch == null) return;

    final data = {
      'name': name,
      'capacity': int.tryParse(_capacityController.text.trim()) ?? 1,
      'branch_id': _selectedBranch,
    };

    if (widget.room == null) {
      await Supabase.instance.client.from('rooms').insert(data);
    } else {
      await Supabase.instance.client.from('rooms').update(data).eq('id', widget.room!['id']);
    }

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    if (widget.room == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аудиторию?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Назад')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.from('rooms').delete().eq('id', widget.room!['id']);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.room == null ? 'Новая аудитория' : 'Редактировать аудиторию'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: _loading ? const CircularProgressIndicator(color: AppTheme.primaryPurple) : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _capacityController,
            decoration: const InputDecoration(labelText: 'Вместимость (чел.)'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedBranch,
            decoration: const InputDecoration(labelText: 'Филиал'),
            items: _branches.map((b) => DropdownMenuItem(
              value: b['id'].toString(),
              child: Text(b['name']),
            )).toList(),
            onChanged: (v) => setState(() => _selectedBranch = v),
          ),
        ],
      ),
      actions: [
        if (widget.room != null)
          TextButton(
            onPressed: _delete,
            child: const Text('Удалить', style: TextStyle(color: AppTheme.danger)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}
