import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _widgetDirectory = 'lib/features/manager/presentation/widgets';

String _source(String filename) {
  return File('$_widgetDirectory/$filename').readAsStringSync();
}

int _nloc(String source) {
  var inBlockComment = false;
  var count = 0;
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('/*')) inBlockComment = true;
    if (trimmed.isNotEmpty && !inBlockComment && !trimmed.startsWith('//')) {
      count += 1;
    }
    if (trimmed.endsWith('*/')) inBlockComment = false;
  }
  return count;
}

void main() {
  test('teacher statistics shell stays below its architecture budget', () {
    final source = _source('teacher_stats_widget.dart');
    final imports = RegExp(r'^import ', multiLine: true).allMatches(source);

    expect(_nloc(source), lessThanOrEqualTo(240));
    expect(imports.length, lessThanOrEqualTo(12));
    expect(source, contains('class TeacherStatsWidget'));
    expect(source, contains('ref.read(magicCrmServiceProvider)'));
    expect(source, contains('ref.read(magicSettingsServiceProvider)'));
    expect(source, contains('ref.read(reportFileOpenerProvider)'));

    for (final forbidden in const [
      '_buildFilters',
      '_buildUnitRow',
      '_applyBulkRate',
      '_editUnitLessonRate',
      'getTeacherStatsReport',
      'exportTeacherStatsReport',
      'setLessonsTeacherRate',
      'updateGroup',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('every extracted teacher statistics owner stays bounded', () {
    for (final filename in const [
      'teacher_stats_models.dart',
      'teacher_stats_controller.dart',
      'teacher_stats_view.dart',
      'teacher_stats_components.dart',
      'teacher_stats_rate_dialogs.dart',
    ]) {
      expect(
        _nloc(_source(filename)),
        lessThanOrEqualTo(500),
        reason: filename,
      );
    }
  });
}
