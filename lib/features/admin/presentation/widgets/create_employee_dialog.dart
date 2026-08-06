import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';

Future<bool?> showCreateEmployeeSurface(
  BuildContext context, {
  required String currentRole,
}) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Новый сотрудник',
    subtitle: 'Контакты и роль в приложении',
    icon: Icons.person_add_alt_1_rounded,
    builder: (_) => CreateEmployeeDialog(currentRole: currentRole),
  );
}

class CreateEmployeeDialog extends ConsumerStatefulWidget {
  const CreateEmployeeDialog({super.key, required this.currentRole});

  final String currentRole;

  @override
  ConsumerState<CreateEmployeeDialog> createState() =>
      _CreateEmployeeDialogState();
}

class _CreateEmployeeDialogState extends ConsumerState<CreateEmployeeDialog> {
  static const _adminRole = (value: 'admin', label: 'Администратор');
  static const _managerRole = (value: 'manager', label: 'Управляющий');

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  String _canonicalPhone = '';
  String _selectedRole = 'admin';
  bool _saving = false;

  List<({String value, String label})> get _roles =>
      widget.currentRole == 'manager'
      ? const [_adminRole]
      : const [_adminRole, _managerRole];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createStaff(
            firstName: firstName,
            lastName: lastName,
            phone: _canonicalPhone,
            email: _emailController.text.trim(),
            role: _selectedRole,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$lastName $firstName добавлен')),
        );
        Navigator.pop(context, true);
      }
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

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('create-employee-form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Сотрудник сможет зарегистрироваться по указанной почте или телефону.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastNameController,
            decoration: const InputDecoration(
              labelText: 'Фамилия *',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _firstNameController,
            decoration: const InputDecoration(
              labelText: 'Имя *',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: _required,
          ),
          const SizedBox(height: 12),
          RuPhoneField(onCanonicalChanged: (value) => _canonicalPhone = value),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Электронная почта *',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              final requiredError = _required(value);
              if (requiredError != null) return requiredError;
              return value!.trim().contains('@')
                  ? null
                  : 'Введите корректный email';
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedRole,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Роль'),
            items: [
              for (final role in _roles)
                DropdownMenuItem(value: role.value, child: Text(role.label)),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) setState(() => _selectedRole = value);
                  },
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
                      : const Text('Добавить сотрудника'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
