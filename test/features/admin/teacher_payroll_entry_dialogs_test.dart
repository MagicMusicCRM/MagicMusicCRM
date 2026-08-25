import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_entry_dialogs.dart';

void main() {
  testWidgets('rate correction requires a reason and returns a typed edit', (
    tester,
  ) async {
    TeacherRateEdit? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showTeacherRateEditDialog(context, {
                'id': 'rate-a',
                'rate': 900,
                'effectiveFrom': '2026-08-01',
              });
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Исправить ставку'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Причина исправления *'),
      'Исправление договора',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(result?.rate, 900);
    expect(result?.effectiveFrom, DateTime(2026, 8, 1));
    expect(result?.reasonText, 'Исправление договора');
  });
}
