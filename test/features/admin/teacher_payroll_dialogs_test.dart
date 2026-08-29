import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_dialogs.dart';

void main() {
  testWidgets('employment change dialog requires and returns an audit reason', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showTeacherEmploymentChangeReasonDialog(
                context,
                employment: const TeacherEmploymentValue(
                  branchIds: [],
                  disciplineIds: [],
                  levels: [],
                  categories: [],
                  birthday: null,
                  workStartDate: null,
                  isPartTime: false,
                  isBlacklisted: false,
                  salary: 1000,
                  salaryChanged: false,
                  rate: 900,
                  rateChanged: true,
                  rateEffectiveFrom: null,
                ),
                initial: const TeacherEmploymentInitial(
                  salary: 1000,
                  rate: 800,
                ),
              );
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить и сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Подтвердите финансовые условия'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Причина изменения'),
      'Новые условия договора',
    );
    await tester.tap(find.text('Подтвердить и сохранить'));
    await tester.pumpAndSettle();

    expect(result, 'Новые условия договора');
  });
}
