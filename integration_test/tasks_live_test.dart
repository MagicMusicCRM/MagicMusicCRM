import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director', 'admin']) {
    testWidgets(
      '$role task commands through workspace menu',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'tasks');
        await h.initialize(size: const Size(1440, 1100));
        final crm = h.scope.read(magicCrmServiceProvider);
        Future<Map<String, dynamic>> read(
          String title, {
          String state = 'open',
        }) async {
          final response = await crm.listSharedTasks(q: title, state: state);
          return (response['items'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((item) => item['title'] == title);
        }

        Future<void> enterEditor() async {
          await h.tap(find.text('Новая задача'));
          await h.waitFor(
            () => find
                .byKey(const Key('shared-task-title'))
                .evaluate()
                .isNotEmpty,
            'Task editor opened',
          );
          await h.quiet();
        }

        Future<void> create(String title) async {
          await tester.enterText(
            find.byKey(const Key('shared-task-title')),
            title,
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Описание'),
            'Проверка записи задачи',
          );
          await tester.pump();
          await h.tap(find.widgetWithText(FilledButton, 'Создать'));
          await h.waitFor(
            () => find.byKey(const Key('shared-task-title')).evaluate().isEmpty,
            'Create closed editor',
          );
          await h.quiet();
          final row = await read(title);
          expect(row['body'], 'Проверка записи задачи');
          expect(row['state'], 'open');
          h.facts.add({'step': h.currentStep, 'row': row});
        }

        Future<void> close(String title) async {
          final row = await read(title);
          final id = row['id'].toString();
          await h.tap(find.byKey(Key('close-shared-task-$id')));
          expect(
            find.byKey(const Key('shared-task-result-select')),
            findsOneWidget,
          );
          expect((await read(title))['version'], row['version']);
          await h.tap(find.byKey(const Key('shared-task-result-select')));
          await h.tap(find.text('Выполнено').last);
          await h.tap(find.byKey(const Key('shared-task-close-submit')));
          await h.waitFor(
            () => find.byKey(Key('close-shared-task-$id')).evaluate().isEmpty,
            'Closed task leaves open list',
          );
          final after = await read(title, state: 'closed');
          expect(after['id'], id);
          expect(after['version'], (row['version'] as num).toInt() + 1);
          final history = await crm.listSharedTaskHistory(id);
          h.facts.add({
            'step': h.currentStep,
            'before': row,
            'after': after,
            'history': history,
          });
          expect(
            history.any(
              (item) => item['action'] == 'workflow.shared_task_closed',
            ),
            true,
          );
        }

        await h.check(
          'TASKS-MENU',
          'Меню → Задачи с настоящими правами',
          () async {
            await h.mount(const StaffWorkspaceScreen());
            await h.tap(find.text('Задачи'));
            await h.waitFor(
              () => find.byType(SharedTasksPanel).evaluate().isNotEmpty,
              'Task destination',
            );
          },
        );
        if (role == 'admin') {
          await h.check(
            'TASKS-ADMIN-ACCESS',
            'Администратор не может создать или изменить задачу',
            () async {
              expect(find.text('Новая задача'), findsNothing);
              expect(find.byTooltip('Изменить'), findsNothing);
              final today = find.byKey(const Key('shared-task-today-filter'));
              expect(tester.widget<ChoiceChip>(today).selected, true);
              await h.tap(today);
              await h.quiet();
            },
          );
          await h.check(
            'TASKS-ADMIN-READ',
            'Администратор видит назначенную задачу после снятия фильтра Сегодня',
            () async {
              final row = await read('TASK-AUDIT-admin');
              expect(find.text('TASK-AUDIT-admin'), findsOneWidget);
              h.facts.add({'step': h.currentStep, 'row': row});
            },
          );
          if (h.steps.last['status'] == 'PASS') {
            await h.check(
              'TASKS-ADMIN-CLOSE',
              'Администратор закрывает назначенную задачу → API и история',
              () => close('TASK-AUDIT-admin'),
            );
          } else {
            h.blocked(
              'TASKS-ADMIN-CLOSE',
              'Закрыть назначенную задачу',
              'TASKS-ADMIN-READ',
            );
          }
          await h.finish();
          return;
        }
        final title = 'TASK-AUDIT-$role';
        final changed = '$title изменена';
        await h.check(
          'TASKS-EDITOR',
          'Кнопка Новая задача загружает редактор и получателей',
          enterEditor,
        );
        await h.check(
          'TASKS-EMPTY',
          'Пустое название блокирует создание',
          () async {
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Создать'),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              h.requests.where(
                (request) =>
                    request['method'] == 'POST' &&
                    request['path'] == '/api/crm/shared-tasks',
              ),
              isEmpty,
            );
          },
        );
        await h.check(
          'TASKS-CREATE',
          'Заполнить и создать задачу → серверное чтение',
          () => create(title),
        );
        if (h.steps.last['status'] != 'PASS') {
          for (final id in ['TASKS-EDIT', 'TASKS-REOPEN', 'TASKS-CLOSE']) {
            h.blocked(id, 'Зависит от созданной задачи', 'TASKS-CREATE');
          }
          await h.finish();
          return;
        }
        await h.check(
          'TASKS-EDIT',
          'Изменить название задачи → серверное чтение',
          () async {
            final before = await read(title);
            final card = find
                .ancestor(of: find.text(title), matching: find.byType(Card))
                .first;
            await h.tap(
              find.descendant(of: card, matching: find.byTooltip('Изменить')),
            );
            await h.waitFor(
              () => find
                  .byKey(const Key('shared-task-title'))
                  .evaluate()
                  .isNotEmpty,
              'Edit existing task',
            );
            await tester.enterText(
              find.byKey(const Key('shared-task-title')),
              changed,
            );
            await tester.pump();
            await h.tap(find.widgetWithText(FilledButton, 'Сохранить'));
            await h.waitFor(
              () =>
                  find.byKey(const Key('shared-task-title')).evaluate().isEmpty,
              'Edit saved',
            );
            final after = await read(changed);
            expect(after['id'], before['id']);
            expect(after['version'], (before['version'] as num).toInt() + 1);
            h.facts.add({
              'step': h.currentStep,
              'before': before,
              'after': after,
            });
          },
        );
        await h.check(
          'TASKS-REOPEN',
          'Повторно открыть редактор и отменить без изменения',
          () async {
            final card = find
                .ancestor(of: find.text(changed), matching: find.byType(Card))
                .first;
            await h.tap(
              find.descendant(of: card, matching: find.byTooltip('Изменить')),
            );
            await h.waitFor(
              () => find
                  .byKey(const Key('shared-task-title'))
                  .evaluate()
                  .isNotEmpty,
              'Reopened editor',
            );
            expect(
              tester
                  .widget<TextField>(find.byKey(const Key('shared-task-title')))
                  .controller!
                  .text,
              changed,
            );
            final before = await read(changed);
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
            expect((await read(changed))['version'], before['version']);
          },
        );
        await h.check(
          'TASKS-CLOSE',
          'Закрыть задачу → API и история',
          () => close(changed),
        );
        if (role == 'manager') {
          await h.check(
            'TASKS-FOR-ADMIN',
            'Создать общую задачу для последующей проверки администратора',
            () async {
              await enterEditor();
              await create('TASK-AUDIT-admin');
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
