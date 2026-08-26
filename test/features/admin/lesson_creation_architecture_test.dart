import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lesson creation shell is bounded typed composition', () {
    final shell = File(
      'lib/features/admin/presentation/widgets/create_lesson_dialog.dart',
    ).readAsStringSync();
    final removedView = File(
      'lib/features/admin/presentation/widgets/create_lesson_dialog_view.dart',
    );

    expect(shell, isNot(contains("part 'create_lesson_dialog_view.dart'")));
    expect(shell, isNot(contains('part of ')));
    expect(shell, isNot(contains('_CreateLessonDialogState')));
    expect(shell, isNot(contains('with LessonEditorDraftActions')));
    expect(shell, isNot(contains('magicApiClientProvider')));
    expect(shell, isNot(contains('MagicApiClient')));
    for (final oldHelper in [
      '_loadData',
      '_saveValidationMessage',
      '_saveCreate',
      '_saveEdit',
      '_lessonPayload',
      '_loadRooms',
      '_loadDecisionCatalog',
      '_loadSubscriptions',
      '_previewConstraintsBeforeSave',
      '_analyzeCurrentSchedule',
    ]) {
      expect(shell, isNot(contains(oldHelper)), reason: oldHelper);
    }
    expect(shell, contains('class _LessonEditorDialogState'));
    expect(shell, contains('implements LessonEditorActions'));
    expect(shell, contains('showDatePicker('));
    expect(shell, contains('showTimePicker('));
    expect(shell, contains('LessonEditorDataController'));
    expect(shell, contains('LessonEditorScheduleController'));
    expect(shell, contains('LessonEditorSaveFlow'));
    expect(shell.split('\n').length, lessThan(320));
    expect(removedView.existsSync(), isFalse);
  });
}
