import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_model.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';

class StaffAccessBody extends StatelessWidget {
  const StaffAccessBody({
    super.key,
    required this.controller,
    required this.currentRole,
    required this.roleField,
    required this.actions,
    required this.onAccessChanged,
    required this.embedded,
  });

  final StaffDetailController controller;
  final String currentRole;
  final Widget roleField;
  final Widget actions;
  final VoidCallback onAccessChanged;
  final bool embedded;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (canManageStaffCredentials(currentRole)) ...[
        TextFormField(
          key: ValueKey('staff-access-email-${controller.draft.email}'),
          initialValue: controller.draft.email,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Почта для входа',
            helperText: staffCredentialHelper(controller.staff),
          ),
        ),
        const SizedBox(height: 12),
      ],
      roleField,
      actions,
      if (embedded &&
          canManageStaffCredentials(currentRole) &&
          controller.profileUserId.isNotEmpty) ...[
        const SizedBox(height: 12),
        ExpansionTile(
          key: const Key('staff-personal-access'),
          title: const Text('Персональные права'),
          subtitle: const Text('Права и исключения для этого сотрудника'),
          children: [
            SizedBox(
              height: 560,
              child: AccessEditorSheet(
                actorRole: currentRole,
                userId: controller.profileUserId,
                userLabel:
                    '${controller.draft.firstName} ${controller.draft.lastName}'
                        .trim(),
                embedded: true,
                onChanged: onAccessChanged,
              ),
            ),
          ],
        ),
      ],
    ],
  );
}
