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
    'director schedule plan end archive restore',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'plan-lifecycle');
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
                branches: const [],
                defaultBranchId: h.fixture['branchId'] as String,
                subscriptions: const [],
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
      var ended = false, archived = false;
      await h.check(
        'OPEN',
        'Открыть существующее постоянное расписание',
        () async {
          await open();
          expect((await read()).isActive, true);
          expect(find.byKey(Key('schedule-plan-end-$id')), findsOneWidget);
        },
      );
      await h.check(
        'END-VALIDATION',
        'Причина завершения обязательна',
        () async {
          await key('schedule-plan-end-$id');
          await key('schedule-plan-end-submit');
          expect(find.text('Укажите причину завершения.'), findsOneWidget);
          expect((await read()).isActive, true);
        },
      );
      await h.check(
        'END-CANCEL',
        'Рассчитать последствия и отменить без изменения',
        () async {
          await tester.enterText(
            find.byKey(const Key('schedule-plan-end-reason')),
            'AUDIT-END',
          );
          await key('schedule-plan-end-submit');
          await h.quiet();
          expect(
            find.byKey(const Key('schedule-plan-end-impact')),
            findsOneWidget,
          );
          await h.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
          expect((await read()).isActive, true);
        },
      );
      await h.check(
        'END',
        'Завершить расписание через preview и commit',
        () async {
          await key('schedule-plan-end-$id');
          await tester.enterText(
            find.byKey(const Key('schedule-plan-end-reason')),
            'AUDIT-END',
          );
          await key('schedule-plan-end-submit');
          await h.quiet();
          expect(
            find.byKey(const Key('schedule-plan-end-impact')),
            findsOneWidget,
          );
          await key('schedule-plan-end-submit');
          await h.quiet();
          final p = await read();
          expect(p.status, 'ended');
          expect(p.endReason, 'AUDIT-END');
          ended = true;
        },
      );
      if (!ended) {
        for (final s in [
          'END-REOPEN',
          'ARCHIVE-CANCEL',
          'ARCHIVE',
          'ARCHIVE-REOPEN',
          'RESTORE',
          'FINAL',
        ]) {
          h.blocked(s, s, 'Завершение расписания не подтверждено');
        }
        await h.finish();
        return;
      }
      await h.check(
        'END-REOPEN',
        'История завершения сохраняется при повторном открытии',
        () async {
          await open();
          expect(
            find.byKey(Key('schedule-plan-end-history-$id')),
            findsOneWidget,
          );
          expect(find.textContaining('AUDIT-END'), findsOneWidget);
        },
      );
      await h.check(
        'ARCHIVE-CANCEL',
        'Архив требует причину; закрытие preview ничего не меняет',
        () async {
          await key('schedule-plan-archive-$id');
          await h.quiet();
          await key('schedule-archive-confirm');
          expect(find.text('Укажите причину архивирования'), findsOneWidget);
          await h.tap(find.byTooltip('Закрыть').last);
          expect((await read()).isArchived, false);
        },
      );
      await h.check('ARCHIVE', 'Архивировать завершённое расписание', () async {
        await key('schedule-plan-archive-$id');
        await h.quiet();
        await tester.enterText(
          find.byKey(const Key('schedule-archive-reason')),
          'AUDIT-ARCHIVE',
        );
        await key('schedule-archive-confirm');
        await h.quiet();
        expect((await read()).isArchived, true);
        archived = true;
      });
      if (!archived) {
        for (final s in ['ARCHIVE-REOPEN', 'RESTORE', 'FINAL']) {
          h.blocked(s, s, 'Архивирование не подтверждено');
        }
        await h.finish();
        return;
      }
      await h.check(
        'ARCHIVE-REOPEN',
        'Открыть архив и причину архивирования',
        () async {
          await open(archived: true);
          expect(find.textContaining('AUDIT-ARCHIVE'), findsOneWidget);
          expect(find.byKey(Key('schedule-plan-restore-$id')), findsOneWidget);
        },
      );
      await h.check(
        'RESTORE',
        'Восстановить видимость без возобновления занятий',
        () async {
          await key('schedule-plan-restore-$id');
          await h.quiet();
          await key('schedule-restore-confirm');
          expect(find.text('Укажите причину восстановления'), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('schedule-restore-reason')),
            'AUDIT-RESTORE',
          );
          await key('schedule-restore-confirm');
          await h.quiet();
          final p = await read();
          expect(p.isArchived, false);
          expect(p.status, 'ended');
        },
      );
      await h.check(
        'FINAL',
        'Повторно открыть восстановленное завершённое расписание',
        () async {
          await open();
          expect((await read()).status, 'ended');
          expect(
            find.byKey(Key('schedule-plan-end-history-$id')),
            findsOneWidget,
          );
          expect(find.byKey(Key('schedule-plan-archive-$id')), findsOneWidget);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
