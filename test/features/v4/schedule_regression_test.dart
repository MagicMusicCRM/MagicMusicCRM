import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schedule route and UI inventory contains no attendance mutations', () {
    final sourceFiles =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final routeSource = File(
      'lib/core/router/app_router.dart',
    ).readAsStringSync();
    final routes = RegExp(
      r'''path\s*:\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    ).allMatches(routeSource).map((match) => match.group(1)!).toList();
    final attendanceRoutes = routes
        .where((route) => route.toLowerCase().contains('attendance'))
        .toList();

    final forbiddenInventory = <RegExp>[
      RegExp(r'''['"]/[^'"]*attendance[^'"]*['"]''', caseSensitive: false),
      RegExp(r'\bAttendanceService\b', caseSensitive: false),
      RegExp(r'\b(?:create|update|mark|set)Attendance\b', caseSensitive: false),
      RegExp(
        r'''(?:attendance|посещаемост)[-_ ](?:toggle|control|button|action)''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:отметить|сохранить|изменить)\s+посещаемост''',
        caseSensitive: false,
      ),
    ];
    final forbiddenHits = <String>[];
    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      for (final pattern in forbiddenInventory) {
        if (pattern.hasMatch(source)) {
          forbiddenHits.add('${file.path}: ${pattern.pattern}');
        }
      }
    }

    expect(attendanceRoutes, isEmpty);
    expect(forbiddenHits, isEmpty);
  });
}
