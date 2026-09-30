import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/navigation/responsive_navigation_shell.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('close a task after its reminder was delivered', (tester) async {
    final h = LiveAuditHarness(tester, 'admin', 'notification-task-close');
    await h.initialize(size: const Size(1440, 1100));
    final id = h.fixture['taskId'] as String;
    final crm = h.scope.read(magicCrmServiceProvider);
    final withComment = h.fixture['closeWithComment'] == true;
    const comment = 'Связались после покупки; следующее занятие согласовано';

    await h.check('UI-CLOSE', 'Закрыть задачу после напоминания', () async {
      await h.mount(const StaffWorkspaceScreen());
      await h.tap(find.text('Задачи'));
      await h.waitFor(
        () => find.byType(SharedTasksPanel).evaluate().isNotEmpty,
        'Task panel opened',
      );
      await h.tap(find.byKey(const Key('shared-task-today-filter')));
      await h.quiet();
      int badge() => tester
          .widget<ResponsiveNavigationShell>(
            find.byType(ResponsiveNavigationShell).first,
          )
          .destinations
          .singleWhere((item) => item.label == 'Задачи')
          .badgeCount;
      final before = badge();
      await h.tap(find.byKey(Key('close-shared-task-$id')));
      await h.tap(find.byKey(const Key('shared-task-result-select')));
      await h.tap(find.text(withComment ? 'Другое' : 'Выполнено').last);
      if (withComment) {
        await h.tap(find.byKey(const Key('shared-task-close-submit')));
        expect(
          find.text('Для результата «Другое» добавьте пояснение.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('shared-task-result-comment')),
          comment,
        );
      }
      await h.tap(find.byKey(const Key('shared-task-close-submit')));
      await h.waitFor(
        () => find.byKey(Key('close-shared-task-$id')).evaluate().isEmpty,
        'Closed task left the open list',
      );
      final closed = await crm.listSharedTasks(
        q: 'AUDIT-REMINDER-open',
        state: 'closed',
      );
      expect((closed['items'] as List).any((item) => item['id'] == id), true);
      if (withComment) {
        final row = (closed['items'] as List).singleWhere(
          (item) => item['id'] == id,
        );
        expect(row['closure']['result']['code'], 'other');
        expect(row['closure']['result']['comment'], comment);
        await h.waitFor(
          () => badge() == before - 1,
          'Today badge decremented once',
        );
      }
      h.facts.add({'step': h.currentStep, 'taskId': id, 'state': 'closed'});
    });
    await h.finish();
    if (withComment) {
      final director = LiveAuditHarness(
        tester,
        'director',
        'notification-task-journal',
      );
      await director.initialize(size: const Size(1440, 1100));
      await director.check(
        'JOURNAL',
        'Директор видит сохранённый результат и комментарий',
        () async {
          await director.mount(const StaffWorkspaceScreen());
          await director.tap(find.text('Задачи'));
          await director.quiet();
          await director.tap(find.byKey(const Key('shared-task-open-results')));
          await director.quiet();
          await tester.enterText(
            find.byKey(const Key('shared-task-results-search')),
            'AUDIT-REMINDER-open',
          );
          await director.tap(find.byTooltip('Найти'));
          await director.waitFor(
            () => find.text(comment).evaluate().isNotEmpty,
            'Persisted comment in journal',
          );
          expect(find.text('Другое'), findsWidgets);
        },
      );
      await director.finish();
    }
  });
}
