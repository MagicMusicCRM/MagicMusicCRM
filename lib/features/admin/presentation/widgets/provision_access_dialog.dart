import 'package:flutter/material.dart';

typedef ProvisionAccessSubmit =
    Future<void> Function(String email, String password, String? role);

Future<bool?> showProvisionAccessDialog(
  BuildContext context, {
  required String personLabel,
  required ProvisionAccessSubmit onSubmit,
  String initialEmail = '',
  Map<String, String>? roles,
  String? initialRole,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _ProvisionAccessDialog(
      personLabel: personLabel,
      initialEmail: initialEmail,
      roles: roles,
      initialRole: initialRole,
      onSubmit: onSubmit,
    ),
  );
}

class _ProvisionAccessDialog extends StatefulWidget {
  const _ProvisionAccessDialog({
    required this.personLabel,
    required this.initialEmail,
    required this.roles,
    required this.initialRole,
    required this.onSubmit,
  });

  final String personLabel;
  final String initialEmail;
  final Map<String, String>? roles;
  final String? initialRole;
  final ProvisionAccessSubmit onSubmit;

  @override
  State<_ProvisionAccessDialog> createState() => _ProvisionAccessDialogState();
}

class _ProvisionAccessDialogState extends State<_ProvisionAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();
  String? _role;
  bool _saving = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final initialEmail = widget.initialEmail.trim();
    _email = TextEditingController(
      text:
          initialEmail.endsWith('@migration.invalid') ||
              initialEmail.endsWith('@local.magicmusiccrm.invalid')
          ? ''
          : initialEmail,
    );
    _role = widget.initialRole ?? widget.roles?.keys.firstOrNull;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordAgain.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(_email.text.trim(), _password.text, _role);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось создать доступ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Создать доступ: ${widget.personLabel}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email для входа *',
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return 'Обязательное поле';
                  return email.contains('@')
                      ? null
                      : 'Введите корректный email';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Пароль *',
                  helperText: 'Не менее 10 символов',
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? 'Скрыть пароль'
                        : 'Показать пароль',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                validator: (value) => (value?.length ?? 0) < 10
                    ? 'Пароль должен содержать минимум 10 символов'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordAgain,
                obscureText: !_showPassword,
                decoration: const InputDecoration(
                  labelText: 'Повторите пароль *',
                ),
                validator: (value) =>
                    value != _password.text ? 'Пароли не совпадают' : null,
              ),
              if (widget.roles case final roles?) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Роль доступа *',
                  ),
                  items: [
                    for (final entry in roles.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(() => _role = value),
                  validator: (value) => value == null ? 'Выберите роль' : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
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
              : const Text('Создать доступ'),
        ),
      ],
    );
  }
}
