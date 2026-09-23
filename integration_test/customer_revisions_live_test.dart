import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/workspace/people_search_action.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
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
          await h.tap(key('lesson-compensation-edit-toggle'));
          expect(
            tester
                .widget<CheckboxListTile>(
                  key('lesson-compensation-edit-toggle'),
                )
                .value,
            true,
          );
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

  testWidgets(
    'lead card creates a trial lesson in the calendar',
    (tester) async {
      final h = LiveAuditHarness(tester, 'admin', 'lead-trial');
      await h.initialize(size: const Size(1440, 1100));
      final crm = h.scope.read(magicCrmServiceProvider);
      final forms = h.scope.read(clientFormsApiProvider);
      final access = await h.scope.read(capabilitySnapshotProvider.future);
      final branch = h.fixture['branchId'] as String;
      final source = (await forms.listSources()).first;
      final pipeline = await crm.getClientPipeline(
        clientType: 'lead',
        branchId: branch,
      );
      final created = await forms.createLead(
        identity: MagicMutationIdentity.create('audit.fixture.lead-trial'),
        firstName: 'Пробное',
        lastName: 'Занятие',
        phone: '+79995554434',
        sourceId: source['id'] as String,
        branchId: branch,
        status: pipeline.activeStages.first.key,
        customFields: [],
      );
      final leadId = created['id'] as String;
      String? trialId;
      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> selectFirst(String fieldKey) async {
        final field = key(fieldKey);
        final picker = tester.widget<SearchablePickerField>(field);
        final label = picker.items.first.label;
        await h.tap(field);
        await h.tap(find.widgetWithText(MenuItemButton, label).last);
        await h.quiet();
      }

      await h.check(
        'OPEN',
        'Открыть запись на пробное из карточки лида',
        () async {
          final row = Map<String, dynamic>.from(
            (await crm.getLeadCard(leadId))['lead'] as Map,
          );
          await h.mount(
            Scaffold(
              body: ClientCard(
                lead: row,
                entityType: 'lead',
                routed: true,
                initialSection: 'overview',
                capabilitySnapshot: access,
              ),
            ),
          );
          await h.quiet();
          await h.tap(key('lead-trial-create'));
          await h.quiet();
          final editor = tester.widget<CreateLessonDialog>(
            find.byType(CreateLessonDialog),
          );
          expect(editor.leadId, leadId);
          expect(editor.initialIsTrial, true);
          expect(find.textContaining('Пробное Занятие'), findsWidgets);
        },
      );
      await h.check(
        'CREATE',
        'Сохранить пробное и перечитать в карточке и календаре',
        () async {
          await selectFirst('lesson-teacher-field');
          await selectFirst('lesson-room-field');
          final tomorrow = DateTime.now().add(const Duration(days: 1));
          await h.tap(key('lesson-date-field'));
          await h.tap(
            find
                .descendant(
                  of: find.byType(DatePickerDialog),
                  matching: find.text('${tomorrow.day}'),
                )
                .last,
          );
          await h.tap(find.text('OK').last);
          await h.tap(key('lesson-time-field'));
          final timePicker = find.byType(TimePickerDialog);
          await h.tap(
            find.descendant(
              of: timePicker,
              matching: find.byIcon(Icons.keyboard_outlined),
            ),
          );
          final inputs = find.descendant(
            of: timePicker,
            matching: find.byType(TextField),
          );
          await tester.enterText(inputs.first, '12');
          await tester.enterText(inputs.last, '00');
          await h.tap(
            find.descendant(of: timePicker, matching: find.text('OK')).last,
          );
          await h.tap(find.widgetWithText(FilledButton, 'Создать'));
          await h.quiet();
          final card = await crm.getLeadCard(leadId);
          final trials = (card['trials'] as List).cast<Map<String, dynamic>>();
          expect(trials, hasLength(1));
          final lessonId = trials.single['id'] as String;
          trialId = lessonId;
          final calendar = (await crm.listLessons(
            lessonId: lessonId,
            limit: 1,
          )).single;
          expect(calendar['lead_id'], leadId);
          expect(calendar['is_trial'], true);
          expect(calendar['scheduled_at'], trials.single['scheduled_at']);
          h.facts.add({
            'step': h.currentStep,
            'leadId': leadId,
            'lessonId': lessonId,
            'cardTrial': trials.single,
            'calendarLesson': calendar,
          });
        },
      );
      if (trialId == null) {
        h.blocked(
          'EDIT',
          'Перенести пробное из строки карточки',
          'Trial was not created',
        );
        h.blocked(
          'CANCEL',
          'Отменить пробное из строки карточки',
          'Trial was not created',
        );
      } else {
        await h.check(
          'EDIT',
          'Перенести пробное из строки карточки и сверить текущее время',
          () async {
            final old = (await crm.listLessons(
              lessonId: trialId,
              limit: 1,
            )).single;
            await h.tap(key('lead-trial-edit-$trialId'));
            await h.quiet();
            expect(find.byType(CreateLessonDialog), findsOneWidget);
            final target = DateTime.now().add(const Duration(days: 2));
            await h.tap(key('lesson-date-field'));
            await h.tap(
              find
                  .descendant(
                    of: find.byType(DatePickerDialog),
                    matching: find.text('${target.day}'),
                  )
                  .last,
            );
            await h.tap(find.text('OK').last);
            await h.tap(key('lesson-edit-reason'));
            await tester.enterText(
              key('lesson-edit-reason'),
              'Перенос пробного занятия по просьбе клиента',
            );
            await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
            await h.quiet();
            expect(key('lesson-decision-preview'), findsOneWidget);
            await h.tap(
              find.widgetWithText(FilledButton, 'Подтвердить изменения'),
            );
            await h.quiet();
            final card = await crm.getLeadCard(leadId);
            final trials = (card['trials'] as List)
                .cast<Map<String, dynamic>>();
            expect(trials, hasLength(1));
            trialId = trials.single['id'] as String;
            final current = (await crm.listLessons(
              lessonId: trialId,
              limit: 1,
            )).single;
            expect(current['scheduled_at'], trials.single['scheduled_at']);
            expect(current['scheduled_at'], isNot(old['scheduled_at']));
            expect(
              DateTime.parse(current['scheduled_at'] as String).toLocal().day,
              target.day,
            );
            expect(key('lead-trial-edit-$trialId'), findsOneWidget);
            h.facts.add({
              'step': h.currentStep,
              'before': old,
              'current': current,
              'cardTrial': trials.single,
            });
          },
        );
        if (trialId == null) {
          h.blocked(
            'CANCEL',
            'Отменить пробное из строки карточки',
            'Move was not confirmed',
          );
        } else {
          await h.check(
            'REPEAT-MOVES',
            'Три переноса: в открытой и повторно открытой карточке один текущий урок',
            () async {
              String label(Map<String, dynamic> lesson) =>
                  DateFormat('d MMMM yyyy, HH:mm', 'ru').format(
                    DateTime.parse(lesson['scheduled_at'] as String).toLocal(),
                  );
              final previousLabels = <String>[];
              for (final offset in [3, 4]) {
                final old = (await crm.listLessons(
                  lessonId: trialId,
                  limit: 1,
                )).single;
                previousLabels.add(label(old));
                await h.tap(key('lead-trial-edit-$trialId'));
                await h.quiet();
                final target = DateTime.now().add(Duration(days: offset));
                await h.tap(key('lesson-date-field'));
                await h.tap(
                  find
                      .descendant(
                        of: find.byType(DatePickerDialog),
                        matching: find.text('${target.day}'),
                      )
                      .last,
                );
                await h.tap(find.text('OK').last);
                await h.tap(key('lesson-edit-reason'));
                await tester.enterText(
                  key('lesson-edit-reason'),
                  'Повторный перенос $offset по просьбе клиента',
                );
                await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
                await h.quiet();
                await h.tap(
                  find.widgetWithText(FilledButton, 'Подтвердить изменения'),
                );
                await h.quiet();
                final trials =
                    ((await crm.getLeadCard(leadId))['trials'] as List)
                        .cast<Map<String, dynamic>>();
                expect(trials, hasLength(1));
                trialId = trials.single['id'] as String;
                expect(
                  trials.single['scheduled_at'],
                  isNot(old['scheduled_at']),
                );
                expect(find.text(label(trials.single)), findsOneWidget);
                for (final previous in previousLabels) {
                  expect(find.text(previous), findsNothing);
                }
              }
              final fresh = Map<String, dynamic>.from(
                (await crm.getLeadCard(leadId))['lead'] as Map,
              );
              await h.mount(
                Scaffold(
                  body: ClientCard(
                    key: UniqueKey(),
                    lead: fresh,
                    entityType: 'lead',
                    routed: true,
                    initialSection: 'overview',
                    capabilitySnapshot: access,
                    onClose: (_) {},
                  ),
                ),
              );
              await h.quiet();
              final current =
                  ((await crm.getLeadCard(leadId))['trials'] as List)
                      .cast<Map<String, dynamic>>()
                      .single;
              expect(find.text(label(current)), findsOneWidget);
              for (final previous in previousLabels) {
                expect(find.text(previous), findsNothing);
              }
              final history = await crm.getClientOperationalHistory(
                clientType: 'lead',
                clientId: leadId,
                limit: 20,
              );
              expect(
                history.items.where(
                  (event) => event.actionKey == 'crm.lesson_rescheduled',
                ),
                hasLength(3),
              );
              h.facts.add({
                'step': h.currentStep,
                'leadId': leadId,
                'currentLessonId': trialId,
                'currentAt': current['scheduled_at'],
                'rescheduleEvents': 3,
                'priorVisibleRows': 0,
              });
            },
          );
          await h.check(
            'CANCEL',
            'Отменить пробное из строки карточки с сохранением истории',
            () async {
              await h.tap(key('lead-trial-cancel-$trialId'));
              await h.quiet();
              await h.tap(key('lesson-decision-reason'));
              await tester.enterText(
                key('lesson-decision-reason'),
                'Отмена пробного занятия по просьбе клиента',
              );
              await h.tap(key('lesson-decision-submit'));
              await h.quiet();
              expect(key('lesson-decision-preview'), findsOneWidget);
              await h.tap(key('lesson-decision-submit'));
              await h.quiet();
              final card = await crm.getLeadCard(leadId);
              final trials = (card['trials'] as List)
                  .cast<Map<String, dynamic>>();
              final cancelled = (await crm.listLessons(
                lessonId: trialId,
                limit: 1,
                includeClosed: true,
              )).single;
              expect(
                cancelled['lifecycle_state'] ?? cancelled['status'],
                'cancelled',
              );
              expect(key('lead-trial-cancel-$trialId'), findsNothing);
              final history = await crm.getClientOperationalHistory(
                clientType: 'lead',
                clientId: leadId,
                limit: 20,
              );
              final moved = history.items.where(
                (event) => event.actionKey == 'crm.lesson_rescheduled',
              );
              final cancelledEvents = history.items.where(
                (event) => event.actionKey == 'crm.lesson_cancelled',
              );
              h.facts.add({
                'step': h.currentStep,
                'cardTrials': trials,
                'calendarLesson': cancelled,
                'history': [
                  for (final event in history.items)
                    {
                      'actionKey': event.actionKey,
                      'reason': event.reason,
                      'summary': event.summary,
                      'title': event.title,
                    },
                ],
              });
              expect(
                moved.any(
                  (event) =>
                      event.summary ==
                      'Перенос пробного занятия по просьбе клиента',
                ),
                isTrue,
              );
              expect(
                cancelledEvents.any(
                  (event) =>
                      event.summary ==
                      'Отмена пробного занятия по просьбе клиента',
                ),
                isTrue,
              );
            },
          );
        }
      }
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
