import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_content.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_history.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  const teacher = <String, dynamic>{
    'students_count': 2,
    'lessons_count': 8,
    'is_app_account': true,
    'app_role': 'teacher',
    'password_configured': true,
  };

  testWidgets(
    'content credential metric is visible only to privileged actors',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const TeacherDetailSummary(
            teacher: teacher,
            canManageCredentials: false,
          ),
        ),
      );
      expect(find.text('Пароль'), findsNothing);

      await tester.pumpWidget(
        _host(
          const TeacherDetailSummary(
            teacher: teacher,
            canManageCredentials: true,
          ),
        ),
      );
      expect(find.text('Пароль'), findsOneWidget);
      expect(find.text('Настроен'), findsOneWidget);
    },
  );

  testWidgets('history mutation menus are absent without management role', (
    tester,
  ) async {
    final payroll = <String, dynamic>{
      'rateHistory': [
        {'id': 'rate-a', 'rate': 900, 'effectiveFrom': '2026-08-01'},
      ],
      'payouts': [
        {
          'id': 'payout-a',
          'kind': 'payout',
          'amount': 1000,
          'paidAt': '2026-08-02T10:00:00Z',
        },
      ],
    };
    void ignoreRow(Map<String, dynamic> _) {}
    void ignoreDelete(Map<String, dynamic> _, {required bool rate}) {}

    await tester.pumpWidget(
      _host(
        TeacherPayrollHistory(
          key: const ValueKey('unprivileged-history'),
          payroll: payroll,
          canManage: false,
          mutating: false,
          onEditRate: ignoreRow,
          onEditPayout: ignoreRow,
          onDelete: ignoreDelete,
        ),
      ),
    );
    await tester.tap(find.text('История ставок (1)'));
    await tester.pumpAndSettle();
    expect(
      find.byType(PopupMenuButton<String>, skipOffstage: false),
      findsNothing,
    );

    await tester.pumpWidget(
      _host(
        TeacherPayrollHistory(
          key: const ValueKey('privileged-history'),
          payroll: payroll,
          canManage: true,
          mutating: false,
          onEditRate: ignoreRow,
          onEditPayout: ignoreRow,
          onDelete: ignoreDelete,
        ),
      ),
    );
    await tester.tap(find.text('История ставок (1)'));
    await tester.pumpAndSettle();
    expect(
      find.byType(PopupMenuButton<String>, skipOffstage: false),
      findsOneWidget,
    );
  });
}
