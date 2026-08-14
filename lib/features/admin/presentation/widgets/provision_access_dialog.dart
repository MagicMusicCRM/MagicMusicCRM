import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/security/password_policy.dart';

typedef ProvisionAccessSubmit =
    Future<void> Function(String? email, String? password);

Future<bool?> showProvisionAccessDialog(
  BuildContext context, {
  required String personLabel,
  required ProvisionAccessSubmit onSubmit,
  String initialEmail = '',
  String? currentPassword,
  bool accessExists = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _ProvisionAccessDialog(
      personLabel: personLabel,
      initialEmail: initialEmail,
      currentPassword: currentPassword,
      accessExists: accessExists,
      onSubmit: onSubmit,
    ),
  );
}

class _ProvisionAccessDialog extends StatefulWidget {
  const _ProvisionAccessDialog({
    required this.personLabel,
    required this.initialEmail,
    required this.currentPassword,
    required this.accessExists,
    required this.onSubmit,
  });

  final String personLabel;
  final String initialEmail;
  final String? currentPassword;
  final bool accessExists;
  final ProvisionAccessSubmit onSubmit;

  @override
  State<_ProvisionAccessDialog> createState() => _ProvisionAccessDialogState();
}

class _ProvisionAccessDialogState extends State<_ProvisionAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();
  bool _saving = false;
  bool _showPassword = false;
  bool _showCurrentPassword = false;

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
    final email = _email.text.trim();
    final initialEmail = widget.initialEmail.trim();
    final emailChanged =
        !widget.accessExists ||
        email.toLowerCase() != initialEmail.toLowerCase();
    final passwordChanged = _password.text.isNotEmpty;
    if (widget.accessExists && !emailChanged && !passwordChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Измените email или укажите новый пароль'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSubmit(
        emailChanged ? email : null,
        passwordChanged ? _password.text : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить доступ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${widget.accessExists ? 'Данные для входа' : 'Создать доступ'}: ${widget.personLabel}',
      ),
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
                  if (email.isEmpty) return 'Укажите email для входа';
                  return email.contains('@')
                      ? null
                      : 'Введите корректный email';
                },
              ),
              if (widget.accessExists) ...[
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: widget.currentPassword ?? '',
                  readOnly: true,
                  enableInteractiveSelection:
                      widget.currentPassword?.isNotEmpty == true,
                  obscureText:
                      widget.currentPassword?.isNotEmpty == true &&
                      !_showCurrentPassword,
                  decoration: InputDecoration(
                    labelText: 'Актуальный пароль',
                    helperText: widget.currentPassword?.isNotEmpty == true
                        ? 'Доступен только директору и администратору системы'
                        : 'Старый пароль нельзя восстановить. Задайте новый — после этого он будет доступен здесь.',
                    suffixIcon: widget.currentPassword?.isNotEmpty == true
                        ? IconButton(
                            tooltip: _showCurrentPassword
                                ? 'Скрыть пароль'
                                : 'Показать пароль',
                            onPressed: () => setState(
                              () =>
                                  _showCurrentPassword = !_showCurrentPassword,
                            ),
                            icon: Icon(
                              _showCurrentPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: widget.accessExists ? 'Новый пароль' : 'Пароль *',
                  helperText: widget.accessExists
                      ? 'Оставьте пустым, чтобы не менять'
                      : passwordMinimumHint,
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
                validator: (value) {
                  final password = value ?? '';
                  if (widget.accessExists && password.isEmpty) return null;
                  return password.length < minPasswordLength
                      ? passwordMinimumError
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordAgain,
                obscureText: !_showPassword,
                decoration: const InputDecoration(
                  labelText: 'Повторите новый пароль',
                ),
                validator: (value) {
                  if (widget.accessExists && _password.text.isEmpty) {
                    return null;
                  }
                  return value != _password.text ? 'Пароли не совпадают' : null;
                },
              ),
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
              : Text(widget.accessExists ? 'Сохранить' : 'Создать доступ'),
        ),
      ],
    );
  }
}
