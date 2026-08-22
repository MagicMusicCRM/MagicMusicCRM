import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/security/password_policy.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_access_role_dialog.dart';

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
  String _accessRole = 'teacher';
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
            accessRole: _accessRole,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(
                error,
                fallback: 'Не удалось создать преподавателя.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

  @override
  Widget build(BuildContext context) {
    final actorRole =
        ref.watch(capabilitySnapshotProvider).asData?.value.role ?? '';
    final accessRoles = personAccessRoleOptions(
      actorRole: actorRole,
      teacher: true,
    );
    return Column(
      key: const ValueKey('create-teacher-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Карточку можно создать без доступа. Почту и пароль можно добавить сейчас или позже.',
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
                  labelText: 'Почта для входа (необязательно)',
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) {
                    return _password.text.isEmpty
                        ? null
                        : 'Укажите почту вместе с паролем';
                  }
                  return email.contains('@')
                      ? null
                      : 'Введите корректный адрес почты';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Пароль (необязательно)',
                  helperText: 'Для доступа: $passwordMinimumHint',
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
                        : 'Укажите пароль вместе с почтой';
                  }
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
                  labelText: 'Повторите пароль',
                ),
                validator: (value) {
                  if (_password.text.isEmpty && (value?.isEmpty ?? true)) {
                    return null;
                  }
                  return value != _password.text ? 'Пароли не совпадают' : null;
                },
              ),
              if (accessRoles.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const Key('create-teacher-access-role'),
                  initialValue: accessRoles.contains(_accessRole)
                      ? _accessRole
                      : accessRoles.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Роль доступа *',
                  ),
                  items: [
                    for (final role in accessRoles)
                      DropdownMenuItem(
                        value: role,
                        child: Text(personAccessRoleLabels[role] ?? role),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) =>
                            setState(() => _accessRole = value ?? 'teacher'),
                ),
              ],
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
