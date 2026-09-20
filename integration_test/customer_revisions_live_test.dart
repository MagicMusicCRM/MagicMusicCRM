import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/workspace/people_search_action.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lesson_settlement_report_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'trial manual pay survives real six-room daily move',
    (tester) async {
      final h = LiveAuditHarness(tester, 'admin', 'customer-revisions');
      final mobile = Platform.isAndroid;
      await h.initialize(size: mobile ? null : const Size(1280, 900));
      h.facts.add({
        'platform': Platform.operatingSystem,
        'logicalWidth':
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
        'logicalHeight':
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
        'devicePixelRatio': tester.view.devicePixelRatio,
      });
      final crm = h.scope.read(magicCrmServiceProvider);
      final id = h.fixture['lessonId'] as String;
      final branch = h.fixture['branchId'] as String;
      var currentId = id;
      Finder key(String value) => find.byKey(ValueKey(value));
      Future<Map<String, dynamic>> read() async =>
          (await crm.listLessons(lessonId: currentId, limit: 1)).single;
      Future<void> open() async {
        final row = await read();
        await h.mount(
          Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => CreateLessonDialog.show(context, lesson: row),
                child: const Text('Открыть'),
              ),
            ),
          ),
        );
        await h.tap(find.text('Открыть'));
        await h.quiet();
      }

      LessonFinancialSectionModel model() => tester
          .widget<LessonFinancialSection>(find.byType(LessonFinancialSection))
          .model;
      Future<void> commit(String reason) async {
        await h.tap(key('lesson-edit-reason'));
        await tester.enterText(key('lesson-edit-reason'), reason);
        await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
        await h.quiet();
        expect(key('lesson-decision-preview'), findsOneWidget);
        await h.tap(find.widgetWithText(FilledButton, 'Подтвердить изменения'));
        await h.quiet();
        expect(find.byType(CreateLessonDialog), findsNothing);
      }

      await h.check(
        'DEFAULT',
        'Пробный: клиент бесплатно, преподавателю ноль',
        () async {
          await open();
          expect(key('lesson-trial-toggle'), findsNothing);
          expect(model().draft.settlementTypeKey, 'trial_lesson');
          expect(model().draft.compensationRuleKey, 'trial_lesson');
          expect(model().draft.clientChargeType, 'none');
        },
      );
      await h.check(
        'MANUAL',
        'Администратор выбирает обычную оплату преподавателю',
        () async {
          await h.tap(key('lesson-compensation-rule-field'));
          await h.tap(find.text('Полная стандартная ставка').last);
          await h.quiet();
          await commit('AUDIT-TRIAL-ADMIN-PAY');
          await open();
          expect(model().draft.compensationRuleKey, 'standard');
          expect(model().draft.settlementTypeKey, 'trial_lesson');
          expect(model().draft.clientChargeType, 'none');
        },
      );
      if (mobile) {
        await h.check(
          'MOBILE-SCHEDULE',
          'Дневное расписание на телефоне: открытие занятия без записи',
          () async {
            final before = await read();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(
              Scaffold(
                body: ScheduleWidget(
                  initialBranchId: branch,
                  initialViewState: ContextViewState(
                    date: DateTime.parse(before['scheduled_at']).toLocal(),
                    filters: {'view': 'day', 'branchId': branch},
                  ),
                ),
              ),
            );
            await h.quiet();
            await h.tap(key('schedule-lesson-$currentId'));
            await h.quiet();
            expect(find.text('Изменить занятие'), findsOneWidget);
            expect((await read())['version'], before['version']);
          },
        );
      } else {
        await h.check(
          'DRAG',
          'Перенос на другую аудиторию и час через реальную сетку',
          () async {
            final before = await read();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(
              Scaffold(
                body: ScheduleWidget(
                  initialBranchId: branch,
                  initialViewState: ContextViewState(
                    date: DateTime.parse(before['scheduled_at']).toLocal(),
                    filters: {'view': 'day', 'branchId': branch},
                  ),
                ),
              ),
            );
            await h.quiet();
            final canvas = tester.widget<ScheduleDayCanvas>(
              find.byType(ScheduleDayCanvas),
            );
            expect(canvas.columns.length, 6);
            final card = key('schedule-lesson-$currentId');
            await tester.ensureVisible(card);
            await h.quiet();
            final rect = tester.getRect(card);
            final original = DateTime.parse(before['scheduled_at']).toLocal();
            await tester.dragFrom(
              rect.center,
              Offset(rect.width + 8, rect.height * 60 / 45),
              kind: PointerDeviceKind.mouse,
            );
            await h.quiet();
            expect(find.byType(CreateLessonDialog), findsOneWidget);
            expect(
              (await read())['version'],
              before['version'],
              reason: 'Drop only proposes; no premature write',
            );
            await commit('AUDIT-TRIAL-DAY-MOVE');
            final rows = await crm.listLessons(
              branchId: branch,
              studentId: h.fixture['studentId'] as String,
              from: '2027-01-12T00:00:00Z',
              to: '2027-01-13T00:00:00Z',
              limit: 100,
            );
            final active = rows
                .where((row) => row['status'] == 'scheduled')
                .single;
            currentId = active['id'] as String;
            final moved = DateTime.parse(active['scheduled_at']).toLocal();
            expect(moved.hour, original.hour + 1);
            expect(moved.minute, 0);
            expect(active['room_id'], isNot(before['room_id']));
            expect(active['duration_minutes'], 45);
            await open();
            expect(model().draft.compensationRuleKey, 'standard');
            expect(model().draft.settlementTypeKey, 'trial_lesson');
          },
        );
      }
      await h.check(
        'FILTER',
        'Отдельное окно отбирает пробные занятия',
        () async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showLessonSettlementReport(
                    context,
                    from: DateTime(2027, 1, 12),
                    to: DateTime(2027, 1, 13),
                    branchId: branch,
                    initialType: 'trial_lesson',
                  ),
                  child: const Text('Открыть списания'),
                ),
              ),
            ),
          );
          await h.tap(find.text('Открыть списания'));
          await h.quiet();
          expect(find.byType(ListTile), findsWidgets);
          expect(find.text('Занятия не найдены'), findsNothing);
        },
      );
      if (mobile) {
        await h.check(
          'TEACHER-FILTER',
          'Фильтр оплаты преподавателю на телефоне',
          () async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(
              Scaffold(
                body: TeacherStatsWidget(
                  branchId: branch,
                  filterRange: DateTimeRange(
                    start: DateTime(2027, 1, 12),
                    end: DateTime(2027, 1, 13),
                  ),
                ),
              ),
            );
            await h.quiet();
            await h.tap(key('compensation-null'));
            await h.tap(find.text('Пробный урок — без оплаты').last);
            await h.quiet();
            expect(key('compensation-trial_lesson'), findsOneWidget);
          },
        );
      }
      for (final query in ['Teacher0', 'Audit-admin']) {
        await h.check(
          'SEARCH-$query',
          'Поиск и открытие действующей карточки $query',
          () async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(const Scaffold(body: PeopleSearchAction()));
            await h.quiet();
            await h.tap(key('global-people-search'));
            await tester.enterText(find.byType(TextField), query);
            await h.quiet();
            await h.tap(find.widgetWithText(ListTile, '$query HTTP test'));
            await h.quiet();
            expect(
              find.byType(
                query == 'Teacher0' ? TeacherDetailDialog : StaffDetailDialog,
              ),
              findsOneWidget,
            );
          },
        );
      }
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
