import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_access_flow.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_content.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_controller.dart';

class StaffDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> staff;
  final String currentRole;

  const StaffDetailDialog({
    super.key,
    required this.staff,
    required this.currentRole,
  });

  static Future<bool?> show(
    BuildContext context,
    Map<String, dynamic> staff, {
    required String currentRole,
  }) {
    return showMagicDialog<bool>(
      context: context,
      builder: (_) => StaffDetailDialog(staff: staff, currentRole: currentRole),
    );
  }

  @override
  ConsumerState<StaffDetailDialog> createState() => _StaffDetailDialogState();
}

class _StaffDetailDialogState extends ConsumerState<StaffDetailDialog> {
  final _formKey = GlobalKey<FormState>();
  late final StaffDetailController _controller;
  late final StaffDetailAccessFlow _accessFlow;

  @override
  void initState() {
    super.initState();
    _controller = StaffDetailController(
      crm: ref.read(magicCrmServiceProvider),
      staff: widget.staff,
    )..addListener(_onControllerChanged);
    _accessFlow = StaffDetailAccessFlow(
      controller: _controller,
      currentRole: widget.currentRole,
    );
    unawaited(_controller.loadBranches());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _openUserLinking(String value) {
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(CrmNavigationRequest.userRolesSearch(value));
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _provisionAccess() async {
    try {
      final saved = await _accessFlow.provision(context);
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Доступ сотрудника создан')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(
              error,
              fallback: 'Не удалось получить данные для входа.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _manageLifecycle() async {
    final saved = await _accessFlow.manageLifecycle(context);
    if (saved && mounted) Navigator.pop(context, true);
  }

  Future<void> _changeAccessRole() async {
    final saved = await _accessFlow.changeRole(context);
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Роль доступа обновлена')));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _controller.saving) return;
    try {
      await _controller.save();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Данные сотрудника сохранены')),
      );
    } on StaffDetailValidationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(
              error,
              fallback: 'Не удалось сохранить сотрудника.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StaffDetailContent(
      controller: _controller,
      formKey: _formKey,
      currentRole: widget.currentRole,
      onProvision: _provisionAccess,
      onLifecycle: _manageLifecycle,
      onRole: _changeAccessRole,
      onLink: _openUserLinking,
      onSave: _save,
      onCancel: () => Navigator.pop(context),
    );
  }
}
