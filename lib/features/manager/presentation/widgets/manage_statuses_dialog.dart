import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';

class ManageStatusesDialog extends ConsumerStatefulWidget {
  const ManageStatusesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ManageStatusesDialog(),
    );
  }

  @override
  ConsumerState<ManageStatusesDialog> createState() => _ManageStatusesDialogState();
}

class _ManageStatusesDialogState extends ConsumerState<ManageStatusesDialog> {
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(leadStatusesProvider.future);
      if (!mounted) return;
      setState(() {
        _statuses = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _addStatus() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => const _StatusEditDialog(),
    );
    if (result != null) {
      await ref.read(supaLeadServiceProvider).addStatus(
        key: result['key']!,
        label: result['label']!,
        color: result['color']!,
        sortOrder: _statuses.length,
      );
      ref.invalidate(leadStatusesProvider);
      _loadStatuses();
    }
  }

  Future<void> _deleteStatus(String id) async {
    await ref.read(supaLeadServiceProvider).deleteStatus(id);
    ref.invalidate(leadStatusesProvider);
    _loadStatuses();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Колонки воронки'),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 400,
        child: _loading 
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple))
            : ListView.builder(
                itemCount: _statuses.length,
                itemBuilder: (context, index) {
                  final s = _statuses[index];
                  final hexColor = s['color']?.toString().replaceAll('#', '') ?? '8B5CF6';
                  final c = Color(int.parse('FF$hexColor', radix: 16));
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 16, height: 16,
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                      title: Text(s['label']),
                      subtitle: Text('Ключ: ${s['key']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                        onPressed: () => _deleteStatus(s['id'].toString()),
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _addStatus,
          icon: const Icon(Icons.add),
          label: const Text('Добавить колонку'),
        ),
      ],
    );
  }
}

class _StatusEditDialog extends StatefulWidget {
  const _StatusEditDialog();

  @override
  State<_StatusEditDialog> createState() => _StatusEditDialogState();
}

class _StatusEditDialogState extends State<_StatusEditDialog> {
  final _labelCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  String _selectedHex = 'D4AF37'; // Default gold

  final List<String> _colors = [
    '8B5CF6', // Purple
    '3B82F6', // Blue
    '10B981', // Green
    'F59E0B', // Yellow
    'EF4444', // Red
    '6B7280', // Gray
  ];

  @override
  void dispose() {
    _labelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Новая колонка'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: _labelCtrl, decoration: const InputDecoration(labelText: 'Название (напр. Переговоры)')),
          const SizedBox(height: 12),
          TextField(controller: _keyCtrl, decoration: const InputDecoration(labelText: 'Ключ (напр. negotiation, на англ., без пробелов)')),
          const SizedBox(height: 16),
          Text('Цвет', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _colors.map((c) {
              final color = Color(int.parse('FF$c', radix: 16));
              final isSelected = _selectedHex == c;
              return GestureDetector(
                onTap: () => setState(() => _selectedHex = c),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (_labelCtrl.text.trim().isNotEmpty && _keyCtrl.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'label': _labelCtrl.text.trim(),
                'key': _keyCtrl.text.trim().toLowerCase(),
                'color': '#$_selectedHex',
              });
            }
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
