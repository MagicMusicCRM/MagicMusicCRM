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

  test(
    'blocks a payroll mutation until a current version is available',
    () async {
      const employment = TeacherEmploymentValue(
        branchIds: ['branch-a'],
        disciplineIds: ['discipline-a'],
        levels: [],
        categories: [],
        birthday: null,
        workStartDate: null,
        isPartTime: false,
        isBlacklisted: false,
        salary: 20000,
        salaryChanged: true,
        rate: null,
        rateChanged: false,
        rateEffectiveFrom: null,
      );
      var reasonRequested = false;

      final preparation = await TeacherDetailSaveCommand.prepare(
        name: 'Анна Петрова',
        phone: '+79990000000',
        employment: employment,
        expectedVersion: null,
        payrollAvailable: true,
        requestPayrollReason: (_) async {
          reasonRequested = true;
          return 'Новые условия';
        },
      );

      expect(preparation.command, isNull);
      expect(preparation.message, contains('версию расчётов'));
      expect(reasonRequested, isFalse);
    },
  );

  test('preserves cancellation before a versioned payroll mutation', () async {
    const employment = TeacherEmploymentValue(
      branchIds: ['branch-a'],
      disciplineIds: ['discipline-a'],
      levels: [],
      categories: [],
      birthday: null,
      workStartDate: null,
      isPartTime: false,
      isBlacklisted: false,
      salary: null,
      salaryChanged: false,
      rate: 900,
      rateChanged: true,
      rateEffectiveFrom: null,
    );

    final preparation = await TeacherDetailSaveCommand.prepare(
      name: 'Анна Петрова',
      phone: '+79990000000',
      employment: employment,
      expectedVersion: 4,
      payrollAvailable: true,
      requestPayrollReason: (_) async => null,
    );

    expect(preparation.command, isNull);
    expect(preparation.message, isNull);
  });
}
