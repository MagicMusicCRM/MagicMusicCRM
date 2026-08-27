class StaffDetailDraft {
  StaffDetailDraft.fromStaff(Map<String, dynamic> staff)
    : firstName =
          _value(staff, 'first_name', 'firstName') ??
          _profileValue(staff, 'first_name', 'firstName') ??
          '',
      lastName =
          _value(staff, 'last_name', 'lastName') ??
          _profileValue(staff, 'last_name', 'lastName') ??
          '',
      canonicalPhone =
          _value(staff, 'phone') ?? _profileValue(staff, 'phone') ?? '',
      email = _value(staff, 'email') ?? '',
      position = _value(staff, 'position') ?? '',
      birthday = _birthday(staff),
      role = (_value(staff, 'role') ?? '').trim(),
      status = (_value(staff, 'status') ?? '').trim(),
      branchIds = _branchIds(staff),
      _initialBirthday = _birthday(staff);

  String firstName;
  String lastName;
  String canonicalPhone;
  String email;
  String position;
  String birthday;
  String role;
  String status;
  Set<String> branchIds;

  final String _initialBirthday;

  String get personLabel => '$lastName $firstName'.trim();

  String? linkSearchValue() {
    final phone = canonicalPhone.trim();
    if (phone.isNotEmpty) return phone;
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty ||
        normalizedEmail.endsWith('@local.magicmusiccrm.invalid') ||
        normalizedEmail.endsWith('@migration.invalid')) {
      return null;
    }
    return normalizedEmail;
  }

  Map<String, dynamic> customDataPatch() {
    final normalizedBirthday = birthday.trim();
    if (normalizedBirthday.isEmpty || normalizedBirthday == _initialBirthday) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{'birthday': normalizedBirthday};
  }
}

String? _value(
  Map<String, dynamic> source,
  String snakeKey, [
  String? camelKey,
]) {
  final value =
      source[snakeKey] ?? (camelKey == null ? null : source[camelKey]);
  return value?.toString();
}

String? _profileValue(
  Map<String, dynamic> staff,
  String snakeKey, [
  String? camelKey,
]) {
  final profile = staff['profiles'] ?? staff['profile'];
  if (profile is! Map) return null;
  final value =
      profile[snakeKey] ?? (camelKey == null ? null : profile[camelKey]);
  return value?.toString();
}

String _birthday(Map<String, dynamic> staff) {
  final customData = staff['custom_data'] ?? staff['customData'];
  if (customData is! Map) return '';
  return customData['birthday']?.toString() ?? '';
}

Set<String> _branchIds(Map<String, dynamic> staff) {
  final branches = staff['branches'];
  if (branches is! List) return <String>{};
  return {
    for (final branch in branches)
      if (branch is Map && branch['id'] != null) branch['id'].toString(),
  };
}

const staffStatusLabels = <String, String>{
  'working': 'Работает',
  'active': 'Активен',
};

bool canManageStaffCredentials(String currentRole) =>
    const {'director', 'system_admin'}.contains(currentRole);

String? staffRequiredValidator(String? value) =>
    value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

String? staffEmailValidator(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return null;
  return email.contains('@') ? null : 'Некорректная почта';
}

String staffCredentialHelper(Map<String, dynamic> data) {
  final passwordChanged = data['password_changed_at']?.toString();
  final emailChanged = data['email_changed_at']?.toString();
  final parts = <String>[
    if (data['password_configured'] == true) 'Пароль настроен',
    if (emailChanged != null && emailChanged.isNotEmpty)
      'почта обновлена ${_shortDate(emailChanged)}',
    if (passwordChanged != null && passwordChanged.isNotEmpty)
      'пароль обновлён ${_shortDate(passwordChanged)}',
  ];
  return parts.isEmpty
      ? 'Доступ не создан. Карточку можно сохранить без него'
      : parts.join(' · ');
}

List<String> staffStatusValues(String current) {
  final values = <String>{...staffStatusLabels.keys};
  if (current.trim().isNotEmpty) values.add(current.trim());
  return values.toList();
}

String staffBranchesText(dynamic value) {
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

String staffRoleLabel(String role) {
  return switch (role) {
    'admin' => 'Администратор',
    'manager' => 'Управляющий',
    'director' => 'Директор',
    'teacher' => 'Преподаватель',
    'system_admin' => 'Администратор системы',
    _ => role.isEmpty ? 'Сотрудник' : role,
  };
}

String _shortDate(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(parsed.day)}.${two(parsed.month)}.${parsed.year} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}
