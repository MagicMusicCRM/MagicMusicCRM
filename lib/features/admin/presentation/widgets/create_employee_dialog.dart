import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';

Future<bool?> showCreateEmployeeSurface(BuildContext context) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Новый сотрудник',
    subtitle: 'Карточка сотрудника и необязательный доступ',
    icon: Icons.person_add_alt_1_rounded,
    builder: (_) => const CreateEmployeeDialog(),
  );
}

class CreateEmployeeDialog extends ConsumerStatefulWidget {
  const CreateEmployeeDialog({super.key});

  @override
  ConsumerState<CreateEmployeeDialog> createState() =>
      _CreateEmployeeDialogState();
}

class _CreateEmployeeDialogState extends ConsumerState<CreateEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordAgainController = TextEditingController();
  String _canonicalPhone = '';
  String? _branchId;
  List<Map<String, dynamic>> _branches = const [];
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final branches = await ref.read(magicCrmServiceProvider).listBranches();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$error';
      });
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordAgainController.dispose();
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
            email: _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
            password: _passwordController.text.isEmpty
                ? null
                : _passwordController.text,
            branchIds: [_branchId!],
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
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Не удалось загрузить филиалы.'),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _loadBranches,
            child: const Text('Повторить'),
          ),
        ],
      );
    }
    if (_branches.isEmpty) {
      return const Text(
        'Сначала создайте филиал. Без филиала сотрудника создать нельзя.',
      );
    }
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('create-employee-form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Карточку можно создать без аккаунта. Email и пароль можно добавить сейчас или позже в карточке; повышение роли выполняется только в «Доступах».',
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
              labelText: 'Электронная почта (необязательно)',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) {
                return _passwordController.text.isEmpty
                    ? null
                    : 'Укажите email вместе с паролем';
              }
              return email.contains('@') ? null : 'Введите корректный email';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Пароль (необязательно)',
              helperText: 'Для доступа — не менее 10 символов',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Скрыть пароль' : 'Показать пароль',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
            validator: (value) {
              final password = value ?? '';
              if (password.isEmpty) {
                return _emailController.text.trim().isEmpty
                    ? null
                    : 'Укажите пароль вместе с email';
              }
              return password.length < 10
                  ? 'Пароль должен содержать минимум 10 символов'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordAgainController,
            obscureText: !_showPassword,
            decoration: const InputDecoration(
              labelText: 'Повторите пароль',
              prefixIcon: Icon(Icons.lock_reset_rounded),
            ),
            validator: (value) {
              if (_passwordController.text.isEmpty &&
                  (value?.isEmpty ?? true)) {
                return null;
              }
              return value != _passwordController.text
                  ? 'Пароли не совпадают'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            menuMaxHeight: 256,
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Филиал *'),
            items: [
              for (final branch in _branches)
                DropdownMenuItem(
                  value: branch['id']?.toString(),
                  child: Text(branch['name']?.toString() ?? 'Филиал'),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _branchId = value),
            validator: (value) => value == null ? 'Выберите филиал' : null,
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
