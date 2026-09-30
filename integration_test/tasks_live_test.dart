import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/services/section_unseen_service.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/core/navigation/responsive_navigation_shell.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_results_panel.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  const embeddedFixture = String.fromEnvironment('HTTP_JOURNEY_FIXTURE');
  final fixtureText = embeddedFixture.isNotEmpty
      ? embeddedFixture
      : Platform.environment['HTTP_JOURNEY_FIXTURE'] ?? '{}';
  final restartOnly = (jsonDecode(fixtureText) as Map)['x08Restart'] == true;
  for (final role
      in restartOnly ? ['admin'] : ['manager', 'admin', 'director']) {
    testWidgets(
      '$role task commands through workspace menu',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'tasks');
        await h.initialize(
          size: const Size(1440, 1100),
          liveCrmRealtime: role == 'admin',
        );
        final crm = h.scope.read(magicCrmServiceProvider);
        if (restartOnly) {
          await h.check(
            'TASKS-X08-PROCESS-RESTART',
            'Новый процесс открывает сохранённые 15 задач через меню',
            () async {
              await h.mount(const StaffWorkspaceScreen());
              await h.tap(find.text('Задачи'));
              await h.waitFor(
                () => find.text('15').evaluate().isNotEmpty,
                'Persisted task badge after process restart',
              );
              await h.waitFor(
                () => find.text('TASK-X08-TODAY-6').evaluate().isNotEmpty,
                'Persisted task card after process restart',
              );
              expect(find.text('TASK-X08-TODAY-6'), findsOneWidget);
              final persisted = await crm.listSharedTasks(
                q: 'TASK-X08-TODAY-6',
                state: 'open',
              );
              expect((persisted['items'] as List).length, 1);
            },
          );
          await h.finish();
          return;
        }
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

        Future<void> showTask(String title) async {
          await tester.enterText(
            find.byKey(const Key('shared-task-search')),
            title,
          );
          await h.tap(find.byTooltip('Найти задачи'));
          await h.quiet();
          expect(
            find.descendant(of: find.byType(Card), matching: find.text(title)),
            findsOneWidget,
          );
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
          await h.check(
            'TASKS-ADMIN-EMPTY',
            'Пустой список не предлагает admin создавать задачу',
            () async {
              await tester.enterText(
                find.byKey(const Key('shared-task-search')),
                'TASK-X08-NO-MATCH',
              );
              await h.tap(find.byTooltip('Найти задачи'));
              await h.quiet();
              expect(
                find.text('Назначенных вам задач по выбранному фильтру нет.'),
                findsOneWidget,
              );
              expect(find.text('Новая задача'), findsNothing);
              expect(
                h.requests.where(
                  (r) =>
                      r['method'] == 'POST' &&
                      r['path'] == '/api/crm/shared-tasks',
                ),
                isEmpty,
              );
            },
          );
          final director = (h.fixture['accounts'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((account) => account['role'] == 'director');
          final directorApi = MagicApiClient(
            baseUrl: h.fixture['baseUrl'],
            tokenStore: MemoryMagicTokenStore(),
          );
          addTearDown(() => directorApi.rawDio.close(force: true));
          final login = await directorApi.post<Map<String, dynamic>>(
            '/auth/login',
            authenticated: false,
            data: {
              'email': director['email'],
              'password': h.fixture['password'],
            },
          );
          await directorApi.saveTokens(
            MagicApiTokens.fromJson(
              Map<String, dynamic>.from(login['session'] as Map),
            ),
          );
          final moscow = DateTime.now().toUtc().add(const Duration(hours: 3));
          String dueAt(int offset, int minute) => DateTime.utc(
            moscow.year,
            moscow.month,
            moscow.day + offset,
            9,
            minute,
          ).toIso8601String();
          final todayTasks = <Map<String, dynamic>>[];
          await h.check(
            'TASKS-X08-SEED',
            'Создать 20 сегодня, 2 завтра и 2 вчера через director API',
            () async {
              await h.waitFor(
                () => h.crmSocketConnects > 0,
                'CRM socket connected before external task creation',
              );
              for (final (offset, count, label) in [
                (0, 20, 'TODAY'),
                (1, 2, 'FUTURE'),
                (-1, 2, 'YESTERDAY'),
              ]) {
                for (var index = 1; index <= count; index++) {
                  final task = await directorApi.post<Map<String, dynamic>>(
                    '/crm/shared-tasks',
                    data: {
                      'title': 'TASK-X08-$label-$index',
                      'allDay': true,
                      'startAt': dueAt(offset, index),
                      'audiences': [
                        {'type': 'branch', 'targetId': h.fixture['branchId']},
                      ],
                    },
                  );
                  if (offset == 0) todayTasks.add(task);
                }
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await h.mount(const StaffWorkspaceScreen());
              await h.tap(find.text('Задачи').last);
              await h.waitFor(
                () => h.crmSocketConnects > 0,
                'CRM socket connected before task closing',
              );
              await h.waitFor(
                () => find.text('20').evaluate().isNotEmpty,
                'Navigation badge counts exactly 20 assigned tasks today',
              );
              expect(find.text('TASK-X08-TODAY-1'), findsOneWidget);
              h.facts.add({
                'step': h.currentStep,
                'taskIds': todayTasks.map((task) => task['id']).toList(),
                'badge': 20,
                'socketConnects': h.crmSocketConnects,
              });
            },
          );
          await h.check(
            'TASKS-X08-CLOSE',
            'UI закрывает 5 задач с разными результатами: 20 → 15',
            () async {
              final outcomes = [
                ('other', 'Другое', 'Уточнён результат X08'),
                ('completed', 'Выполнено', ''),
                ('not_completed', 'Не выполнено', ''),
                ('follow_up', 'Нужен следующий контакт', ''),
                ('completed', 'Выполнено', 'Комментарий X08'),
              ];
              for (var index = 0; index < outcomes.length; index++) {
                final task = todayTasks[index];
                final id = task['id'].toString();
                int closeCalls() => h.requests
                    .where(
                      (request) =>
                          request['method'] == 'POST' &&
                          request['path'] == '/api/crm/shared-tasks/$id/close',
                    )
                    .length;
                await h.tap(find.byKey(Key('close-shared-task-$id')));
                final submit = find.byKey(
                  const Key('shared-task-close-submit'),
                );
                if (index == 0) {
                  final before = closeCalls();
                  await h.tap(submit);
                  expect(
                    find.text('Выберите результат выполнения задачи.'),
                    findsOneWidget,
                  );
                  expect(closeCalls(), before);
                }
                await h.tap(find.byKey(const Key('shared-task-result-select')));
                await h.tap(find.text(outcomes[index].$2).last);
                if (index == 0) {
                  final before = closeCalls();
                  await h.tap(submit);
                  expect(
                    find.text('Для результата «Другое» добавьте пояснение.'),
                    findsOneWidget,
                  );
                  expect(closeCalls(), before);
                }
                if (outcomes[index].$3.isNotEmpty) {
                  await tester.enterText(
                    find.byKey(const Key('shared-task-result-comment')),
                    outcomes[index].$3,
                  );
                }
                await h.tap(submit);
                await h.waitFor(
                  () => submit.evaluate().isEmpty,
                  'Close dialog dismissed',
                );
                await h.waitFor(
                  () => find
                      .byKey(Key('close-shared-task-$id'))
                      .evaluate()
                      .isEmpty,
                  'Task $id leaves open list',
                );
                final closed = await read(
                  task['title'].toString(),
                  state: 'closed',
                );
                final result = closed['closure']['result'];
                expect(result['code'], outcomes[index].$1);
                expect(result['comment'] ?? '', outcomes[index].$3);
                await h.waitFor(
                  () => find.text('${19 - index}').evaluate().isNotEmpty,
                  'Navigation badge decremented after close',
                );
              }
              h.facts.add({'step': h.currentStep, 'badge': 15});
            },
          );
          await h.check(
            'TASKS-X08-CONFLICT',
            '409 сохраняет результат и комментарий в открытой форме',
            () async {
              final task = todayTasks[5];
              final id = task['id'].toString();
              await h.tap(find.byKey(Key('close-shared-task-$id')));
              await h.tap(find.byKey(const Key('shared-task-result-select')));
              await h.tap(find.text('Другое').last);
              await tester.enterText(
                find.byKey(const Key('shared-task-result-comment')),
                'Черновик X08 после конфликта',
              );
              await directorApi.patch<Map<String, dynamic>>(
                '/crm/shared-tasks/$id',
                data: {
                  'expectedVersion': task['version'],
                  'title': task['title'],
                  'body': 'Параллельная правка X08',
                  'allDay': true,
                  'startAt': task['startAt'],
                  'priority': task['priority'],
                  'audiences': [
                    {'type': 'branch', 'targetId': h.fixture['branchId']},
                  ],
                },
              );
              await h.tap(find.byKey(const Key('shared-task-close-submit')));
              await h.waitFor(
                () => find
                    .byKey(const Key('shared-task-close-error'))
                    .evaluate()
                    .isNotEmpty,
                'Server conflict shown inside close dialog',
              );
              expect(
                tester
                    .widget<TextFormField>(
                      find.byKey(const Key('shared-task-result-comment')),
                    )
                    .controller!
                    .text,
                'Черновик X08 после конфликта',
              );
              expect((await read(task['title'].toString()))['state'], 'open');
              await h.tap(find.widgetWithText(TextButton, 'Отмена'));
              h.facts.add({
                'step': h.currentStep,
                'taskId': id,
                'draftKept': true,
              });
            },
            expectedHttpErrors: [
              (
                method: 'POST',
                path: '/api/crm/shared-tasks/${todayTasks[5]['id']}/close',
                status: 409,
                maxCount: 1,
              ),
            ],
          );
          await h.check(
            'TASKS-X08-REOPEN',
            'Просмотр и повторное открытие оставляют счётчик 15',
            () async {
              await tester.pumpWidget(const SizedBox.shrink());
              await h.mount(const StaffWorkspaceScreen());
              await h.tap(find.text('Задачи').last);
              expect(find.text('15'), findsOneWidget);
              final unseen = await h.scope.read(sectionUnseenProvider.future);
              expect(unseen['tasks'], 15);
            },
          );
          await h.check(
            'TASKS-X08-RECONNECT',
            'После пропущенного события reconnect восстанавливает счётчик',
            () async {
              h.crmSocketTransport!.disconnect();
              final extra = await directorApi.post<Map<String, dynamic>>(
                '/crm/shared-tasks',
                data: {
                  'title': 'AUDIT-X08-RECOVERY',
                  'allDay': true,
                  'startAt': dueAt(0, 30),
                  'audiences': [
                    {'type': 'branch', 'targetId': h.fixture['branchId']},
                  ],
                },
              );
              await Future<void>.delayed(const Duration(seconds: 3));
              expect(find.text('15'), findsOneWidget);
              h.crmSocketTransport!.connect();
              await h.waitFor(
                () => h.crmSocketConnects > 1,
                'CRM socket reconnected',
              );
              await h.waitFor(
                () => find.text('16').evaluate().isNotEmpty,
                'Missed task appears in navigation badge after reconnect',
              );
              await directorApi.post<Map<String, dynamic>>(
                '/crm/shared-tasks/${extra['id']}/close',
                data: {
                  'expectedVersion': extra['version'],
                  'resultCode': 'completed',
                  'resultLabel': 'Выполнено',
                },
              );
              await h.waitFor(
                () => find.text('15').evaluate().isNotEmpty,
                'Remote close updates navigation badge through CRM stream',
              );
              h.facts.add({
                'step': h.currentStep,
                'socketConnects': h.crmSocketConnects,
                'badge': 15,
              });
            },
          );
          await h.check(
            'TASKS-X08-MIDNIGHT',
            'Открытый экран переходит на новый московский день без remount',
            () async {
              var clock = DateTime.utc(
                moscow.year,
                moscow.month,
                moscow.day,
                20,
                59,
                50,
              );
              await h.mount(
                Scaffold(
                  body: SharedTasksPanel(
                    defaultToMineToday: true,
                    now: () => clock,
                  ),
                ),
              );
              await h.quiet();
              expect(find.text('TASK-X08-TODAY-6'), findsOneWidget);
              expect(find.text('TASK-X08-FUTURE-1'), findsNothing);

              clock = DateTime.utc(
                moscow.year,
                moscow.month,
                moscow.day,
                21,
                0,
                1,
              );
              await tester.pump(const Duration(seconds: 11));
              await h.quiet();
              expect(find.text('TASK-X08-TODAY-6'), findsNothing);
              expect(find.text('TASK-X08-FUTURE-1'), findsOneWidget);
              final day = DateTime.utc(
                moscow.year,
                moscow.month,
                moscow.day + 1,
              );
              h.facts.add({
                'step': h.currentStep,
                'nextMoscowDay': day.toIso8601String(),
                'futureTaskCount': 2,
              });
            },
          );
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
            await showTask(title);
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
            await h.quiet();
            await h.waitFor(
              () =>
                  tester
                      .widget<FilledButton>(
                        find.widgetWithText(FilledButton, 'Сохранить'),
                      )
                      .onPressed !=
                  null,
              'Task editor is ready after audience preview',
            );
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
            await showTask(changed);
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
          () async {
            await showTask(changed);
            await close(changed);
          },
        );
        if (role == 'director') {
          await h.check(
            'TASKS-X08-JOURNAL',
            'Director открывает журнал и видит комментарий, автора и время',
            () async {
              await h.tap(find.byKey(const Key('shared-task-open-results')));
              await h.waitFor(
                () => find.byType(SharedTaskResultsPanel).evaluate().isNotEmpty,
                'Results panel opened',
              );
              await tester.enterText(
                find.byKey(const Key('shared-task-results-search')),
                'TASK-X08-TODAY-1',
              );
              await h.tap(find.byTooltip('Найти'));
              await h.waitFor(
                () => find.text('Уточнён результат X08').evaluate().isNotEmpty,
                'Persisted comment visible in journal',
              );
              expect(find.text('Другое'), findsWidgets);
              expect(find.text('Закрыл'), findsWidgets);
              expect(find.text('Закрыта'), findsWidgets);
              await h.tap(find.byKey(const Key('shared-task-results-result')));
              await h.tap(find.widgetWithText(MenuItemButton, 'Другое'));
              await h.quiet();
              expect(find.text('Уточнён результат X08'), findsOneWidget);
              await h.tap(
                find.byKey(const Key('shared-task-results-period-week')),
              );
              await h.quiet();
              expect(find.text('Уточнён результат X08'), findsOneWidget);
              await h.tap(find.byKey(const Key('shared-task-results-back')));
              await h.tap(find.byKey(const Key('shared-task-open-results')));
              await h.waitFor(
                () => find.byType(SharedTaskResultsPanel).evaluate().isNotEmpty,
                'Results panel reopened',
              );
              await tester.enterText(
                find.byKey(const Key('shared-task-results-search')),
                'TASK-X08-LEGACY',
              );
              await h.tap(find.byTooltip('Найти'));
              await h.waitFor(
                () => find
                    .text('Историческое закрытие: результат не зафиксирован')
                    .evaluate()
                    .isNotEmpty,
                'Legacy closure appears without manufactured result',
              );
              await h.tap(find.byKey(const Key('shared-task-results-result')));
              await h.tap(
                find.widgetWithText(MenuItemButton, 'Без результата (история)'),
              );
              await h.quiet();
              expect(
                find.text('Историческое закрытие: результат не зафиксирован'),
                findsOneWidget,
              );
            },
          );
        }
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
        if (role == 'director') {
          await h.check(
            'TASKS-TODAY-COUNT',
            '20 задач сегодня → просмотр не обнуляет → закрытие пяти даёт 15',
            () async {
              final account = await h.scope.read(
                capabilitySnapshotProvider.future,
              );
              final before = await h.api.get<Map<String, dynamic>>(
                '/crm/sections/unseen',
              );
              final baseline = (before['tasks'] as num).toInt();
              final moscowNow = DateTime.now().toUtc().add(
                const Duration(hours: 3),
              );
              DateTime dayAtUtc(int offset) => DateTime.utc(
                moscowNow.year,
                moscowNow.month,
                moscowNow.day + offset,
                9,
              );
              Future<Map<String, dynamic>> create(int index, int offset) =>
                  h.api.post<Map<String, dynamic>>(
                    '/crm/shared-tasks',
                    data: {
                      'title': 'AUDIT-COUNT-$index',
                      'allDay': true,
                      'startAt': dayAtUtc(offset).toIso8601String(),
                      'audiences': [
                        {'type': 'user', 'targetId': account.accountId},
                      ],
                    },
                  );
              final created = <Map<String, dynamic>>[];
              for (var index = 0; index < 20; index++) {
                created.add(await create(index, 0));
              }
              await create(20, 1);
              await create(21, -1);
              Future<int> count() async =>
                  ((await h.api.get<Map<String, dynamic>>(
                            '/crm/sections/unseen',
                          ))['tasks']
                          as num)
                      .toInt();
              expect(await count(), baseline + 20);
              await h.api.post<Map<String, dynamic>>(
                '/crm/sections/seen',
                data: {'section': 'tasks'},
              );
              expect(await count(), baseline + 20);
              h.scope.invalidate(sectionUnseenProvider);
              await h.quiet();
              int badge() => tester
                  .widget<ResponsiveNavigationShell>(
                    find.byType(ResponsiveNavigationShell).first,
                  )
                  .destinations
                  .singleWhere((destination) => destination.label == 'Задачи')
                  .badgeCount;
              await h.waitFor(
                () => badge() == baseline + 20,
                'Today badge loaded',
              );
              for (final row in created.take(5)) {
                await h.api.post<Map<String, dynamic>>(
                  '/crm/shared-tasks/${row['id']}/close',
                  data: {
                    'expectedVersion': row['version'],
                    'resultCode': 'completed',
                    'resultLabel': 'Выполнено',
                  },
                );
              }
              expect(await count(), baseline + 15);
              final second = MagicApiClient(
                baseUrl: h.fixture['baseUrl'] as String,
                tokenStore: MemoryMagicTokenStore(),
              );
              addTearDown(() => second.rawDio.close(force: true));
              final director = (h.fixture['accounts'] as List)
                  .cast<Map<String, dynamic>>()
                  .singleWhere((account) => account['role'] == 'director');
              final login = await second.post<Map<String, dynamic>>(
                '/auth/login',
                authenticated: false,
                data: {
                  'email': director['email'],
                  'password': h.fixture['password'],
                },
              );
              await second.saveTokens(
                MagicApiTokens.fromJson(
                  Map<String, dynamic>.from(login['session'] as Map),
                ),
              );
              final secondView = await second.get<Map<String, dynamic>>(
                '/crm/sections/unseen',
              );
              expect((secondView['tasks'] as num).toInt(), baseline + 15);
              h.scope.invalidate(sectionUnseenProvider);
              await h.quiet();
              await h.waitFor(
                () => badge() == baseline + 15,
                'Badge after five closes',
              );
              h.facts.add({
                'step': h.currentStep,
                'baseline': baseline,
                'createdToday': 20,
                'futureExcluded': true,
                'overdueExcluded': true,
                'afterClose': await count(),
                'secondSessionCount': secondView['tasks'],
                'badge': badge(),
              });
            },
          );
          await h.check(
            'TASKS-TWO-SESSION-REALTIME',
            'Две сессии получают изменение задачи, одна восстанавливает связь',
            () async {
              final account = await h.scope.read(
                capabilitySnapshotProvider.future,
              );
              final second = MagicApiClient(
                baseUrl: h.fixture['baseUrl'] as String,
                tokenStore: MemoryMagicTokenStore(),
              );
              addTearDown(() => second.rawDio.close(force: true));
              final director = (h.fixture['accounts'] as List)
                  .cast<Map<String, dynamic>>()
                  .singleWhere((row) => row['role'] == 'director');
              final login = await second.post<Map<String, dynamic>>(
                '/auth/login',
                authenticated: false,
                data: {
                  'email': director['email'],
                  'password': h.fixture['password'],
                },
              );
              await second.saveTokens(
                MagicApiTokens.fromJson(
                  Map<String, dynamic>.from(login['session'] as Map),
                ),
              );
              final firstRealtime = MagicRealtimeService(
                api: h.api,
                apiBaseUrl: h.fixture['baseUrl'] as String,
              );
              final secondRealtime = MagicRealtimeService(
                api: second,
                apiBaseUrl: h.fixture['baseUrl'] as String,
                transportFactory: (origin, options) =>
                    SocketIoMagicRealtimeTransport(origin, {
                      ...options,
                      'forceNew': true,
                    }),
              );
              addTearDown(firstRealtime.resetSession);
              addTearDown(secondRealtime.resetSession);
              final firstConnection = await firstRealtime.connect();
              final secondConnection = await secondRealtime.connect();
              addTearDown(firstConnection.dispose);
              addTearDown(secondConnection.dispose);
              final firstEvents = <String>[];
              final secondEvents = <String>[];
              firstConnection.onCrmChanged((event) {
                if (event['entity'] == 'task') {
                  firstEvents.add('${event['id']}');
                }
              });
              secondConnection.onCrmChanged((event) {
                if (event['entity'] == 'task') {
                  secondEvents.add('${event['id']}');
                }
              });
              await tester.pump(const Duration(seconds: 2));
              final moscowNow = DateTime.now().toUtc().add(
                const Duration(hours: 3),
              );
              final tomorrow = DateTime.utc(
                moscowNow.year,
                moscowNow.month,
                moscowNow.day + 1,
                9,
              ).toIso8601String();
              Future<String> create(String suffix) async {
                final task = await h.api.post<Map<String, dynamic>>(
                  '/crm/shared-tasks',
                  data: {
                    'title': 'AUDIT-REALTIME-$suffix',
                    'allDay': true,
                    'startAt': tomorrow,
                    'audiences': [
                      {'type': 'user', 'targetId': account.accountId},
                    ],
                  },
                );
                return task['id'] as String;
              }

              final both = await create('BOTH');
              await h.waitFor(
                () => firstEvents.contains(both) && secondEvents.contains(both),
                'Both connected sessions received the same task event',
              );
              h.facts.add({
                'step': h.currentStep,
                'phase': 'both-connected',
                'taskId': both,
                'firstEvents': firstEvents.toList(),
                'secondEvents': secondEvents.toList(),
              });
              secondConnection.disconnect();
              await tester.pump(const Duration(seconds: 1));
              final missed = await create('OFFLINE');
              h.facts.add({
                'step': h.currentStep,
                'phase': 'after-offline-write',
                'taskId': missed,
                'firstEvents': firstEvents.toList(),
                'secondEvents': secondEvents.toList(),
              });
              try {
                await h.waitFor(
                  () => firstEvents.contains(missed),
                  'Connected session received offline-period event',
                );
              } catch (_) {
                h.facts.add({
                  'step': h.currentStep,
                  'phase': 'offline-event-timeout',
                  'taskId': missed,
                  'firstEvents': firstEvents.toList(),
                  'secondEvents': secondEvents.toList(),
                });
                rethrow;
              }
              expect(secondEvents, isNot(contains(missed)));
              secondConnection.connect();
              await tester.pump(const Duration(seconds: 2));
              final restored = await create('RESTORED');
              await h.waitFor(
                () =>
                    firstEvents.contains(restored) &&
                    secondEvents.contains(restored),
                'Reconnected session received a new task event',
              );
              h.facts.add({
                'step': h.currentStep,
                'both': both,
                'offline': missed,
                'restored': restored,
                'firstReceived': firstEvents,
                'secondReceived': secondEvents,
              });
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
  testWidgets(
    'manager reads persisted task results in a new session',
    (tester) async {
      final h = LiveAuditHarness(tester, 'manager', 'tasks-manager-results');
      await h.initialize(size: const Size(1440, 1100));
      await h.check(
        'TASKS-X08-MANAGER-JOURNAL',
        'Manager открывает журнал после закрытия задач admin',
        () async {
          await h.mount(const StaffWorkspaceScreen());
          await h.tap(find.text('Задачи').last);
          await h.tap(find.byKey(const Key('shared-task-open-results')));
          await tester.enterText(
            find.byKey(const Key('shared-task-results-search')),
            'TASK-X08-TODAY-1',
          );
          await h.tap(find.byTooltip('Найти'));
          await h.waitFor(
            () => find.text('Уточнён результат X08').evaluate().isNotEmpty,
            'Manager sees persisted result comment',
          );
          expect(find.text('Закрыл'), findsWidgets);
          expect(find.text('Закрыта'), findsWidgets);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
