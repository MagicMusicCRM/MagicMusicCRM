import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  test('finance shell composes normal controller and view libraries', () {
    final shell = _source(
      'lib/features/manager/presentation/widgets/finance_widget.dart',
    );

    expect(shell, contains("import 'finance_controller.dart';"));
    expect(shell, contains("import 'finance_widget_widgets.dart';"));
    expect(shell, contains('reportFileOpenerProvider'));
    expect(shell, isNot(contains("part 'finance_widget_widgets.dart'")));
    expect(shell, isNot(contains("import 'dart:io'")));
    expect(shell, isNot(contains('path_provider')));
    expect(shell, isNot(contains('OpenFilex')));
  });

  test('finance view has no back import, providers or service I/O', () {
    final view = _source(
      'lib/features/manager/presentation/widgets/finance_widget_widgets.dart',
    );

    expect(view, isNot(contains('part of')));
    expect(view, isNot(contains('finance_widget.dart')));
    expect(view, isNot(contains('flutter_riverpod')));
    expect(view, isNot(contains('MagicCrmService')));
    expect(view, isNot(contains('magicCrmServiceProvider')));
  });
}
