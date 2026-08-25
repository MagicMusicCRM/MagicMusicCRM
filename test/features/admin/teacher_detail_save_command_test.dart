import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_save_command.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';

void main() {
  test('builds a versioned command from the validated employment draft', () {
    const employment = TeacherEmploymentValue(
      branchIds: ['branch-a'],
      disciplineIds: ['discipline-a'],
      levels: ['Средний'],
      categories: ['Взрослые'],
      birthday: null,
      workStartDate: null,
      isPartTime: false,
      isBlacklisted: false,
      salary: 20000,
      salaryChanged: true,
      rate: 900,
      rateChanged: true,
      rateEffectiveFrom: null,
    );

    final command = TeacherDetailSaveCommand.fromEditor(
      name: ' Анна Мария Петрова ',
      phone: '+79990000000',
      employment: employment,
      payrollExpectedVersion: 4,
      payrollReasonText: 'Новые условия',
    );

    expect(command.firstName, 'Анна');
    expect(command.lastName, 'Мария Петрова');
    expect(command.salary, 20000);
    expect(command.rate, 900);
    expect(command.rateEffectiveFrom, isNull);
    expect(command.payrollExpectedVersion, 4);
    expect(command.payrollReasonText, 'Новые условия');
    expect(command.customDataPatch['levels'], ['Средний']);
  });
}
