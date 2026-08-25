import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_access_role_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_lifecycle_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/provision_access_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_access_flow.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_content.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_model.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_save_command.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_dialogs.dart';

class TeacherDetailDialog extends ConsumerStatefulWidget {
  const TeacherDetailDialog({super.key, required this.teacher});

  final Map<String, dynamic> teacher;

  static Future<bool?> show(
    BuildContext context,
    Map<String, dynamic> teacher,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (_) => TeacherDetailDialog(teacher: teacher),
    );
  }

  @override
  ConsumerState<TeacherDetailDialog> createState() =>
      _TeacherDetailDialogState();
}

class _TeacherDetailDialogState extends ConsumerState<TeacherDetailDialog> {
  late Map<String, dynamic> _teacher;
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late String _canonicalPhone;
  late final TeacherEmploymentInitial _employmentInitial;
  late final TeacherPayrollController _payrollController;
  final _employmentKey = GlobalKey<TeacherEmploymentFieldsState>();
  bool _saving = false;

  String get _teacherId => _teacher['id'].toString();
  String get _actorRole =>
      ref.read(capabilitySnapshotProvider).asData?.value.role ?? '';

  @override
  void initState() {
    super.initState();
    final initial = TeacherDetailInitialData.fromTeacher(widget.teacher);
    _teacher = initial.teacher;
    _nameController = TextEditingController(text: initial.name);
    _emailController = TextEditingController(text: initial.email);
    _canonicalPhone = initial.phone;
    _employmentInitial = initial.employment;
    _payrollController = TeacherPayrollController(
      service: ref.read(magicCrmServiceProvider),
      teacherId: _teacherId,
    )..load();
  }

  @override
  void dispose() {
    _payrollController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      _showMessage('Укажите имя преподавателя.');
      return;
    }
    final employment = _employmentKey.currentState?.validateAndRead();
    if (employment == null) return;
    final payrollChanged = employment.salaryChanged || employment.rateChanged;
    int? payrollExpectedVersion;
    String? payrollReasonText;
    if (payrollChanged) {
      payrollExpectedVersion = _payrollController.expectedVersion;
      if (payrollExpectedVersion == null || _payrollController.error != null) {
        _showMessage(
          'Не удалось проверить версию расчётов. '
          'Обновите блок оплат и повторите.',
        );
        return;
      }
      payrollReasonText = await showTeacherEmploymentChangeReasonDialog(
        context,
        employment: employment,
        initial: _employmentInitial,
      );
      if (payrollReasonText == null || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final command = TeacherDetailSaveCommand.fromEditor(
        name: _nameController.text,
        phone: _canonicalPhone,
        employment: employment,
        payrollExpectedVersion: payrollExpectedVersion,
        payrollReasonText: payrollReasonText,
      );
      await command.execute(ref.read(magicCrmServiceProvider), _teacherId);
      if (!mounted) return;
      Navigator.pop(context, true);
      _showMessage('Данные сохранены');
    } catch (error) {
      if (mounted) {
        _showMessage(
          userErrorMessage(
            error,
            fallback: 'Не удалось сохранить преподавателя.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _provisionAccess() async {
    final accessExists = _teacher['is_app_account'] == true;
    final updated = await TeacherDetailAccessFlow.run(
      service: ref.read(magicCrmServiceProvider),
      teacherId: _teacherId,
      currentEmail: _emailController.text,
      accessExists: accessExists,
      onLoadError: (error) {
        if (!mounted) return;
        _showMessage(
          userErrorMessage(
            error,
            fallback: 'Не удалось получить данные для входа.',
          ),
        );
      },
      showDialog:
          ({required initialEmail, currentPassword, required onSubmit}) {
            return showProvisionAccessDialog(
              context,
              personLabel: _nameController.text.trim(),
              initialEmail: initialEmail,
              currentPassword: currentPassword,
              accessExists: accessExists,
              onSubmit: onSubmit,
            );
          },
    );
    if (mounted && updated != null) {
      setState(() {
        _teacher = updated;
        _emailController.text = updated['email']?.toString() ?? '';
      });
      _showMessage('Доступ преподавателя создан');
    }
  }

  Future<void> _manageLifecycle() async {
    final saved = await showPersonLifecycleDialog(
      context,
      personType: 'teacher',
      personId: _teacherId,
      personName: _nameController.text.trim(),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _changeAccessRole() async {
    final userId = _teacher['profile_user_id']?.toString() ?? '';
    if (userId.isEmpty) return;
    final role = await showPersonAccessRoleDialog(
      context,
      actorRole: _actorRole,
      userId: userId,
      personLabel: _nameController.text.trim(),
      teacher: true,
    );
    if (role == null || !mounted) return;
    setState(() => _teacher = {..._teacher, 'app_role': role});
    _showMessage('Роль доступа обновлена');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(capabilitySnapshotProvider).asData?.value.role ?? '';
    final canManageCredentials = const {
      'director',
      'system_admin',
    }.contains(role);
    return AlertDialog(
      title: const Text('Карточка преподавателя'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: TeacherDetailContent(
            teacher: _teacher,
            nameController: _nameController,
            emailController: _emailController,
            initialPhone: _canonicalPhone,
            onPhoneChanged: (phone) => _canonicalPhone = phone,
            employmentKey: _employmentKey,
            employmentInitial: _employmentInitial,
            payrollController: _payrollController,
            actorRole: role,
            canManageCredentials: canManageCredentials,
            saving: _saving,
            onProvisionAccess: _provisionAccess,
            onManageLifecycle: _manageLifecycle,
            onChangeAccessRole: _changeAccessRole,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(
            'Отмена',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        FilledButton(
          onPressed: _saving || _teacher['lifecycle_state'] == 'archived'
              ? null
              : _save,
          child: _saving
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
