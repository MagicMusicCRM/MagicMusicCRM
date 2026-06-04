import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherDetailDialog extends StatefulWidget {
  final Map<String, dynamic> teacher;
  
  const TeacherDetailDialog({super.key, required this.teacher});

  static Future<bool?> show(BuildContext context, Map<String, dynamic> teacher) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => TeacherDetailDialog(teacher: teacher),
    );
  }

  @override
  State<TeacherDetailDialog> createState() => _TeacherDetailDialogState();
}

class _TeacherDetailDialogState extends State<TeacherDetailDialog> {
  late Map<String, dynamic> _localData;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _localData = Map<String, dynamic>.from(widget.teacher);
    final fn = _localData['first_name'] ?? '';
    final ln = _localData['last_name'] ?? '';
    final prof = _localData['profiles'] as Map<String, dynamic>?;
    
    _nameController = TextEditingController(text: '$fn $ln'.trim().isEmpty ? '${prof?['first_name'] ?? ''} ${prof?['last_name'] ?? ''}'.trim() : '$fn $ln'.trim());
    _phoneController = TextEditingController(text: _localData['phone']?.toString() ?? prof?['phone']?.toString() ?? '');
    _emailController = TextEditingController(text: _localData['email']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final names = _nameController.text.trim().split(' ');
      final fn = names.isNotEmpty ? names.first : '';
      final ln = names.length > 1 ? names.sublist(1).join(' ') : '';
      
      await Supabase.instance.client.from('teachers').update({
        'first_name': fn,
        'last_name': ln,
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
      }).eq('id', _localData['id']);
      
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Данные сохранены')));
      }
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
    return AlertDialog(
      title: const Text('Карточка преподавателя'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Имя Фамилия'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Телефон'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Сохранить'),
        ),
      ],
    );
  }
}
