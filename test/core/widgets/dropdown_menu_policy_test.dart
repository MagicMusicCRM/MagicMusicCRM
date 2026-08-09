import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain dropdowns are capped to a compact scrollable menu', () {
    final uncapped = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      final pattern = RegExp(r'DropdownButtonFormField<[^>]+>\(\s*');
      for (final match in pattern.allMatches(source)) {
        if (!source.startsWith('menuMaxHeight: 256,', match.end)) {
          uncapped.add(file.path);
        }
      }
    }
    expect(uncapped, isEmpty);
  });
}
