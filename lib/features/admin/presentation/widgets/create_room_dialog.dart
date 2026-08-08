import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class CreateRoomDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? room;
  final String branchId;
  final String branchName;

  const CreateRoomDialog({
    super.key,
    this.room,
    required this.branchId,
    required this.branchName,
  });

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    if (widget.room != null) {
      _nameController.text = widget.room!['name'] ?? '';
      _capacityController.text = widget.room!['capacity']?.toString() ?? '1';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    if (_saving) return; // guard against double-submit
    setState(() => _saving = true);

    try {
      final capacity = int.parse(_capacityController.text.trim());
      final crm = ref.read(magicCrmServiceProvider);

      if (widget.room == null) {
        await crm.createRoom(
          name: name,
          branchId: widget.branchId,
          capacity: capacity,
        );
      } else {
        final roomId = widget.room!['id']?.toString();
        if (roomId == null || roomId.isEmpty) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        await crm.updateRoom(
          roomId,
          name: name,
          branchId: widget.branchId,
          capacity: capacity,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить аудиторию.')),
        );
      }
    }
  }

  Future<void> _delete() async {
    if (widget.room == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аудиторию?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Назад'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final roomId = widget.room!['id']?.toString();
      if (roomId == null || roomId.isEmpty) return;
      if (_saving) return;
      setState(() => _saving = true);
      try {
        await ref.read(magicCrmServiceProvider).deleteRoom(roomId);
        if (mounted) Navigator.pop(context, true);
      } catch (_) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось удалить аудиторию.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.room == null
            ? 'Новая аудитория · ${widget.branchName}'
            : 'Редактировать аудиторию · ${widget.branchName}',
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Название *'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите название аудитории'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacityController,
              decoration: const InputDecoration(
                labelText: 'Вместимость, человек *',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final capacity = int.tryParse(value?.trim() ?? '');
                return capacity == null || capacity < 1 || capacity > 1000
                    ? 'Введите целое число от 1 до 1000'
                    : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (widget.room != null)
          TextButton(
            onPressed: _saving ? null : _delete,
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
