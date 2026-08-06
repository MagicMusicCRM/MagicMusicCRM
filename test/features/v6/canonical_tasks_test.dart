import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production task route has one canonical provider', () {
    final lib = Directory('lib');
    final productionSources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('tasks_widget.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(productionSources, isNot(contains('TasksWidget(')));
    expect(productionSources, isNot(contains('.createTask(')));
    expect(productionSources, isNot(contains('.listTasks(')));

    final route = File(
      'lib/features/messenger/presentation/screens/'
      'messenger_screen_builders_a.dart',
    ).readAsStringSync();
    expect(route, contains('SharedTasksV4Panel('));

    final backendRuntime = [
      Directory('server/src/crm'),
      Directory('server/src/notifications'),
      Directory('server/src/migration'),
    ]
        .expand((directory) => directory.listSync(recursive: true))
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.ts') && !file.path.endsWith('.spec.ts'),
        )
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(backendRuntime, isNot(contains('app.tasks')));
    expect(backendRuntime, isNot(contains('app.task_history')));
    expect(backendRuntime, isNot(contains('/crm/tasks')));
  });
}
