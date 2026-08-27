import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_model.dart';

typedef StaffDetailLinkCallback = void Function(String value);

class StaffDetailContent extends StatelessWidget {
  const StaffDetailContent({
    super.key,
    required this.controller,
    required this.formKey,
    required this.currentRole,
    required this.onProvision,
    required this.onLifecycle,
    required this.onRole,
    required this.onLink,
    required this.onSave,
    required this.onCancel,
  });

  final StaffDetailController controller;
  final GlobalKey<FormState> formKey;
  final String currentRole;
  final VoidCallback onProvision;
  final VoidCallback onLifecycle;
  final VoidCallback onRole;
  final StaffDetailLinkCallback onLink;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Карточка сотрудника'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: _StaffDetailForm(
              controller: controller,
              currentRole: currentRole,
              onProvision: onProvision,
              onLifecycle: onLifecycle,
              onRole: onRole,
              onLink: onLink,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: controller.saving ? null : onCancel,
          child: Text(
            'Отмена',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        FilledButton(
          onPressed: controller.saving || controller.isArchived ? null : onSave,
          child: controller.saving
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

class _StaffDetailForm extends StatelessWidget {
  const _StaffDetailForm({
    required this.controller,
    required this.currentRole,
    required this.onProvision,
    required this.onLifecycle,
    required this.onRole,
    required this.onLink,
  });

  final StaffDetailController controller;
  final String currentRole;
  final VoidCallback onProvision;
  final VoidCallback onLifecycle;
  final VoidCallback onRole;
  final StaffDetailLinkCallback onLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StaffSummary(controller: controller, currentRole: currentRole),
        _StaffAccessActions(
          controller: controller,
          currentRole: currentRole,
          onProvision: onProvision,
          onLifecycle: onLifecycle,
          onLink: onLink,
        ),
        const SizedBox(height: 12),
        _IdentityFields(controller: controller, currentRole: currentRole),
        const SizedBox(height: 12),
        _AccessRoleField(
          controller: controller,
          currentRole: currentRole,
          onRole: onRole,
        ),
        const SizedBox(height: 12),
        _BranchSelector(controller: controller),
        const SizedBox(height: 12),
        _EmploymentFields(controller: controller),
      ],
    );
  }
}

class _StaffSummary extends StatelessWidget {
  const _StaffSummary({required this.controller, required this.currentRole});

  final StaffDetailController controller;
  final String currentRole;

  @override
  Widget build(BuildContext context) {
    final staff = controller.staff;
    final isAppAccount = controller.isAppAccount;
    final canManageCredentials = canManageStaffCredentials(currentRole);
    final branches = staffBranchesText(staff['branches']);
    final passwordConfigured = staff['password_configured'] == true;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
          icon: Icons.badge_outlined,
          label: 'Роль в системе',
          value: staffRoleLabel(controller.draft.role),
          color: AppTheme.primaryGold,
        ),
        _SummaryChip(
          icon: isAppAccount
              ? Icons.verified_user_rounded
              : Icons.person_off_rounded,
          label: 'Аккаунт',
          value: isAppAccount ? staffRoleLabel(controller.appRole) : 'Нет',
          color: isAppAccount
              ? AppTheme.success
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        if (canManageCredentials)
          _SummaryChip(
            icon: passwordConfigured
                ? Icons.password_rounded
                : Icons.no_encryption_gmailerrorred_rounded,
            label: 'Пароль',
            value: passwordConfigured ? 'Настроен' : 'Не задан',
            color: passwordConfigured
                ? AppTheme.success
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        if (branches.isNotEmpty)
          _SummaryChip(
            icon: Icons.location_on_outlined,
            label: 'Филиалы',
            value: branches,
            color: AppTheme.secondaryGold,
            wide: true,
          ),
      ],
    );
  }
}

class _StaffAccessActions extends StatelessWidget {
  const _StaffAccessActions({
    required this.controller,
    required this.currentRole,
    required this.onProvision,
    required this.onLifecycle,
    required this.onLink,
  });

  final StaffDetailController controller;
  final String currentRole;
  final VoidCallback onProvision;
  final VoidCallback onLifecycle;
  final StaffDetailLinkCallback onLink;

