import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'director schedule plan row edit and removal',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'plan-rows');
      await h.initialize(size: const Size(1500, 1500));
      final crm = h.scope.read(magicCrmServiceProvider);
      final studentId = h.fixture['studentId'] as String;
      final id = h.fixture['planId'] as String;
      Future<SchedulePlan> read() async {
        final p = (await crm.listSchedulePlans(
          studentId: studentId,
          includeArchived: true,
        )).singleWhere((p) => p.id == id);
        h.facts.add({
          'step': h.currentStep,
          'id': p.id,
          'status': p.status,
          'version': p.version,
          'archived': p.isArchived,
          'endReason': p.endReason,
          'activeUntil': p.activeUntil,
        });
        return p;
      }

      Future<void> open({bool archived = false}) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          Scaffold(
            body: SingleChildScrollView(
              child: RecurringSchedulePlanSection(
                studentId: studentId,
                subjectName: 'HTTP student',
                fallbackLessons: const [],
                branches: await crm.listBranches(limit: 100),
                defaultBranchId: h.fixture['branchId'] as String,
                subscriptions: await crm.listSubscriptions(
                  studentId: studentId,
                ),
                canWrite: (h.access['capabilities'] as List).contains(
                  'schedule.lesson.write',
                ),
                onChanged: () {},
              ),
            ),
          ),
        );
        await h.quiet();
        if (archived) {
          await h.tap(
            find.byKey(const PageStorageKey('archived-schedule-plans')),
          );
        }
        await h.tap(find.text('HTTP recurring journey').first);
      }

      Future<void> key(String value) => h.tap(find.byKey(Key(value)));
      String? rowId;
      Future<void> edit() async {
        rowId = (await read()).currentRows.single.id;
        await key('schedule-plan-row-edit-$rowId');
        await h.quiet();
        expect(
          find.byKey(const Key('preferred-schedule-save')),
          findsOneWidget,
        );
      }

      await h.check('OPEN', 'Открыть строку постоянного расписания', () async {
        await open();
        await edit();
      });
      await h.check(
        'EDIT-CANCEL',
        'Отмена изменения сохраняет вторник',
        () async {
          expect(
            tester
                .widget<FilterChip>(
                  find.byKey(const Key('preferred-schedule-weekday-2')),
                )
                .onSelected,
            isNull,
          );

          await h.tap(find.text('Отмена').last);
          expect((await read()).currentRows.single.weekday, 2);
        },
      );
      await h.check(
        'EDIT-PREVIEW',
        'Изменить описание строки и открыть общую проверку',
        () async {
          await edit();
          expect(
            tester
                .widget<FilterChip>(
                  find.byKey(const Key('preferred-schedule-weekday-2')),
                )
                .onSelected,
            isNull,
          );

          await tester.enterText(
            find.byKey(const Key('preferred-schedule-notes')),
            'AUDIT-ROW-EDIT',
          );
          await key('preferred-schedule-save');
          await h.quiet();
          expect(
            find.byKey(const Key('schedule-plan-preview-and-create')),
            findsOneWidget,
          );
          expect((await read()).currentRows.single.weekday, 2);
        },
      );
      await h.check(
        'EDIT',
        'Сохранить проверенное изменение без переписывания старых занятий',
        () async {
          await key('schedule-plan-preview-and-create');
          await h.quiet();
          final p = await read();
          expect(p.currentRows.single.weekday, 2);
          expect(p.currentRows.single.notes, 'AUDIT-ROW-EDIT');
          rowId = p.currentRows.single.id;
        },
      );
      await h.check(
        'REOPEN',
        'После открытия сохраняются вторник и заметка строки',
        () async {
          await open();
          final p = await read();
          expect(p.currentRows.single.weekday, 2);
          expect(p.currentRows.single.notes, 'AUDIT-ROW-EDIT');
        },
      );
      Future<void> removal() async {
        rowId = (await read()).currentRows.single.id;
        await key('remove-plan-row-$rowId');
        await h.quiet();
      }

      await h.check(
        'REMOVE-PREVIEW',
        'Удаление строки требует причину и показывает последствия',
        () async {
          await removal();
          await key('schedule-plan-row-removal-submit');
          expect(find.text('Укажите причину удаления строки.'), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('schedule-plan-row-removal-reason')),
            'AUDIT-ROW-REMOVE',
          );
          await key('schedule-plan-row-removal-submit');
          await h.quiet();
          expect(
            find.byKey(const Key('schedule-plan-row-removal-impact')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('schedule-plan-row-removal-submit')),
                )
                .onPressed,
            isNull,
          );
        },
      );
      await h.check(
        'REMOVE-CANCEL',
        'Отмена удаления сохраняет действующую строку',
        () async {
          await h.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
          expect((await read()).currentRows, hasLength(1));
        },
      );
      await h.check(
        'REMOVE',
        'Подтверждение удаляет последнюю действующую строку и завершает план',
        () async {
          await removal();
          await tester.enterText(
            find.byKey(const Key('schedule-plan-row-removal-reason')),
            'AUDIT-ROW-REMOVE',
          );
          await key('schedule-plan-row-removal-submit');
          await h.quiet();
          await key('schedule-plan-row-removal-confirm');
          await key('schedule-plan-row-removal-submit');
          await h.quiet();
          expect((await read()).status, 'ended');
        },
      );
      await h.check(
        'FINAL',
        'Повторное открытие сохраняет завершение и историю строк',
        () async {
          await open();
          expect((await read()).status, 'ended');
          expect(find.byTooltip('Удалить строку'), findsNothing);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
