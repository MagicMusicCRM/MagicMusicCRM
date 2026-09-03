import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/access_management.dart';

const personAccessRoleLabels = <String, String>{
  'teacher': 'Преподаватель',
  'admin': 'Администратор',
  'manager': 'Управляющий',
  'director': 'Директор',
};

List<String> personAccessRoleOptions({
  required String actorRole,
  required bool teacher,
}) {
  const level = <String, int>{
    'teacher': 1,
    'admin': 2,
    'manager': 3,
    'director': 4,
    'system_admin': 5,
  };
  final actorLevel = level[actorRole] ?? 0;
  final candidates = teacher
      ? const ['teacher', 'admin', 'manager', 'director']
      : const ['admin', 'manager', 'director'];
  return [
    for (final role in candidates)
      if ((level[role] ?? 99) < actorLevel) role,
  ];
}

Future<String?> showPersonAccessRoleDialog(
  BuildContext context, {
  required String actorRole,
  required String userId,
  required String personLabel,
  required bool teacher,
}) {
  return showMagicDialog<String>(
    context: context,
    builder: (_) => PersonAccessRoleDialog(
      actorRole: actorRole,
      userId: userId,
      personLabel: personLabel,
      teacher: teacher,
    ),
  );
}

class PersonAccessRoleDialog extends ConsumerStatefulWidget {
  const PersonAccessRoleDialog({
    super.key,
    required this.actorRole,
    required this.userId,
    required this.personLabel,
    required this.teacher,
    this.dataSource,
  });

  final String actorRole;
  final String userId;
  final String personLabel;
  final bool teacher;
  final AccessManagementDataSource? dataSource;

  @override
  ConsumerState<PersonAccessRoleDialog> createState() =>
      _PersonAccessRoleDialogState();
}

class _PersonAccessRoleDialogState
    extends ConsumerState<PersonAccessRoleDialog> {
  ManagedUserAccess? _access;
  String? _selectedRole;
  Object? _error;
  bool _confirmReset = false;
  bool _saving = false;

  AccessManagementDataSource get _source =>
      widget.dataSource ?? ref.read(accessManagementServiceProvider);

  List<String> get _roles => personAccessRoleOptions(
    actorRole: widget.actorRole,
    teacher: widget.teacher,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final access = await _source.getUserAccess(widget.userId);
      if (!mounted) return;
      setState(() {
        _access = access;
        _selectedRole = access.role;
        _error = null;
        _confirmReset = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final access = _access;
    final role = _selectedRole;
    if (access == null || role == null || role == access.role || _saving) {
      return;
    }
    if (!_confirmReset) {
      setState(() => _error = 'Подтвердите сброс персональных прав.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _source.assignRole(
        userId: access.userId,
        role: role,
        expectedVersion: access.accessVersion,
        resetOverridesConfirmed: true,
        emergencySurface: widget.actorRole == 'system_admin',
        reasonCode: 'crm.person_card.role_change',
        identity: MagicMutationIdentity.create('person-card-role'),
      );
      if (mounted) Navigator.pop(context, role);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final roles = <String>{..._roles, if (access != null) access.role}.toList()
      ..sort(
        (a, b) => personAccessRoleLabels.keys
            .toList()
            .indexOf(a)
            .compareTo(personAccessRoleLabels.keys.toList().indexOf(b)),
      );
    return AlertDialog(
      title: const Text('Роль доступа'),
      content: SizedBox(
        width: 420,
        child: access == null && _error == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.personLabel),
                  const SizedBox(height: 12),
                  if (access != null)
                    DropdownButtonFormField<String>(
                      menuMaxHeight: 256,
                      key: const Key('person-access-role-selector'),
                      initialValue: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Роль доступа',
                      ),
                      items: [
                        for (final role in roles)
                          DropdownMenuItem(
                            value: role,
                            enabled: _roles.contains(role),
                            child: Text(personAccessRoleLabels[role] ?? role),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _selectedRole = value;
                              _confirmReset = false;
                              _error = null;
                            }),
                    ),
                  if (access != null && _selectedRole != access.role) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      key: const Key('person-access-reset-confirmation'),
                      contentPadding: EdgeInsets.zero,
                      value: _confirmReset,
                      onChanged: _saving
                          ? null
                          : (value) =>
                                setState(() => _confirmReset = value == true),
                      title: const Text(
                        'Сбросить персональные настройки доступа',
                      ),
                      subtitle: const Text(
                        'После смены роли будут действовать права выбранной роли.',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      userErrorMessage(
                        _error,
                        fallback: 'Не удалось изменить роль.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        if (access == null && _error != null)
          FilledButton.tonal(onPressed: _load, child: const Text('Повторить'))
        else
          FilledButton(
            key: const Key('person-access-role-save'),
            onPressed: _saving || access == null || _selectedRole == access.role
                ? null
                : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить роль'),
          ),
      ],
    );
  }
}
