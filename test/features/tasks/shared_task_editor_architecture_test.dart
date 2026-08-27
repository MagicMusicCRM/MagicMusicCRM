import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  test('shared task view depends only on its clean view contract', () {
    final view = _source(
      'lib/features/manager/presentation/tasks/shared_task_editor_view.dart',
    );

    expect(view, contains('shared_task_editor_view_contract.dart'));
    expect(view, isNot(contains('shared_task_editor_controller.dart')));
    expect(view, isNot(contains('shared_tasks_data_source.dart')));
    expect(view, isNot(contains('flutter_riverpod')));
    expect(view, isNot(contains('MagicCrmService')));
  });

  test('view contract is pure and cannot create an import cycle', () {
    final contractFile = File(
      'lib/features/manager/presentation/tasks/'
      'shared_task_editor_view_contract.dart',
    );
    expect(contractFile.existsSync(), isTrue);
    if (!contractFile.existsSync()) return;
    final contract = contractFile.readAsStringSync();

    expect(contract, contains('SharedTaskEditorViewContract'));
    expect(contract, contains('SharedTaskEditorViewSnapshot'));
    expect(contract, isNot(contains('shared_task_editor_controller.dart')));
    expect(contract, isNot(contains('shared_task_editor_view.dart')));
    expect(contract, isNot(contains('shared_tasks_data_source.dart')));
    expect(contract, isNot(contains('flutter_riverpod')));
    expect(contract, isNot(contains('MagicCrmService')));
  });
}