  @override
  Widget build(BuildContext context) {
    final canManage = canManageStaffCredentials(currentRole);
    final linkSearchValue = controller.draft.linkSearchValue();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canManage) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: controller.isArchived ? null : onProvision,
              icon: const Icon(Icons.key_rounded),
              label: Text(
                controller.isAppAccount ? 'Данные для входа' : 'Создать доступ',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onLifecycle,
              icon: Icon(
                controller.isArchived
                    ? Icons.restore_rounded
                    : Icons.person_off_outlined,
              ),
              label: Text(
                controller.isArchived
                    ? 'Восстановить сотрудника'
                    : 'Отключить сотрудника',
              ),
            ),
          ),
        ],
        if (controller.isAppAccount && linkSearchValue != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onLink(linkSearchValue),
              icon: const Icon(Icons.manage_accounts_rounded),
              label: const Text('Найти в пользователях'),
            ),
          ),
        ],
      ],
    );
  }
}

class _IdentityFields extends StatelessWidget {
  const _IdentityFields({required this.controller, required this.currentRole});

  final StaffDetailController controller;
  final String currentRole;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    return Column(
      children: [
        TextFormField(
          initialValue: draft.lastName,
          decoration: const InputDecoration(labelText: 'Фамилия'),
          validator: staffRequiredValidator,
          onChanged: (value) => draft.lastName = value,
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: draft.firstName,
          decoration: const InputDecoration(labelText: 'Имя'),
          validator: staffRequiredValidator,
          onChanged: (value) => draft.firstName = value,
        ),
        const SizedBox(height: 12),
        RuPhoneField(
          initialCanonical: draft.canonicalPhone,
          onCanonicalChanged: controller.setCanonicalPhone,
        ),
        const SizedBox(height: 12),
        if (canManageStaffCredentials(currentRole)) ...[
          TextFormField(
            key: ValueKey(draft.email),
            initialValue: draft.email,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Почта для входа',
              helperText: staffCredentialHelper(controller.staff),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: staffEmailValidator,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AccessRoleField extends StatelessWidget {
  const _AccessRoleField({
    required this.controller,
    required this.currentRole,
    required this.onRole,
  });

  final StaffDetailController controller;
  final String currentRole;
  final VoidCallback onRole;

  @override
  Widget build(BuildContext context) {
    final canChange =
        canManageStaffCredentials(currentRole) &&
        controller.profileUserId.isNotEmpty;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Роль доступа',
        helperText: 'Определяет права пользователя в приложении',
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              staffRoleLabel(
                controller.appRole.isEmpty
                    ? controller.draft.role
                    : controller.appRole,
              ),
            ),
          ),
          if (canChange)
            TextButton(
              key: const Key('staff-change-access-role'),
              onPressed: controller.saving ? null : onRole,
              child: const Text('Изменить'),
            ),
        ],
      ),
    );
  }
}

class _BranchSelector extends StatelessWidget {
  const _BranchSelector({required this.controller});

  final StaffDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Филиалы *'),
        const SizedBox(height: 6),
        if (controller.loadingBranches)
          const Center(child: CircularProgressIndicator())
        else if (controller.branchesError != null)
          Row(
            children: [
              const Expanded(child: Text('Не удалось загрузить филиалы.')),
              TextButton(
                onPressed: controller.loadBranches,
                child: const Text('Повторить'),
              ),
            ],
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final branch in controller.branches)
                FilterChip(
                  label: Text(branch['name']?.toString() ?? 'Филиал'),
                  selected: controller.draft.branchIds.contains(
                    branch['id']?.toString(),
                  ),
                  onSelected: (selected) {
                    final id = branch['id']?.toString();
                    if (id != null) controller.setBranchSelected(id, selected);
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _EmploymentFields extends StatelessWidget {
  const _EmploymentFields({required this.controller});

  final StaffDetailController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    return Column(
      children: [
        TextFormField(
          initialValue: draft.position,
          decoration: const InputDecoration(labelText: 'Должность'),
          onChanged: (value) => draft.position = value,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          menuMaxHeight: 256,
          initialValue: draft.status.isEmpty ? null : draft.status,
          decoration: const InputDecoration(labelText: 'Статус'),
          items: _dropdownItems(draft.status),
          onChanged: (value) {
            if (value != null) controller.setStatus(value);
          },
          validator: staffRequiredValidator,
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: draft.birthday,
          decoration: const InputDecoration(
            labelText: 'Дата рождения',
            hintText: '1990-06-01',
          ),
          onChanged: (value) => draft.birthday = value,
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
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
      width: wide ? 220 : 132,
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

List<DropdownMenuItem<String>> _dropdownItems(String current) {
  return [
    for (final value in staffStatusValues(current))
      DropdownMenuItem<String>(
        value: value,
        child: Text(staffStatusLabels[value] ?? value),
      ),
  ];
}
