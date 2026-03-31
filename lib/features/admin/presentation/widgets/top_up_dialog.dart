import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class TopUpDialog extends StatefulWidget {
  final Map<String, dynamic> student;

  const TopUpDialog({super.key, required this.student});

  static Future<bool?> show(BuildContext context, Map<String, dynamic> student) {
    return showDialog<bool>(
      context: context,
      builder: (_) => TopUpDialog(student: student),
    );
  }

  @override
  State<TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends State<TopUpDialog> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);
    
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректную сумму')));
      return;
    }

    setState(() => _saving = true);

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('payments').insert({
        'student_id': widget.student['id'],
        'amount': amount,
        'type': 'other', // manual top-up
        'description': _descController.text.trim().isEmpty ? 'Ручное пополнение баланса' : _descController.text.trim(),
        'payment_date': DateTime.now().toIso8601String(),
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.student['first_name'] ?? ''} ${widget.student['last_name'] ?? ''}'.trim();

    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Пополнить баланс'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ученик: ${name.isEmpty ? "Без имени" : name}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Сумма (₽) *',
              prefixIcon: Icon(Icons.currency_ruble_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Комментарий (необязательно)',
              hintText: 'Например: Перевод на карту',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_card_rounded, size: 18),
          label: const Text('Пополнить'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
        ),
      ],
    );
  }
}
