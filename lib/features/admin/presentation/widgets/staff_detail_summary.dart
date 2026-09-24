import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_model.dart';

import 'personnel_embedded_card_frame.dart';

typedef StaffSummaryLinkCallback = void Function(String value);

class StaffSummary extends StatelessWidget {
  const StaffSummary({
    super.key,
    required this.controller,
    required this.currentRole,
  });

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
        ),
        PersonnelMetricChip(
          icon: isAppAccount
              ? Icons.verified_user_rounded
              : Icons.person_off_rounded,
          label: 'Аккаунт',
          value: isAppAccount ? staffRoleLabel(controller.appRole) : 'Нет',
        ),
        if (canManageCredentials)
          PersonnelMetricChip(
            icon: passwordConfigured
                ? Icons.password_rounded
                : Icons.no_encryption_gmailerrorred_rounded,
            label: 'Пароль',
            value: passwordConfigured ? 'Настроен' : 'Не задан',
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

class StaffAccessActions extends StatelessWidget {
  const StaffAccessActions({
    super.key,
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
  final StaffSummaryLinkCallback onLink;

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

PersonnelCardSection buildStaffHistorySection(
  Map<String, dynamic> staff, {
  required bool canViewActivity,
}) {
  return PersonnelCardSection(
    id: 'history',
    label: 'История',
    icon: Icons.history_rounded,
    lazy: true,
    child: PersonnelHistorySummary(
      createdAt: staff['created_at'] ?? staff['createdAt'],
      lifecycleState: staff['lifecycle_state']?.toString() ?? 'active',
      offboardedAt: staff['offboarded_at'] ?? staff['offboardedAt'],
      offboardReason: staff['offboard_reason'] ?? staff['offboardReason'],
      personId: staff['id']?.toString(),
      personType: 'staff',
      canViewActivity: canViewActivity,
    ),
  );
}
