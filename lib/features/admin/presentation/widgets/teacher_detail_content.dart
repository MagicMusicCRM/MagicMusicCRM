import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_model.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/personnel_embedded_card_frame.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_settings.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';

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
    required this.actorRole,
    required this.canManageCredentials,
    required this.canManageTeacherRates,
    required this.canOpenSchedule,
    required this.canViewAvailability,
    required this.canEditAvailability,
    required this.saving,
    required this.onOpenSchedule,
    required this.onAccessChanged,
    required this.onProvisionAccess,
    required this.onManageLifecycle,
    required this.onChangeAccessRole,
    this.embedded = false,
  });

  final Map<String, dynamic> teacher;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final String initialPhone;
  final ValueChanged<String> onPhoneChanged;
  final GlobalKey<TeacherEmploymentFieldsState> employmentKey;
  final TeacherEmploymentInitial employmentInitial;
  final TeacherEmploymentReferenceGateway employmentReferenceGateway;
  final String actorRole;
  final bool canManageCredentials;
  final bool canManageTeacherRates;
  final bool canOpenSchedule;
  final bool canViewAvailability;
  final bool canEditAvailability;
  final bool saving;
  final VoidCallback onOpenSchedule;
  final VoidCallback onAccessChanged;
  final VoidCallback onProvisionAccess;
  final VoidCallback onManageLifecycle;
  final VoidCallback onChangeAccessRole;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final identity = _TeacherDetailSection(
      title: 'Основные данные',
      icon: Icons.person_outline_rounded,
      child: Column(
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Имя Фамилия'),
          ),
          const SizedBox(height: 10),
          RuPhoneField(
            initialCanonical: initialPhone,
            onCanonicalChanged: onPhoneChanged,
          ),
        ],
      ),
    );
    final employment = _TeacherDetailSection(
      title: 'Работа, филиалы и оплата',
      icon: Icons.work_outline_rounded,
      child: TeacherEmploymentFields(
        key: employmentKey,
        gateway: employmentReferenceGateway,
        initial: employmentInitial,
        canManageRate: canManageTeacherRates,
        requireRateConfirmation: true,
        enabled: !saving,
      ),
    );
    final scheduleActions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canOpenSchedule)
          OutlinedButton.icon(
            key: const Key('teacher-open-schedule'),
            onPressed: onOpenSchedule,
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('Открыть расписание'),
          ),
      ],
    );
    final access = _TeacherDetailSection(
      title: 'Доступ в приложение',
      icon: Icons.admin_panel_settings_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            const SizedBox(height: 10),
          ],
          _AccessRoleField(
            role: teacher['app_role']?.toString() ?? 'teacher',
            canChange:
                const {'director', 'system_admin'}.contains(actorRole) &&
                (teacher['profile_user_id']?.toString().isNotEmpty ?? false),
            saving: saving,
            onChange: onChangeAccessRole,
          ),
          if (embedded &&
              const {'director', 'system_admin'}.contains(actorRole) &&
              (teacher['profile_user_id']?.toString().isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              key: const Key('teacher-personal-access'),
              title: const Text('Персональные права'),
              subtitle: const Text(
                'Права и исключения для этого преподавателя',
              ),
              children: [
                SizedBox(
                  height: 560,
                  child: AccessEditorSheet(
                    actorRole: actorRole,
                    userId: teacher['profile_user_id'].toString(),
                    userLabel: nameController.text.trim(),
                    embedded: true,
                    onChanged: onAccessChanged,
                  ),
                ),
              ],
            ),
          ],
          if (canManageCredentials) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
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
                OutlinedButton.icon(
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
              ],
            ),
          ],
        ],
      ),
    );
    if (embedded) {
      final teacherId = teacher['id']?.toString();
      Widget section(String name, Widget child) =>
          KeyedSubtree(key: Key('teacher-card-$name'), child: child);
      final profile = section('profile', identity);
      final work = section('employment', employment);
      final schedule = section(
        'schedule',
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.75),
            ),
          ),
          child: teacherId == null || teacherId.isEmpty
              ? const Center(
                  child: Text('Не удалось определить преподавателя.'),
                )
              : ScheduleReferenceSettings(
                  canEdit: canEditAvailability,
                  section: ScheduleReferenceSection.teacherSchedule,
                  initialTeacherId: teacherId,
                  lockedTeacherId: teacherId,
                  inline: true,
                ),
        ),
      );
      final permissions = section('access', access);
      final history = section(
        'history',
        PersonnelHistorySummary(
          createdAt: teacher['created_at'] ?? teacher['createdAt'],
          lifecycleState: teacher['lifecycle_state']?.toString() ?? 'active',
          offboardedAt: teacher['offboarded_at'] ?? teacher['offboardedAt'],
          offboardReason:
              teacher['offboard_reason'] ?? teacher['offboardReason'],
          personId: teacherId,
          personType: 'teacher',
          canViewActivity: canManageCredentials,
        ),
      );
      return PersonnelCardCanvas(
        summary: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TeacherDetailSummary(
              teacher: teacher,
              canManageCredentials: canManageCredentials,
            ),
            if (scheduleActions.children.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              scheduleActions,
            ],
          ],
        ),
        desktopLeft: [profile, work],
        desktopRight: [if (canViewAvailability) schedule, permissions, history],
        mobileSections: [
          profile,
          if (canViewAvailability) schedule,
          work,
          permissions,
          history,
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final details = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: identity),
                  const SizedBox(width: 14),
                  Expanded(flex: 6, child: employment),
                ],
              )
            : Column(
                children: [identity, const SizedBox(height: 12), employment],
              );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TeacherDetailSummary(
              teacher: teacher,
              canManageCredentials: canManageCredentials,
            ),
            if (scheduleActions.children.isNotEmpty) ...[
              const SizedBox(height: 10),
              scheduleActions,
            ],
            const SizedBox(height: 12),
            details,
            const SizedBox(height: 12),
            access,
          ],
        );
      },
    );
  }
}

class _TeacherDetailSection extends StatelessWidget {
  const _TeacherDetailSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.xl,
              vertical: AppSpace.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: AppColor.gold),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
          Padding(padding: const EdgeInsets.all(AppSpace.lg), child: child),
        ],
      ),
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PersonnelMetricChip(
          icon: Icons.school_rounded,
          label: 'Ученики',
          value: teacherDetailInt(teacher['students_count']).toString(),
        ),
        if (canManageCredentials)
          PersonnelMetricChip(
            icon: teacher['password_configured'] == true
                ? Icons.password_rounded
                : Icons.no_encryption_gmailerrorred_rounded,
            label: 'Пароль',
            value: teacher['password_configured'] == true
                ? 'Настроен'
                : 'Не задан',
          ),
        PersonnelMetricChip(
          icon: Icons.event_available_rounded,
          label: 'Занятия',
          value: teacherDetailInt(teacher['lessons_count']).toString(),
        ),
        if (rating > 0)
          PersonnelMetricChip(
            icon: Icons.star_rounded,
            label: 'Рейтинг',
            value: rating.toStringAsFixed(1),
          ),
        PersonnelMetricChip(
          icon: hasAccount
              ? Icons.verified_user_rounded
              : Icons.person_off_rounded,
          label: 'Аккаунт',
          value: hasAccount
              ? teacherDetailRoleLabel(teacher['app_role']?.toString() ?? '')
              : 'Нет',
        ),
        if (branches.isNotEmpty)
          PersonnelMetricChip(
            icon: Icons.location_on_outlined,
            label: 'Филиалы',
            value: branches,
            wide: true,
          ),
      ],
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
