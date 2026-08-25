import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';

void main() {
  test('public dialog keeps the supplied teacher card', () {
    const dialog = TeacherDetailDialog(teacher: {'id': 'teacher-a'});
    expect(dialog.teacher['id'], 'teacher-a');
  });

  test('teacher detail is split into independent bounded owners', () {
    const root = 'lib/features/admin/presentation/widgets';
    const requiredFiles = [
      'teacher_detail_access_flow.dart',
      'teacher_detail_content.dart',
      'teacher_detail_model.dart',
      'teacher_detail_save_command.dart',
      'teacher_payroll_controller.dart',
      'teacher_payroll_dialog_controller_owner.dart',
      'teacher_payroll_dialogs.dart',
      'teacher_payroll_entry_dialogs.dart',
      'teacher_payroll_history.dart',
      'teacher_payroll_section.dart',
    ];

    for (final name in requiredFiles) {
      expect(File('$root/$name').existsSync(), isTrue, reason: name);
    }

    final shell = File('$root/teacher_detail_dialog.dart').readAsStringSync();
    final saveBody = shell.substring(
      shell.indexOf('Future<void> _save()'),
      shell.indexOf('Future<void> _provisionAccess()'),
    );
    expect(shell, isNot(contains("part '")));
    expect(shell, isNot(contains('part of')));
    expect(shell.split('\n').length, lessThanOrEqualTo(430));
    expect(
      saveBody,
      isNot(contains('showTeacherEmploymentChangeReasonDialog')),
    );
    expect(saveBody, isNot(contains('payrollExpectedVersion')));
    expect(shell, isNot(contains('createTeacherPayout(')));
    expect(shell, isNot(contains('updateTeacherRateEntry(')));
    expect(shell, isNot(contains('updateTeacherPayoutEntry(')));
    expect(shell, isNot(contains('PopupMenuButton<String>')));
    expect(File('$root/teacher_detail_widgets.dart').existsSync(), isFalse);
  });
}
