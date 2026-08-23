import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every production IconButton has a tooltip', () {
    final missing = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      var start = source.indexOf('IconButton(');
      while (start >= 0) {
        final next = source.indexOf('IconButton(', start + 1);
        final end = next < 0 ? source.length : next;
        final block = source.substring(start, end);
        if (!RegExp(r'\btooltip\s*:').hasMatch(block)) {
          final line = '\n'.allMatches(source.substring(0, start)).length + 1;
          missing.add('${file.path}:$line');
        }
        start = next;
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Icon-only controls need labels: $missing',
    );
  });

  test('every icon-only production FAB has a tooltip', () {
    final missing = <String>[];
    final pattern = RegExp(r'FloatingActionButton(?:\.small)?\(');
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      final matches = pattern.allMatches(source).toList();
      for (var index = 0; index < matches.length; index++) {
        final start = matches[index].start;
        final end = index + 1 < matches.length
            ? matches[index + 1].start
            : source.length;
        if (!RegExp(r'\btooltip\s*:').hasMatch(source.substring(start, end))) {
          final line = '\n'.allMatches(source.substring(0, start)).length + 1;
          missing.add('${file.path}:$line');
        }
      }
    }
    expect(missing, isEmpty, reason: 'Icon-only FABs need labels: $missing');
  });

  testWidgets('tooltip supplies semantics and Enter activates focus', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IconButton(
            autofocus: true,
            tooltip: 'Обновить данные',
            onPressed: () => activations++,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(Tooltip)).tooltip,
      contains('Обновить данные'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 1);
  });
}
