import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';

class TeacherDetailSaveCommand {
  const TeacherDetailSaveCommand({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.customDataPatch,
    required this.disciplineIds,
    required this.branchIds,
    this.salary,
    this.rate,
    this.rateEffectiveFrom,
    this.payrollExpectedVersion,
    this.payrollReasonText,
  });

  factory TeacherDetailSaveCommand.fromEditor({
    required String name,
    required String phone,
    required TeacherEmploymentValue employment,
    required int? payrollExpectedVersion,
    required String? payrollReasonText,
  }) {
    final names = name.trim().split(RegExp(r'\s+'));
    return TeacherDetailSaveCommand(
      firstName: names.first,
      lastName: names.length > 1 ? names.sublist(1).join(' ') : '',
      phone: phone,
      customDataPatch: employment.customDataPatch,
      salary: employment.salaryChanged ? employment.salary : null,
      disciplineIds: employment.disciplineIds,
      branchIds: employment.branchIds,
      rate: employment.rateChanged ? employment.rate : null,
      rateEffectiveFrom:
          employment.rateChanged && employment.rateEffectiveFrom != null
          ? DateFormat('yyyy-MM-dd').format(employment.rateEffectiveFrom!)
          : null,
      payrollExpectedVersion: payrollExpectedVersion,
      payrollReasonText: payrollReasonText,
    );
  }

  final String firstName;
  final String lastName;
  final String phone;
  final Map<String, dynamic> customDataPatch;
  final num? salary;
  final List<String> disciplineIds;
  final List<String> branchIds;
  final num? rate;
  final String? rateEffectiveFrom;
  final int? payrollExpectedVersion;
  final String? payrollReasonText;

  Future<Map<String, dynamic>> execute(
    MagicCrmService service,
    String teacherId,
  ) {
    return service.updateTeacher(
      teacherId,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      customDataPatch: customDataPatch,
      salary: salary,
      disciplineIds: disciplineIds,
      branchIds: branchIds,
      rate: rate,
      rateEffectiveFrom: rateEffectiveFrom,
      payrollExpectedVersion: payrollExpectedVersion,
      payrollReasonText: payrollReasonText,
    );
  }
}
