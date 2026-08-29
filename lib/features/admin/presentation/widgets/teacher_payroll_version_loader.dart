import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class TeacherPayrollVersionLoader {
  TeacherPayrollVersionLoader({
    required MagicCrmService service,
    required this.teacherId,
  }) : _service = service;

  final MagicCrmService _service;
  final String teacherId;

  int? _expectedVersion;
  Object? _error;

  int? get expectedVersion => _expectedVersion;
  Object? get error => _error;

  Future<void> load() async {
    _error = null;
    _expectedVersion = null;
    try {
      final payroll = await _service.getTeacherPayroll(teacherId);
      _expectedVersion = _version(payroll['version']);
    } catch (error) {
      _error = error;
    }
  }

  static int? _version(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
