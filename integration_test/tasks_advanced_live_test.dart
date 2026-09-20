import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'live_audit_harness.dart';

final _sourceProvider = Provider<SharedTasksDataSource>(
  (ref) => MagicCrmSharedTasksDataSource(ref),
);
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director']) {
    testWidgets(
      '$role task intervals audiences reminders',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'tasks-advanced');
        await h.initialize(size: const Size(1500, 1500));
        final source = h.scope.read(_sourceProvider);
        Map<String, dynamic>? saved;
        final title = 'AUDIT-ADVANCED-$role';
        Future<Map<String, dynamic>> read() async {
          final r = await source.listFiltered(q: title);
          final row = (r['items'] as List).cast<Map<String, dynamic>>().single;
          h.facts.add({'step': h.currentStep, 'task': row});
          return row;
        }

        Future<void> open({bool edit = false}) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showSharedTaskEditor(
                    ctx,
                    dataSource: source,
                    task: edit ? saved : null,
                  ),
                  child: const Text('Открыть редактор'),
                ),
              ),
            ),
          );
          await h.tap(find.text('Открыть редактор'));
          await h.quiet();
          expect(find.byKey(const Key('shared-task-title')), findsOneWidget);
        }

        Future<void> acceptPicker(Type type) async {
          final dialog = find.byType(type);
          await h.waitFor(() => dialog.evaluate().isNotEmpty, 'Picker opened');
          final l = MaterialLocalizations.of(tester.element(dialog));
          await h.tap(
            find.descendant(of: dialog, matching: find.text(l.okButtonLabel)),
          );
        }

        Future<void> chooseDate(String label, DateTime date) async {
          await h.tap(find.widgetWithText(ListTile, label));
          final d = find.byType(DatePickerDialog);
          await h.waitFor(() => d.evaluate().isNotEmpty, 'Date picker opened');
          final l = MaterialLocalizations.of(tester.element(d));
          await h.tap(
            find.descendant(
              of: d,
              matching: find.byTooltip(l.inputDateModeButtonLabel),
            ),
          );
          final f = find.descendant(
            of: d,
            matching: find.byType(TextFormField),
          );
          await tester.enterText(f, l.formatCompactDate(date));
          await acceptPicker(DatePickerDialog);
          await acceptPicker(TimePickerDialog);
        }

        Future<void> submit(bool edit) async {
          await h.tap(
            find.widgetWithText(FilledButton, edit ? 'Сохранить' : 'Создать'),
          );
          await h.quiet();
          await h.waitFor(
            () => find.byKey(const Key('shared-task-title')).evaluate().isEmpty,
            'Task saved and editor closed',
          );
          saved = await read();
        }

        await h.check(
          'INTERVAL',
          'Настроить интервал и отклонить окончание раньше начала',
          () async {
            await open();
            await tester.enterText(
              find.byKey(const Key('shared-task-title')),
              title,
            );
            await h.tap(find.widgetWithText(SwitchListTile, 'На весь день'));
            final date = DateTime.now().add(const Duration(days: 3));
            await chooseDate('Начало', date);
            expect(
              find.byKey(const Key('shared-task-interval-error')),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Создать'),
                  )
                  .onPressed,
              isNull,
            );
            await chooseDate('Окончание', date);
            expect(
              find.byKey(const Key('shared-task-interval-error')),
              findsNothing,
            );
          },
        );
        await h.check(
          'AUDIENCE',
          'Выбрать филиал и проверить preview получателей',
          () async {
            await h.tap(find.text('Один филиал'));
            await h.tap(find.byKey(const Key('shared-task-audience-target')));
            await h.tap(find.text('HTTP test').last);
            await h.tap(find.text('Добавить получателя'));
            await h.quiet();
            expect(
              find.byKey(const Key('shared-task-recipient-total')),
              findsOneWidget,
            );
          },
        );
        await h.check(
          'REMINDER',
          'Включить напоминание и подтвердить точную дату и время',
          () async {
            await h.tap(
              find.widgetWithText(SwitchListTile, 'Напомнить в приложении'),
            );
            await h.tap(find.byKey(const Key('shared-task-reminder-at')));
            await acceptPicker(DatePickerDialog);
            await acceptPicker(TimePickerDialog);
          },
        );
        await h.check(
          'CREATE',
          'Сохранить интервал, филиал и напоминание',
          () async {
            await submit(false);
            expect(saved!['allDay'], false);
            expect(
              DateTime.parse(
                saved!['endAt'],
              ).isAfter(DateTime.parse(saved!['startAt'])),
              true,
            );
            expect(saved!['audiences'], hasLength(1));
            expect((saved!['audiences'] as List).single['type'], 'branch');
            expect(saved!['reminders'], hasLength(1));
          },
        );
        if (saved == null) {
          h.blocked('REOPEN', 'Повторное открытие', 'Создание не подтверждено');
          h.blocked('EDIT', 'Изменение', 'Создание не подтверждено');
          h.blocked('FINAL', 'Итог', 'Создание не подтверждено');
          await h.finish();
          return;
        }
        await h.check(
          'REOPEN',
          'Повторное открытие восстанавливает переключатели и напоминание',
          () async {
            await open(edit: true);
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.widgetWithText(SwitchListTile, 'На весь день'),
                  )
                  .value,
              false,
            );
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.widgetWithText(
                      SwitchListTile,
                      'Напомнить в приложении',
                    ),
                  )
                  .value,
              true,
            );
          },
        );
        await h.check(
          'EDIT',
          'Изменить на весь день и отключить напоминание',
          () async {
            await h.tap(find.widgetWithText(SwitchListTile, 'На весь день'));
            await h.tap(
              find.widgetWithText(SwitchListTile, 'Напомнить в приложении'),
            );
            await submit(true);
            expect(saved!['allDay'], true);
            expect(saved!['reminders'], isEmpty);
          },
        );
        await h.check(
          'FINAL',
          'Итоговый редактор сохраняет весь день без напоминания',
          () async {
            await open(edit: true);
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.widgetWithText(SwitchListTile, 'На весь день'),
                  )
                  .value,
              true,
            );
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.widgetWithText(
                      SwitchListTile,
                      'Напомнить в приложении',
                    ),
                  )
                  .value,
              false,
            );
            await read();
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
