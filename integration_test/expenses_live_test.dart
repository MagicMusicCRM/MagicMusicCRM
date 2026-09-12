import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget_widgets.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director']) {
    testWidgets(
      '$role school expense forms and persisted history',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'expenses');
        await h.initialize(size: const Size(1440, 1300));
        final crm = h.scope.read(magicCrmServiceProvider),
            branch = h.fixture['branchId'] as String;
        String? expenseId;
        Future<List<Map<String, dynamic>>> rows() async =>
            ((await crm.listExpenses(branchId: branch))['items'] as List)
                .cast<Map<String, dynamic>>();
        Future<Map<String, dynamic>> current() async {
          final row = (await rows()).singleWhere((r) => r['id'] == expenseId);
          h.facts.add({'step': h.currentStep, 'expense': row});
          return row;
        }

        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          final now = DateTime.now();
          await h.mount(
            Scaffold(
              body: ReportsWidget(
                role: role,
                initialTab: 1,
                initialViewState: ContextViewState(
                  filters: {
                    'dashboardFrom': DateTime(
                      now.year,
                      now.month,
                      1,
                    ).toIso8601String(),
                    'dashboardTo': DateTime(
                      now.year,
                      now.month + 1,
                      0,
                    ).toIso8601String(),
                    'branchId': branch,
                  },
                ),
              ),
            ),
          );
          await h.quiet();
        }

        Finder field(int index) => find
            .descendant(
              of: find.byType(ExpenseSheetForm),
              matching: find.byType(TextField),
            )
            .at(index);
        Future<void> fill(int index, String value) async {
          await h.tap(field(index));
          await tester.enterText(field(index), value);
          await tester.pump();
        }

        Future<void> add() =>
            h.tap(find.widgetWithText(FilledButton, 'Расход'));
        Future<void> close() =>
            h.tap(find.byKey(const ValueKey('magic-modal-close')));
        Future<void> menu(String label) async {
          await h.tap(find.byKey(ValueKey('expense-actions-$expenseId')));
          await h.tap(find.text(label).last);
          await h.quiet();
        }

        await h.check(
          'OPEN',
          'Журнал финансов доступен директору; управляющий не запускает запрос расходов',
          () async {
            final start = h.requests.length;
            await open();
            if (role == 'manager') {
              expect(find.text('Финансовые операции'), findsNothing);
              expect(find.text('Расход'), findsNothing);
              expect(
                h.requests
                    .skip(start)
                    .any(
                      (r) => (r['path'] ?? '').toString().contains(
                        '/crm/expenses',
                      ),
                    ),
                false,
              );
            } else {
              expect(find.text('Финансовые операции'), findsOneWidget);
              expect(await rows(), isEmpty);
            }
          },
        );
        if (role == 'manager') {
          await h.finish();
          return;
        }
        await h.check(
          'VALIDATION-CANCEL',
          'Пустая сумма, ноль и дробь меньше копейки блокируются; закрытие не создаёт расход',
          () async {
            await add();
            final save = find.widgetWithText(FilledButton, 'Сохранить');
            for (final value in ['', '0', '1.001']) {
              await fill(0, value);
              expect(tester.widget<FilledButton>(save).onPressed, isNull);
            }
            await fill(0, '1200,50');
            expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
            await close();
            expect(await rows(), isEmpty);
          },
        );
        await h.check(
          'CREATE',
          'Сохранить расход с копейками, категорией и комментарием в выбранном филиале',
          () async {
            await open();
            await add();
            await fill(0, '1200,50');
            await fill(1, 'AUDIT-EXPENSE');
            await h.tap(find.widgetWithText(FilledButton, 'Сохранить'));
            await h.quiet();
            final saved = await rows();
            expect(saved.length, 1);
            expenseId = saved.single['id'] as String;
            final row = await current();
            expect(row['amount'], 1200.5);
            expect(row['category'], 'rent');
            expect(row['branchId'], branch);
            expect(row['version'], 1);
            expect(
              find.byKey(ValueKey('expense-actions-$expenseId')),
              findsOneWidget,
            );
          },
        );
        if (expenseId == null) {
          h.blocked(
            'DEPENDENTS',
            'Изменение и удаление расхода',
            'Expense creation failed',
          );
          await h.finish();
          return;
        }
        await h.check(
          'REOPEN',
          'Повторное открытие показывает сохранённый расход',
          () async {
            await open();
            expect(find.textContaining('AUDIT-EXPENSE'), findsOneWidget);
            expect((await current())['version'], 1);
          },
        );
        await h.check(
          'EDIT-CANCEL',
          'Отмена заполненной правки оставляет прежнюю сумму',
          () async {
            await menu('Изменить');
            await fill(0, '9000');
            await fill(1, 'CANCEL-EXPENSE');
            await close();
            expect((await current())['amount'], 1200.5);
          },
        );
        await h.check(
          'EDIT',
          'Изменить сумму, категорию и комментарий с повышением версии',
          () async {
            await open();
            await menu('Изменить');
            await fill(0, '1750');
            await fill(1, 'AUDIT-EXPENSE-EDITED');
            await h.tap(find.byType(DropdownButtonFormField<String>));
            await h.tap(find.text('Маркетинг').last);
            await h.tap(
              find.widgetWithText(FilledButton, 'Сохранить изменения'),
            );
            await h.quiet();
            final row = await current();
            expect(row['amount'], 1750);
            expect(row['category'], 'marketing');
            expect(row['description'], 'AUDIT-EXPENSE-EDITED');
            expect(row['version'], 2);
          },
        );
        await h.check(
          'CLEAR',
          'Очистка необязательного комментария сохраняется',
          () async {
            await open();
            await menu('Изменить');
            await fill(1, '');
            await h.tap(
              find.widgetWithText(FilledButton, 'Сохранить изменения'),
            );
            await h.quiet();
            final row = await current();
            expect(row['description'] ?? '', '');
            expect(row['version'], 3);
          },
        );
        await h.check(
          'STALE',
          'Устаревшая версия отклонена без изменения расхода',
          () async {
            try {
              await crm.updateExpense(
                expenseId: expenseId!,
                expectedVersion: 1,
                amount: 9999,
                category: 'rent',
              );
              fail('Stale write accepted');
            } on MagicApiException catch (error) {
              expect(error.statusCode, 409);
            }
            expect((await current())['amount'], 1750);
          },
          expectedHttpErrors: [
            (
              method: 'PATCH',
              path: '/api/crm/expenses/$expenseId',
              status: 409,
              maxCount: 1,
            ),
          ],
        );
        await h.check(
          'DELETE-CANCEL',
          'Отказ от удаления сохраняет расход и версию',
          () async {
            await open();
            await menu('Удалить');
            await h.tap(find.widgetWithText(TextButton, 'Отмена'));
            expect((await current())['version'], 3);
          },
        );
        await h.check(
          'DELETE',
          'Подтверждение удаляет расход из действующего списка',
          () async {
            await menu('Удалить');
            await h.tap(find.byKey(const ValueKey('confirm-delete-expense')));
            await h.quiet();
            expect(await rows(), isEmpty);
          },
        );
        await h.check(
          'DELETE-REOPEN',
          'Повторное открытие сохраняет пустой список и нулевой итог расходов',
          () async {
            await open();
            expect(find.text('Нет расходов за период'), findsOneWidget);
            expect((await crm.listExpenses(branchId: branch))['total'], 0);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 15)),
    );
  }
}
