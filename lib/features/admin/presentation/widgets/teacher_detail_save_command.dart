import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';

typedef TeacherPayrollReasonRequester =
    Future<String?> Function(TeacherEmploymentValue employment);

class TeacherDetailSavePreparation {
  const TeacherDetailSavePreparation._({this.command, this.message});

  const TeacherDetailSavePreparation.ready(TeacherDetailSaveCommand command)
    : this._(command: command);

  const TeacherDetailSavePreparation.cancelled() : this._();

  const TeacherDetailSavePreparation.invalid(String message)
    : this._(message: message);

  final TeacherDetailSaveCommand? command;
  final String? message;
}

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

  static Future<TeacherDetailSavePreparation> prepare({
    required String name,
    required String phone,
    required TeacherEmploymentValue employment,
    required int? expectedVersion,
    required bool payrollAvailable,
    required TeacherPayrollReasonRequester requestPayrollReason,
  }) async {
    if (name.trim().isEmpty) {
      return const TeacherDetailSavePreparation.invalid(
        'Укажите имя преподавателя.',
      );
    }
    final payrollChanged = employment.salaryChanged || employment.rateChanged;
    if (!payrollChanged) {
      return TeacherDetailSavePreparation.ready(
        TeacherDetailSaveCommand.fromEditor(
          name: name,
          phone: phone,
          employment: employment,
          payrollExpectedVersion: null,
          payrollReasonText: null,
        ),
      );
    }
    if (!payrollAvailable || expectedVersion == null) {
      return const TeacherDetailSavePreparation.invalid(
        'Не удалось проверить версию расчётов. '
        'Обновите блок оплат и повторите.',
      );
    }
    final reason = await requestPayrollReason(employment);
    if (reason == null) {
      return const TeacherDetailSavePreparation.cancelled();
    }
    return TeacherDetailSavePreparation.ready(
      TeacherDetailSaveCommand.fromEditor(
        name: name,
        phone: phone,
        employment: employment,
        payrollExpectedVersion: expectedVersion,
        payrollReasonText: reason,
      ),
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
