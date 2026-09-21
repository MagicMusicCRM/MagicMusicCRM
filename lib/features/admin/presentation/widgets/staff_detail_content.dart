import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_model.dart';

import 'personnel_embedded_card_frame.dart';

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
    this.embedded = false,
    this.onClose,
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
  final bool embedded;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final form = Form(
      key: formKey,
      child: _StaffDetailForm(
        controller: controller,
        currentRole: currentRole,
        onProvision: onProvision,
        onLifecycle: onLifecycle,
        onRole: onRole,
        onLink: onLink,
        embedded: embedded,
      ),
    );
    final saveButton = FilledButton.icon(
      key: const Key('staff-detail-save'),
      onPressed: controller.saving || controller.isArchived ? null : onSave,
      icon: controller.saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_outlined, size: 18),
      label: Text(controller.saving ? 'Сохранение…' : 'Сохранить'),
    );
    if (embedded) {
      return PersonnelEmbeddedCardFrame(
        key: const Key('staff-detail-embedded'),
        title: 'Карточка сотрудника',
        icon: Icons.badge_outlined,
        body: form,
        action: saveButton,
        saving: controller.saving,
        onClose: onClose,
      );
    }
    return AlertDialog(
      title: const Text('Карточка сотрудника'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: form)),
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
        saveButton,
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
    required this.embedded,
  });

  final StaffDetailController controller;
  final String currentRole;
  final VoidCallback onProvision;
  final VoidCallback onLifecycle;
  final VoidCallback onRole;
  final StaffDetailLinkCallback onLink;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final identity = _StaffDetailSection(
      title: 'Основные данные и доступ',
      child: Column(
        children: [
          _IdentityFields(controller: controller, currentRole: currentRole),
          _AccessRoleField(
            controller: controller,
            currentRole: currentRole,
            onRole: onRole,
          ),
        ],
      ),
    );
    final employment = _StaffDetailSection(
      title: 'Работа и филиалы',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BranchSelector(controller: controller),
          const SizedBox(height: 12),
          _EmploymentFields(controller: controller),
        ],
      ),
    );
    final access = _StaffDetailSection(
      title: 'Доступ в приложение',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccessRoleField(
            controller: controller,
            currentRole: currentRole,
            onRole: onRole,
          ),
          _StaffAccessActions(
            controller: controller,
            currentRole: currentRole,
            onProvision: onProvision,
            onLifecycle: onLifecycle,
            onLink: onLink,
          ),
        ],
      ),
    );
    if (embedded) {
      final staff = controller.staff;
      return PersonnelSectionedCardBody(
        keyPrefix: 'staff',
        sections: [
          PersonnelCardSection(
            id: 'overview',
            label: 'Обзор',
            icon: Icons.dashboard_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StaffSummary(controller: controller, currentRole: currentRole),
                const SizedBox(height: 12),
                _StaffDetailSection(
                  title: 'Основные данные',
                  child: _IdentityFields(
                    controller: controller,
                    currentRole: currentRole,
                  ),
                ),
              ],
            ),
          ),
          PersonnelCardSection(
            id: 'employment',
            label: 'Работа и филиалы',
            icon: Icons.work_outline_rounded,
            child: employment,
          ),
          PersonnelCardSection(
            id: 'access',
            label: 'Доступ',
            icon: Icons.admin_panel_settings_outlined,
            child: access,
          ),
          PersonnelCardSection(
            id: 'history',
            label: 'История',
            icon: Icons.history_rounded,
            child: PersonnelHistorySummary(
              createdAt: staff['created_at'] ?? staff['createdAt'],
              lifecycleState: staff['lifecycle_state']?.toString() ?? 'active',
              offboardedAt: staff['offboarded_at'] ?? staff['offboardedAt'],
              offboardReason:
                  staff['offboard_reason'] ?? staff['offboardReason'],
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
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
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 14),
                  Expanded(child: employment),
                ],
              )
            else ...[
              identity,
              const SizedBox(height: 12),
              employment,
            ],
          ],
        );
      },
    );
  }
}

class _StaffDetailSection extends StatelessWidget {
  const _StaffDetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          child,
        ],
      ),
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
        PersonnelMetricChip(
          icon: Icons.badge_outlined,
          label: 'Роль в системе',
          value: staffRoleLabel(controller.draft.role),
          color: AppTheme.primaryGold,
        ),
        PersonnelMetricChip(
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
          PersonnelMetricChip(
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
          PersonnelMetricChip(
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
        AppDropdownButtonFormField<String>(
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

List<DropdownMenuItem<String>> _dropdownItems(String current) {
  return [
    for (final value in staffStatusValues(current))
      DropdownMenuItem<String>(
        value: value,
        child: Text(staffStatusLabels[value] ?? value),
      ),
  ];
}
