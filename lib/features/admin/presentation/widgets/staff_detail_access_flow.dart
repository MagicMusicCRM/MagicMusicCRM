import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_access_role_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_lifecycle_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/provision_access_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_controller.dart';

class StaffDetailAccessFlow {
  const StaffDetailAccessFlow({
    required this.controller,
    required this.currentRole,
  });

  final StaffDetailController controller;
  final String currentRole;

  Future<bool> provision(BuildContext context) async {
    if (controller.isArchived) return false;
    Map<String, dynamic>? credentials;
    if (controller.isAppAccount) {
      credentials = await controller.loadCredentials();
    }
    if (!context.mounted) return false;

    Map<String, dynamic>? updated;
    final saved = await showProvisionAccessDialog(
      context,
      personLabel: controller.draft.personLabel,
      initialEmail: credentials?['email']?.toString() ?? controller.draft.email,
      currentPassword: credentials?['password']?.toString(),
      accessExists: controller.isAppAccount,
      onSubmit: (email, password) async {
        updated = await controller.provisionAccess(
          email: email,
          password: password,
        );
      },
    );
    return saved == true && updated != null;
  }

  Future<bool> manageLifecycle(BuildContext context) async {
    final id = controller.staff['id']?.toString() ?? '';
    if (id.isEmpty) return false;
    final saved = await showPersonLifecycleDialog(
      context,
      personType: 'staff',
      personId: id,
      personName: controller.draft.personLabel,
    );
    return saved == true;
  }

  Future<bool> changeRole(BuildContext context) async {
    final userId = controller.profileUserId;
    if (userId.isEmpty) return false;
    final selectedRole = await showPersonAccessRoleDialog(
      context,
      actorRole: currentRole,
      userId: userId,
      personLabel: controller.draft.personLabel,
      teacher: false,
    );
    if (selectedRole == null) return false;
    controller.applyAccessRole(selectedRole);
    return true;
  }
}
