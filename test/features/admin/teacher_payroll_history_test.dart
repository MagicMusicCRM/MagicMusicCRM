import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_history.dart';

void main() {
  testWidgets('read-only history never builds mutation menus', (tester) async {
    void ignoreRow(Map<String, dynamic> _) {}
    void ignoreDelete(Map<String, dynamic> _, {required bool rate}) {}

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeacherPayrollHistory(
            payroll: const {
              'rateHistory': [
                {'id': 'rate-a', 'rate': 900, 'effectiveFrom': '2026-08-01'},
              ],
              'payouts': <dynamic>[],
            },
            canManage: false,
            mutating: false,
            onEditRate: ignoreRow,
            onEditPayout: ignoreRow,
            onDelete: ignoreDelete,
          ),
        ),
      ),
    );

    await tester.tap(find.text('История ставок (1)'));
    await tester.pumpAndSettle();

    expect(
      find.byType(PopupMenuButton<String>, skipOffstage: false),
      findsNothing,
    );
  });
}
