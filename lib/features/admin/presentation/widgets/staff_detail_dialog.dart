import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/provision_access_dialog.dart';

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
    return showDialog<bool>(
      context: context,
      builder: (_) => StaffDetailDialog(staff: staff, currentRole: currentRole),
    );
  }

  @override
  ConsumerState<StaffDetailDialog> createState() => _StaffDetailDialogState();
}

class _StaffDetailDialogState extends ConsumerState<StaffDetailDialog> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, dynamic> _staff;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _positionController;
  late TextEditingController _birthdayController;
  late String _canonicalPhone;
  late String _role;
  late String _status;
  List<Map<String, dynamic>> _allBranches = const [];
  final Set<String> _branchIds = {};
  bool _loadingBranches = true;
  String? _branchesError;
  bool _saving = false;

  static const _roleLabels = {
    'manager': 'Управляющий',
    'director': 'Директор',
    'admin': 'Администратор',
    'system_admin': 'Администратор системы',
  };

  static const _statusLabels = {
    'working': 'Работает',
    'active': 'Активен',
    'inactive': 'Неактивен',
    'archived': 'В архиве',
  };

  @override
  void initState() {
    super.initState();
    _staff = Map<String, dynamic>.from(widget.staff);
    final profile = _profile;
    final customData = _customData;
    _firstNameController = TextEditingController(
      text: _staff['first_name']?.toString() ?? profile['first_name'] ?? '',
    );
    _lastNameController = TextEditingController(
      text: _staff['last_name']?.toString() ?? profile['last_name'] ?? '',
    );
    _canonicalPhone =
        _staff['phone']?.toString() ?? profile['phone']?.toString() ?? '';
    _emailController = TextEditingController(
      text: _staff['email']?.toString() ?? '',
    );
    _positionController = TextEditingController(
      text: _staff['position']?.toString() ?? '',
    );
    _birthdayController = TextEditingController(
      text: customData['birthday']?.toString() ?? '',
    );
    _role = _staff['role']?.toString().trim() ?? '';
    _status = _staff['status']?.toString().trim() ?? '';
    final branches = _staff['branches'];
    if (branches is List) {
      for (final branch in branches) {
        if (branch is Map && branch['id'] != null) {
          _branchIds.add(branch['id'].toString());
        }
      }
    }
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await ref.read(magicCrmServiceProvider).listBranches();
      if (!mounted) return;
      setState(() {
        _allBranches = branches;
        _loadingBranches = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingBranches = false;
        _branchesError = '$error';
      });
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _positionController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _profile {
    final value = _staff['profiles'];
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  Map<String, dynamic> get _customData {
    final value = _staff['custom_data'];
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  String? _linkSearchValue() {
    final phone = _canonicalPhone.trim();
    if (phone.isNotEmpty) return phone;
    final email = _emailController.text.trim().toLowerCase();
    if (email.isNotEmpty &&
        !email.endsWith('@local.magicmusiccrm.invalid') &&
        !email.endsWith('@migration.invalid')) {
      return email;
    }
    return null;
  }

  void _openUserLinking(String value) {
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(CrmNavigationRequest.userRolesSearch(value));
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Map<String, String> get _provisionRoles => switch (widget.currentRole) {
    'system_admin' => const {
      'admin': 'Администратор',
      'manager': 'Управляющий',
      'director': 'Директор',
      'system_admin': 'Администратор системы',
    },
    'director' => const {'admin': 'Администратор', 'manager': 'Управляющий'},
    _ => const {'admin': 'Администратор'},
  };

  Future<void> _provisionAccess() async {
    final id = _staff['id']?.toString();
    if (id == null || id.isEmpty) return;
    Map<String, dynamic>? updated;
    final currentRole = _staff['role']?.toString();
    final roles = _provisionRoles;
    final saved = await showProvisionAccessDialog(
      context,
      personLabel: '${_lastNameController.text} ${_firstNameController.text}'
          .trim(),
      initialEmail: _emailController.text,
      roles: roles,
      initialRole: roles.containsKey(currentRole)
          ? currentRole
          : roles.keys.first,
      onSubmit: (email, password, role) async {
        updated = await ref
            .read(magicCrmServiceProvider)
            .provisionStaffAccess(
              staffId: id,
              email: email,
              password: password,
              role: role!,
            );
      },
    );
    if (saved == true && mounted && updated != null) {
      setState(() {
        _staff = updated!;
        _emailController.text = updated!['email']?.toString() ?? '';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Доступ сотрудника создан')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    if (_branchIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы один филиал.')),
      );
      return;
    }
    final id = _staff['id']?.toString();
    if (id == null || id.isEmpty) return;

    setState(() => _saving = true);
    try {
      final currentBirthday = _customData['birthday']?.toString() ?? '';
      final birthday = _birthdayController.text.trim();
      final customDataPatch = <String, dynamic>{};
      if (birthday.isNotEmpty && birthday != currentBirthday) {
        customDataPatch['birthday'] = birthday;
      }

      await ref
          .read(magicCrmServiceProvider)
          .updateStaff(
            id,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            phone: _canonicalPhone,
            email: _emailController.text,
            role: _role,
            position: _positionController.text,
            status: _status,
            branchIds: _branchIds.toList(),
            customDataPatch: customDataPatch,
          );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Данные сотрудника сохранены')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить сотрудника: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkSearchValue = _linkSearchValue();
    final branches = _branchesText(_staff['branches']);
    final isAppAccount = _staff['is_app_account'] == true;
    final appRole = _staff['app_role']?.toString() ?? '';

    return AlertDialog(
      title: const Text('Карточка сотрудника'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(
                      icon: Icons.badge_outlined,
                      label: 'CRM роль',
                      value: _staffRoleLabel(_role),
                      color: AppTheme.primaryGold,
                    ),
                    _SummaryChip(
                      icon: isAppAccount
                          ? Icons.verified_user_rounded
                          : Icons.person_off_rounded,
                      label: 'Аккаунт',
                      value: isAppAccount ? _staffRoleLabel(appRole) : 'Нет',
                      color: isAppAccount
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
                ),
                if (!isAppAccount) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _provisionAccess,
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('Создать доступ'),
                    ),
                  ),
                ] else if (linkSearchValue != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _openUserLinking(linkSearchValue),
                      icon: const Icon(Icons.manage_accounts_rounded),
                      label: const Text('Найти в пользователях'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastNameController,
                  decoration: const InputDecoration(labelText: 'Фамилия'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _firstNameController,
                  decoration: const InputDecoration(labelText: 'Имя'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                RuPhoneField(
                  initialCanonical: _canonicalPhone,
                  onCanonicalChanged: (c) =>
                      setState(() => _canonicalPhone = c),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Email для входа',
                    helperText: 'Управляется через раздел «Пользователи»',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: _emailValidator,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role.isEmpty ? null : _role,
                  decoration: const InputDecoration(labelText: 'CRM роль'),
                  items: _dropdownItems(_roleLabels, _role),
                  onChanged: (value) => setState(() => _role = value ?? _role),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                const Text('Филиалы *'),
                const SizedBox(height: 6),
                if (_loadingBranches)
                  const Center(child: CircularProgressIndicator())
                else if (_branchesError != null)
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Не удалось загрузить филиалы.'),
                      ),
                      TextButton(
                        onPressed: _loadBranches,
                        child: const Text('Повторить'),
                      ),
                    ],
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final branch in _allBranches)
                        FilterChip(
                          label: Text(branch['name']?.toString() ?? 'Филиал'),
                          selected: _branchIds.contains(
                            branch['id']?.toString(),
                          ),
                          onSelected: (selected) {
                            final id = branch['id']?.toString();
                            if (id == null) return;
                            setState(() {
                              if (selected) {
                                _branchIds.add(id);
                              } else {
                                _branchIds.remove(id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _positionController,
                  decoration: const InputDecoration(labelText: 'Должность'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status.isEmpty ? null : _status,
                  decoration: const InputDecoration(labelText: 'Статус'),
                  items: _dropdownItems(_statusLabels, _status),
                  onChanged: (value) =>
                      setState(() => _status = value ?? _status),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _birthdayController,
                  decoration: const InputDecoration(
                    labelText: 'Дата рождения',
                    hintText: '1990-06-01',
                  ),
                ),
              ],
            ),
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
          onPressed: _saving ? null : _save,
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

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Обязательное поле' : null;
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    if (!email.contains('@')) return 'Некорректная почта';
    return null;
  }

  List<DropdownMenuItem<String>> _dropdownItems(
    Map<String, String> labels,
    String current,
  ) {
    final values = <String>{...labels.keys};
    if (current.trim().isNotEmpty) values.add(current.trim());
    return values
        .map(
          (value) => DropdownMenuItem<String>(
            value: value,
            child: Text(labels[value] ?? value),
          ),
        )
        .toList();
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool wide;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.wide = false,
  });

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

String _branchesText(dynamic value) {
  if (value is! List) return '';
  return value
      .map((branch) {
        if (branch is Map) {
          return (branch['name'] ?? branch['branch_name'] ?? '').toString();
        }
        return branch.toString();
      })
      .where((name) => name.trim().isNotEmpty)
      .join(', ');
}

String _staffRoleLabel(String role) {
  return switch (role) {
    'admin' => 'Администратор',
    'manager' => 'Управляющий',
    'director' => 'Директор',
    'teacher' => 'Преподаватель',
    'system_admin' => 'Администратор системы',
    _ => role.isEmpty ? 'Сотрудник' : role,
  };
}
