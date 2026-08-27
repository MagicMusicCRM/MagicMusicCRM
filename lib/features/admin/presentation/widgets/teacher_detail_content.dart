import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_model.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_section.dart';

import 'teacher_employment_reference_gateway.dart';

class TeacherDetailContent extends StatelessWidget {
  const TeacherDetailContent({
    super.key,
    required this.teacher,
    required this.nameController,
    required this.emailController,
    required this.initialPhone,
    required this.onPhoneChanged,
    required this.employmentKey,
    required this.employmentInitial,
    required this.employmentReferenceGateway,
    required this.payrollController,
    required this.actorRole,
    required this.canManageCredentials,
    required this.saving,
    required this.onProvisionAccess,
    required this.onManageLifecycle,
    required this.onChangeAccessRole,
  });

  final Map<String, dynamic> teacher;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final String initialPhone;
  final ValueChanged<String> onPhoneChanged;
  final GlobalKey<TeacherEmploymentFieldsState> employmentKey;
  final TeacherEmploymentInitial employmentInitial;
  final TeacherEmploymentReferenceGateway employmentReferenceGateway;
  final TeacherPayrollController payrollController;
  final String actorRole;
  final bool canManageCredentials;
  final bool saving;
  final VoidCallback onProvisionAccess;
  final VoidCallback onManageLifecycle;
  final VoidCallback onChangeAccessRole;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TeacherDetailSummary(
          teacher: teacher,
          canManageCredentials: canManageCredentials,
        ),
        if (canManageCredentials) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: teacher['lifecycle_state'] == 'archived'
                  ? null
                  : onProvisionAccess,
              icon: const Icon(Icons.key_rounded),
              label: Text(
                teacher['is_app_account'] == true
                    ? 'Данные для входа'
                    : 'Создать доступ',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onManageLifecycle,
              icon: Icon(
                teacher['lifecycle_state'] == 'archived'
                    ? Icons.restore_rounded
                    : Icons.person_off_outlined,
              ),
              label: Text(
                teacher['lifecycle_state'] == 'archived'
                    ? 'Восстановить преподавателя'
                    : 'Отключить преподавателя',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TeacherPayrollSection(
          controller: payrollController,
          canManageHistory: canManageCredentials,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Имя Фамилия'),
        ),
        const SizedBox(height: 12),
        RuPhoneField(
          initialCanonical: initialPhone,
          onCanonicalChanged: onPhoneChanged,
        ),
        const SizedBox(height: 12),
        if (canManageCredentials) ...[
          TextField(
            controller: emailController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Почта для входа',
              helperText: teacherDetailCredentialHelper(teacher),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
        ],
        _AccessRoleField(
          role: teacher['app_role']?.toString() ?? 'teacher',
          canChange:
              const {'director', 'system_admin'}.contains(actorRole) &&
              (teacher['profile_user_id']?.toString().isNotEmpty ?? false),
          saving: saving,
          onChange: onChangeAccessRole,
        ),
        const SizedBox(height: 22),
        TeacherEmploymentFields(
          key: employmentKey,
          gateway: employmentReferenceGateway,
          initial: employmentInitial,
          enabled: !saving,
        ),
      ],
    );
  }
}

class TeacherDetailSummary extends StatelessWidget {
  const TeacherDetailSummary({
    super.key,
    required this.teacher,
    required this.canManageCredentials,
  });

  final Map<String, dynamic> teacher;
  final bool canManageCredentials;

  @override
  Widget build(BuildContext context) {
    final branches = teacherDetailBranchesText(teacher['branches']);
    final rating = teacherDetailNum(teacher['rating']);
    final hasAccount = teacher['is_app_account'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(90),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _TeacherMetric(
            icon: Icons.school_rounded,
            label: 'Ученики',
            value: teacherDetailInt(teacher['students_count']).toString(),
            color: AppTheme.primaryGold,
          ),
          if (canManageCredentials)
            _TeacherMetric(
              icon: teacher['password_configured'] == true
                  ? Icons.password_rounded
                  : Icons.no_encryption_gmailerrorred_rounded,
              label: 'Пароль',
              value: teacher['password_configured'] == true
                  ? 'Настроен'
                  : 'Не задан',
              color: teacher['password_configured'] == true
                  ? AppTheme.success
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          _TeacherMetric(
            icon: Icons.event_available_rounded,
            label: 'Занятия',
            value: teacherDetailInt(teacher['lessons_count']).toString(),
            color: AppTheme.success,
          ),
          if (rating > 0)
            _TeacherMetric(
              icon: Icons.star_rounded,
              label: 'Рейтинг',
              value: rating.toStringAsFixed(1),
              color: AppTheme.secondaryGold,
            ),
          _TeacherMetric(
            icon: hasAccount
                ? Icons.verified_user_rounded
                : Icons.person_off_rounded,
            label: 'Аккаунт',
            value: hasAccount
                ? teacherDetailRoleLabel(teacher['app_role']?.toString() ?? '')
                : 'Нет',
            color: hasAccount
                ? AppTheme.success
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          if (branches.isNotEmpty)
            _TeacherMetric(
              icon: Icons.location_on_outlined,
              label: 'Филиалы',
              value: branches,
              color: AppTheme.primaryGold,
              wide: true,
            ),
        ],
      ),
    );
  }
}

class _AccessRoleField extends StatelessWidget {
  const _AccessRoleField({
    required this.role,
    required this.canChange,
    required this.saving,
    required this.onChange,
  });

  final String role;
  final bool canChange;
  final bool saving;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Роль доступа',
        helperText: 'Определяет права пользователя в приложении',
      ),
      child: Row(
        children: [
          Expanded(child: Text(teacherDetailRoleLabel(role))),
          if (canChange)
            TextButton(
              key: const Key('teacher-change-access-role'),
              onPressed: saving ? null : onChange,
              child: const Text('Изменить'),
            ),
        ],
      ),
    );
  }
}

class _TeacherMetric extends StatelessWidget {
  const _TeacherMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? 220 : 118,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(54)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
