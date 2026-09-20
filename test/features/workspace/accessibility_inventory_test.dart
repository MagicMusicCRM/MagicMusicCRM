import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/architecture/icon_tooltip_guard.dart';

void main() {
  test('every production icon-only button declares its own tooltip', () {
    final missing = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      missing.addAll(
        findMissingIconTooltips(file.readAsStringSync(), path: file.path),
      );
    }
    expect(
      missing,
      isEmpty,
      reason: 'Icon-only controls need labels: $missing',
    );
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
