import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_dialogs.dart';

void main() {
  testWidgets('delete dialog requires and returns an audit reason', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showTeacherPayrollDeleteDialog(
                context,
                rate: true,
              );
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить запись ставки?'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Причина удаления *'),
      'Дубликат ставки',
    );
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(result, 'Дубликат ставки');
  });
}
