import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director']) {
    testWidgets(
      '$role reviews account deletion requests using actual queues',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'deletion-queue');
        await h.initialize(size: const Size(1440, 1300));
        final service = h.scope.read(magicProfileAdminServiceProvider);
        final rejectedId = h.fixture['rejectedId'] as String,
            completedId = h.fixture['completedId'] as String;
        Future<Map<String, dynamic>> current(String id) async {
          final row = (await service.listDeletionRequests()).singleWhere(
            (r) => r['id'] == id,
          );
          h.facts.add({'step': h.currentStep, 'request': row});
          return row;
        }

        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'data'),
          );
          await h.quiet();
          await h.tap(find.text('Запросы на удаление'));
          await h.quiet();
        }

        Future<void> action(String id, String label) async {
          final row = await current(id);
          final name =
              (row['profileName'] ?? row['email'] ?? row['userEmail'])
                  as String;
          final card = find
              .ancestor(
                of: find.text(name),
                matching: find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_DeletionRequestCard',
                ),
              )
              .first;
          await h.tap(find.descendant(of: card, matching: find.text(label)));
          await h.quiet();
        }

        Future<void> confirm(String label) =>
            h.tap(find.widgetWithText(ElevatedButton, label));
        Future<void> cancel() =>
            h.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
        Future<void> note(String value) async {
          final field = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Резолюция',
          );
          await h.tap(field);
          await tester.enterText(field, value);
          await tester.pump();
        }

        await h.check(
          'OPEN',
          'Открыть два ожидающих запроса через настройки данных',
          () async {
            await open();
            expect(
              (await service.listDeletionRequests(status: 'pending')).length,
              2,
            );
            if (role == 'manager') {
              expect(find.text('В работу'), findsNothing);
              expect(find.text('Выполнить'), findsNothing);
              expect(find.text('Отклонить'), findsNothing);
            }
          },
        );
        await h.check(
          'FILTER',
          'Фильтр выполненных пуст, возврат к ожидающим показывает запросы',
          () async {
            await h.tap(find.text('Выполнен'));
            await h.quiet();
            expect(find.text('Нет запросов на удаление'), findsOneWidget);
            await h.tap(find.text('Ожидает'));
            await h.quiet();
            expect(find.text('Нет запросов на удаление'), findsNothing);
          },
        );
        if (role == 'manager') {
          await h.finish();
          return;
        }
        await h.check(
          'PROCESS-CANCEL',
          'Отмена взятия в работу оставляет pending',
          () async {
            await open();
            await action(rejectedId, 'В работу');
            await cancel();
            expect((await current(rejectedId))['status'], 'pending');
          },
        );
        await h.check('PROCESS', 'Взять первый запрос в работу', () async {
          await open();
          await action(rejectedId, 'В работу');
          await confirm('В работу');
          await h.quiet();
          expect((await current(rejectedId))['status'], 'processing');
        });
        await h.check(
          'REJECT-CANCEL',
          'Отклонение требует резолюцию; отмена оставляет processing',
          () async {
            await open();
            await action(rejectedId, 'Отклонить');
            expect(
              tester
                  .widget<ElevatedButton>(
                    find.widgetWithText(ElevatedButton, 'Отклонить'),
                  )
                  .onPressed,
              isNull,
            );
            await note('CANCEL-REJECTION');
            await cancel();
            expect((await current(rejectedId))['status'], 'processing');
          },
        );
        await h.check(
          'REJECT',
          'Отклонить первый запрос с сохранением причины',
          () async {
            await open();
            await action(rejectedId, 'Отклонить');
            await note('AUDIT-REJECTED');
            await confirm('Отклонить');
            await h.quiet();
            final row = await current(rejectedId);
            expect(row['status'], 'rejected');
            expect(row['resolutionNote'], 'AUDIT-REJECTED');
          },
        );
        await h.check(
          'SECOND-PROCESS',
          'Взять второй запрос в работу',
          () async {
            await open();
            await action(completedId, 'В работу');
            await confirm('В работу');
            await h.quiet();
            expect((await current(completedId))['status'], 'processing');
          },
        );
        await h.check(
          'COMPLETE-CANCEL',
          'Обезличивание требует резолюцию и подтверждение; отмена не завершает запрос',
          () async {
            await open();
            await action(completedId, 'Выполнить');
            final button = find.widgetWithText(ElevatedButton, 'Выполнить');
            expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
            await note('CANCEL-COMPLETION');
            expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
            await h.tap(
              find.byKey(const ValueKey('confirm-deletion-anonymization')),
            );
            expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
            await cancel();
            expect((await current(completedId))['status'], 'processing');
          },
        );
        await h.check(
          'COMPLETE',
          'Подтверждение завершает запрос и сохраняет резолюцию',
          () async {
            await open();
            await action(completedId, 'Выполнить');
            await note('AUDIT-COMPLETED');
            await h.tap(
              find.byKey(const ValueKey('confirm-deletion-anonymization')),
            );
            await confirm('Выполнить');
            await h.quiet();
            final row = await current(completedId);
            expect(row['status'], 'completed');
            expect(row['resolutionNote'], 'AUDIT-COMPLETED');
          },
        );
        await h.check(
          'REOPEN-FINAL',
          'Повторное открытие показывает конечные статусы без кнопок повторной обработки',
          () async {
            await open();
            expect((await current(rejectedId))['status'], 'rejected');
            expect((await current(completedId))['status'], 'completed');
            expect(find.text('В работу'), findsNothing);
            expect(find.text('Выполнить'), findsNothing);
            expect(find.text('Отклонить'), findsNothing);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
