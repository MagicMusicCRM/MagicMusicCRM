import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

String _utcOffsetLabel(int minutes) {
  final sign = minutes >= 0 ? '+' : '-';
  final abs = minutes.abs();
  final h = abs ~/ 60;
  final m = abs % 60;
  final timeStr = m == 0 ? 'UTC$sign$h' : 'UTC$sign$h:${m.toString().padLeft(2, '0')}';
  return switch (minutes) {
    180 => 'МСК ($timeStr)',
    120 => 'EET ($timeStr)',
    60 => 'CET ($timeStr)',
    0 => 'UTC',
    _ => timeStr,
  };
}

class BranchFormDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? branch;

  const BranchFormDialog({super.key, this.branch});

  @override
  ConsumerState<BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends ConsumerState<BranchFormDialog> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  int _utcOffsetMinutes = 180;
  bool _saving = false;

  static final List<int> _offsetOptions = List.generate(
    (14 * 60 + 12 * 60) ~/ 30 + 1,
    (i) => -12 * 60 + i * 30,
  );

  @override
  void initState() {
    super.initState();
    if (widget.branch != null) {
      _nameController.text = widget.branch!['name'] as String? ?? '';
      _addressController.text = widget.branch!['address'] as String? ?? '';
      _utcOffsetMinutes =
          (widget.branch!['utc_offset_minutes'] as num?)?.toInt() ?? 180;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final address = _addressController.text.trim();

      if (widget.branch == null) {
        await crm.createBranch(
          name: name,
          address: address.isEmpty ? null : address,
          utcOffsetMinutes: _utcOffsetMinutes,
        );
      } else {
        final id = widget.branch!['id']?.toString();
        if (id == null || id.isEmpty) return;
        await crm.updateBranch(
          id,
          name: name,
          address: address,
          utcOffsetMinutes: _utcOffsetMinutes,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.branch != null;
    return AlertDialog(
      title: Text(isEdit ? 'Редактировать филиал' : 'Новый филиал'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название *'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(labelText: 'Адрес'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _utcOffsetMinutes,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Часовой пояс'),
            items: _offsetOptions
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(_utcOffsetLabel(m)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _utcOffsetMinutes = v);
            },
          ),
        ],
      ),
      actions: [
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
