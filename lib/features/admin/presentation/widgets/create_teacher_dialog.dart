import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';

Future<bool?> showCreateTeacherSurface(BuildContext context) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Новый преподаватель',
    subtitle: 'Карточка, условия работы и необязательный доступ',
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
  final _identityFormKey = GlobalKey<FormState>();
  final _employmentKey = GlobalKey<TeacherEmploymentFieldsState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();
  String _phone = '';
  bool _saving = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _passwordAgain.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final identityValid = _identityFormKey.currentState?.validate() ?? false;
    final employment = _employmentKey.currentState?.validateAndRead();
    if (!identityValid || employment == null) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTeacher(
            firstName: _firstName.text,
            lastName: _lastName.text,
            phone: _phone,
            email: _email.text.trim().isEmpty ? null : _email.text,
            password: _password.text.isEmpty ? null : _password.text,
            branchIds: employment.branchIds,
            disciplineIds: employment.disciplineIds,
            customDataPatch: employment.customDataPatch,
            salary: employment.salary,
            rate: employment.rate,
            rateEffectiveFrom: employment.rateEffectiveFrom == null
                ? null
                : DateFormat(
                    'yyyy-MM-dd',
                  ).format(employment.rateEffectiveFrom!),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('create-teacher-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Карточку можно создать без аккаунта. Если указать email и пароль, рабочий доступ будет создан и связан с преподавателем одной операцией.',
        ),
        const SizedBox(height: 16),
        Form(
          key: _identityFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _firstName,
                decoration: const InputDecoration(labelText: 'Имя *'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastName,
                decoration: const InputDecoration(labelText: 'Фамилия'),
              ),
              const SizedBox(height: 12),
              RuPhoneField(onCanonicalChanged: (value) => _phone = value),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email для входа (необязательно)',
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) {
                    return _password.text.isEmpty
                        ? null
                        : 'Укажите email вместе с паролем';
                  }
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
                  labelText: 'Пароль (необязательно)',
                  helperText: 'Для доступа — не менее 10 символов',
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
                  if (password.isEmpty) {
                    return _email.text.trim().isEmpty
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
                controller: _passwordAgain,
                obscureText: !_showPassword,
                decoration: const InputDecoration(
                  labelText: 'Повторите пароль',
                ),
                validator: (value) {
                  if (_password.text.isEmpty && (value?.isEmpty ?? true)) {
                    return null;
                  }
                  return value != _password.text ? 'Пароли не совпадают' : null;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        TeacherEmploymentFields(
          key: _employmentKey,
          requireRate: true,
          enabled: !_saving,
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
                    : const Text('Создать'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
