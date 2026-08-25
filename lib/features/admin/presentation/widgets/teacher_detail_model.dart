import 'package:intl/intl.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';

class TeacherDetailInitialData {
  const TeacherDetailInitialData({
    required this.teacher,
    required this.name,
    required this.phone,
    required this.email,
    required this.employment,
  });

  factory TeacherDetailInitialData.fromTeacher(Map<String, dynamic> source) {
    final teacher = Map<String, dynamic>.from(source);
    final profile = teacher['profiles'] is Map
        ? Map<String, dynamic>.from(teacher['profiles'] as Map)
        : const <String, dynamic>{};
    final directName = [teacher['first_name'], teacher['last_name']]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .join(' ');
    final profileName = [profile['first_name'], profile['last_name']]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .join(' ');
    final custom = teacher['custom_data'] is Map
        ? Map<String, dynamic>.from(teacher['custom_data'] as Map)
        : const <String, dynamic>{};

    return TeacherDetailInitialData(
      teacher: teacher,
      name: directName.isEmpty ? profileName : directName,
      phone: teacher['phone']?.toString() ?? profile['phone']?.toString() ?? '',
      email: teacher['email']?.toString() ?? '',
      employment: TeacherEmploymentInitial(
        branches: teacherDetailMapList(teacher['assigned_branches']),
        disciplines: teacherDetailMapList(teacher['disciplines']),
        levels: teacherDetailMultiValue(custom, 'levels', 'level'),
        categories: teacherDetailMultiValue(custom, 'categories', 'category'),
        birthday: teacherDetailParseDate(custom['birthday']),
        workStartDate: teacherDetailParseDate(custom['workStartDate']),
        isPartTime: custom['isPartTime'] == true,
        isBlacklisted: custom['isBlacklisted'] == true,
        salary: teacherDetailNullableNum(teacher['salary']),
        rate: teacherDetailNullableNum(teacher['current_rate']),
      ),
    );
  }

  final Map<String, dynamic> teacher;
  final String name;
  final String phone;
  final String email;
  final TeacherEmploymentInitial employment;
}

List<Map<String, dynamic>> teacherDetailMapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

Set<String> teacherDetailMultiValue(
  Map<String, dynamic> custom,
  String pluralKey,
  String legacyKey,
) {
  final raw = custom[pluralKey] ?? custom[legacyKey];
  if (raw is List) {
    return {
      for (final value in raw)
        if (value?.toString().trim().isNotEmpty == true)
          value.toString().trim(),
    };
  }
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return {};
  return {
    for (final part in text.split(RegExp(r'[,;]')))
      if (part.trim().isNotEmpty) part.trim(),
  };
}

DateTime? teacherDetailParseDate(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(text);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
  );
}

num? teacherDetailNullableNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '');
}

num teacherDetailNum(dynamic value) => teacherDetailNullableNum(value) ?? 0;

int teacherDetailInt(dynamic value) => teacherDetailNum(value).toInt();

String teacherDetailBranchesText(dynamic value) {
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

String teacherDetailRoleLabel(String role) => switch (role) {
  'admin' => 'Администратор',
  'manager' => 'Управляющий',
  'director' => 'Директор',
  'teacher' => 'Преподаватель',
  'system_admin' => 'Администратор системы',
  _ => role.isEmpty ? 'Нет' : role,
};

String teacherDetailShortDate(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  return parsed == null ? value : DateFormat('dd.MM.yyyy HH:mm').format(parsed);
}

String teacherDetailShortDay(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  return parsed == null ? value : DateFormat('dd.MM.yyyy').format(parsed);
}

String teacherDetailCredentialHelper(Map<String, dynamic> data) {
  final passwordChanged = data['password_changed_at']?.toString();
  final emailChanged = data['email_changed_at']?.toString();
  final parts = <String>[
    if (data['password_configured'] == true) 'Пароль настроен',
    if (emailChanged != null && emailChanged.isNotEmpty)
      'почта обновлена ${teacherDetailShortDate(emailChanged)}',
    if (passwordChanged != null && passwordChanged.isNotEmpty)
      'пароль обновлён ${teacherDetailShortDate(passwordChanged)}',
  ];
  return parts.isEmpty
      ? 'Доступ не создан. Карточку можно сохранить без него'
      : parts.join(' · ');
}
