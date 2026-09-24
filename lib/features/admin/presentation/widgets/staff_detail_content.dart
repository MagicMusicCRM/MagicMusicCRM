import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_model.dart';

import 'personnel_embedded_card_frame.dart';
import 'staff_detail_summary.dart';
import 'staff_detail_access_section.dart';

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
    required this.onAccessChanged,
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
  final VoidCallback onAccessChanged;
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
        onAccessChanged: onAccessChanged,
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
      label: Text(
        controller.saving
            ? 'Сохранение профиля…'
            : embedded
            ? 'Сохранить профиль'
            : 'Сохранить',
      ),
    );
    if (embedded) {
      return PersonnelEmbeddedCardFrame(
        key: const Key('staff-detail-embedded'),
        title: 'Карточка сотрудника',
        icon: Icons.badge_outlined,
        personName: '${controller.draft.firstName} ${controller.draft.lastName}'
            .trim(),
        statusLabel: controller.isArchived ? 'В архиве' : 'Активен',
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
    required this.onAccessChanged,
    required this.onLink,
    required this.embedded,
  });

  final StaffDetailController controller;
  final String currentRole;
  final VoidCallback onProvision;
  final VoidCallback onLifecycle;
  final VoidCallback onRole;
  final VoidCallback onAccessChanged;
  final StaffDetailLinkCallback onLink;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final identity = _StaffDetailSection(
      title: 'Основные данные и доступ',
      icon: Icons.person_outline_rounded,
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
      icon: Icons.work_outline_rounded,
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
      icon: Icons.admin_panel_settings_outlined,
      child: StaffAccessBody(
        controller: controller,
        currentRole: currentRole,
        roleField: _AccessRoleField(
          controller: controller,
          currentRole: currentRole,
          onRole: onRole,
        ),
        actions: StaffAccessActions(
          controller: controller,
          currentRole: currentRole,
          onProvision: onProvision,
          onLifecycle: onLifecycle,
          onLink: onLink,
        ),
        onAccessChanged: onAccessChanged,
        embedded: embedded,
      ),
    );
    if (embedded) {
      final staff = controller.staff;
      Widget section(String name, Widget child) =>
          KeyedSubtree(key: Key('staff-card-$name'), child: child);
      final profile = section(
        'profile',
        _StaffDetailSection(
          title: 'Основные данные',
          icon: Icons.person_outline_rounded,
          child: _IdentityFields(
            controller: controller,
            currentRole: currentRole,
            showAccessEmail: false,
          ),
        ),
      );
      final work = section('employment', employment);
      final permissions = section('access', access);
      final history = section(
        'history',
        PersonnelHistorySummary(
          createdAt: staff['created_at'] ?? staff['createdAt'],
          lifecycleState: staff['lifecycle_state']?.toString() ?? 'active',
          offboardedAt: staff['offboarded_at'] ?? staff['offboardedAt'],
          offboardReason: staff['offboard_reason'] ?? staff['offboardReason'],
          personId: staff['id']?.toString(),
          personType: 'staff',
          canViewActivity: canManageStaffCredentials(currentRole),
        ),
      );
      return PersonnelCardCanvas(
        summary: StaffSummary(controller: controller, currentRole: currentRole),
        desktopLeft: [profile, work],
        desktopRight: [permissions, history],
        mobileSections: [profile, work, permissions, history],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaffSummary(controller: controller, currentRole: currentRole),
            StaffAccessActions(
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
  const _StaffDetailSection({
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

class _IdentityFields extends StatelessWidget {
  const _IdentityFields({
    required this.controller,
    required this.currentRole,
    this.showAccessEmail = true,
  });

  final StaffDetailController controller;
  final String currentRole;
  final bool showAccessEmail;

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
        if (showAccessEmail && canManageStaffCredentials(currentRole)) ...[
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
