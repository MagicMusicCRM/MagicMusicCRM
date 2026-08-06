import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';

Future<bool?> showCreateTeacherSurface(BuildContext context) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Новый преподаватель',
    subtitle: 'Контакты и специализация',
    icon: Icons.school_outlined,
    builder: (_) => const CreateTeacherDialog(),
  );
}

class CreateTeacherDialog extends ConsumerStatefulWidget {
  const CreateTeacherDialog({super.key});

  @override
  ConsumerState<CreateTeacherDialog> createState() =>
      _CreateTeacherDialogState();
}

class _CreateTeacherDialogState extends ConsumerState<CreateTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final email = _emailController.text.trim();
      final specialization = _specializationController.text.trim();
      await ref
          .read(magicCrmServiceProvider)
          .createTeacher(
            firstName: _firstNameController.text.trim(),
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
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('create-teacher-form'),
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _firstNameController,
            decoration: const InputDecoration(labelText: 'Имя *'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Введите имя преподавателя'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lastNameController,
            decoration: const InputDecoration(labelText: 'Фамилия'),
          ),
          const SizedBox(height: 12),
          RuPhoneField(onCanonicalChanged: (value) => _canonicalPhone = value),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (value) {
              final email = value?.trim() ?? '';
              return email.isNotEmpty && !email.contains('@')
                  ? 'Введите корректный email'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _specializationController,
            decoration: const InputDecoration(
              labelText: 'Специализация',
              hintText: 'Например: Гитара, Вокал',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Создать преподавателя'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
