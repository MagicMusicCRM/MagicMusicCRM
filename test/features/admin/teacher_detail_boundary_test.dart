import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('teacher detail is split into independent bounded owners', () {
    const root = 'lib/features/admin/presentation/widgets';
    const requiredFiles = [
      'teacher_detail_model.dart',
      'teacher_payroll_controller.dart',
      'teacher_payroll_dialogs.dart',
      'teacher_payroll_history.dart',
      'teacher_payroll_section.dart',
      'teacher_detail_content.dart',
    ];

    for (final name in requiredFiles) {
      expect(File('$root/$name').existsSync(), isTrue, reason: name);
    }

    final shell = File('$root/teacher_detail_dialog.dart').readAsStringSync();
    expect(shell, isNot(contains("part '")));
    expect(shell, isNot(contains('part of')));
    expect(shell.split('\n').length, lessThanOrEqualTo(430));
    expect(shell, isNot(contains('createTeacherPayout(')));
    expect(shell, isNot(contains('updateTeacherRateEntry(')));
    expect(shell, isNot(contains('updateTeacherPayoutEntry(')));
    expect(shell, isNot(contains('PopupMenuButton<String>')));
    expect(File('$root/teacher_detail_widgets.dart').existsSync(), isFalse);
  });
}
