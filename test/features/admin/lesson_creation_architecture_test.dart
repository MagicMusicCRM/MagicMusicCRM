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
    final models = File(
      'lib/features/admin/presentation/widgets/lesson_editor/'
      'lesson_editor_models.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/features/admin/presentation/widgets/lesson_editor/'
      'lesson_editor_decision_policy.dart',
    ).readAsStringSync();

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
    for (final duplicateWrapper in [
      'LessonBranchEdit',
      'LessonRoomEdit',
      'LessonTeacherEdit',
      'LessonCompletionEdit',
      'LessonSettlementEdit',
      'LessonCompensationRuleEdit',
      'LessonCompensationValueEdit',
      'LessonSettlementReasonEdit',
      'LessonFundingEdit',
      'LessonSubscriptionEdit',
    ]) {
      expect(models, isNot(contains('class $duplicateWrapper')));
    }
    final reducer = policy.substring(
      policy.indexOf('  applyEdit('),
      policy.indexOf('  LessonEditorDraft branchSelection('),
    );
    expect(reducer, isNot(matches(RegExp(r'\b_\s*=>|\bdefault\s*:'))));
  });
}
