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
    expect(productionSources, contains('SharedTasksPanel('));
    expect(
      productionSources,
      isNot(contains(<String>['SharedTasks', 'V4Panel'].join())),
    );
    expect(
      productionSources,
      isNot(contains(<String>['shared_tasks_', 'v4_panel'].join())),
    );

    final workspaceRoute = File(
      'lib/features/crm/presentation/staff_workspace_secondary_destination.dart',
    ).readAsStringSync();
    expect(workspaceRoute, contains('SharedTasksPanel('));

    final messenger = File(
      'lib/features/messenger/presentation/screens/'
      'messenger_screen_builders_a.dart',
    ).readAsStringSync();
    expect(messenger, isNot(contains('SharedTasksPanel(')));

    final backendRuntime =
        [
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
