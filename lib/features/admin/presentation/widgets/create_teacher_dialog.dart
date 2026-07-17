import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';

class CreateTeacherDialog extends ConsumerStatefulWidget {
  const CreateTeacherDialog({super.key});

  @override
  ConsumerState<CreateTeacherDialog> createState() =>
      _CreateTeacherDialogState();
}

class _CreateTeacherDialogState extends ConsumerState<CreateTeacherDialog> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _specializationController = TextEditingController();
  String _canonicalPhone = '';
  bool _saving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _specializationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final firstName = _firstNameController.text.trim();
    if (firstName.isEmpty) {
      // Used to return silently, which read as a dead Save button.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите имя преподавателя')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final email = _emailController.text.trim();
      final specialization = _specializationController.text.trim();
      await ref
          .read(magicCrmServiceProvider)
          .createTeacher(
            firstName: firstName,
            lastName: _lastNameController.text,
            phone: _canonicalPhone,
            email: email.isEmpty ? null : email,
            specialization: specialization.isEmpty ? null : specialization,
          );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый преподаватель'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'Имя *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'Фамилия'),
            ),
            const SizedBox(height: 12),
            RuPhoneField(onCanonicalChanged: (c) => _canonicalPhone = c),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _specializationController,
              decoration: const InputDecoration(
                labelText: 'Специализация',
                hintText: 'Например: Гитара, Вокал',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
