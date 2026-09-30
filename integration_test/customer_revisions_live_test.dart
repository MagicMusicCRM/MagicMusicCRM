import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/lead_lesson_date_tray.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lesson_settlement_report_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  final rawFixture = Platform.environment['HTTP_JOURNEY_FIXTURE'];
  final runFixture = rawFixture == null
      ? const <String, dynamic>{}
      : jsonDecode(rawFixture) as Map<String, dynamic>;
  if (runFixture['trialRestart'] == true) {
    for (final role in ['admin', 'manager', 'director']) {
      if (!(runFixture['trialRecords'] as Map).containsKey(role)) continue;
      testWidgets(
        '$role trial remains cancelled after client process restart',
        (tester) async {
          final h = LiveAuditHarness(tester, role, 'lead-trial-restart');
          await h.initialize(size: const Size(1440, 1100));
          final record = Map<String, dynamic>.from(
            (h.fixture['trialRecords'] as Map)[role] as Map,
          );
          final leadId = record['leadId'] as String;
          final lessonId = record['lessonId'] as String;
          final crm = h.scope.read(magicCrmServiceProvider);
          await h.check(
            'RESTART',
            'Fresh client reads one cancelled trial history',
            () async {
              await h.mount(
                StaffWorkspaceScreen(
                  initialLink: EntityLink.typed(
                    entityType: EntityLinkType.client,
                    entityId: leadId,
                    variant: 'lead',
                  ),
                ),
              );
              await h.quiet();
              expect(find.byType(ClientCard), findsOneWidget);
              expect(find.text('Пробные занятия не назначены'), findsOneWidget);
              final card = await crm.getLeadCard(leadId);
              expect(card['trials'], isEmpty);
              final lessons = await crm.listLessons(
                lessonId: lessonId,
                includeClosed: true,
                limit: 10,
              );
              expect(lessons, hasLength(1));
              expect(lessons.single['status'], 'cancelled');
              final history = await crm.getClientOperationalHistory(
                clientType: 'lead',
                clientId: leadId,
                limit: 20,
              );
              for (final action in [
                'crm.lesson_created',
                'crm.lesson_rescheduled',
                'crm.lesson_cancelled',
              ]) {
                expect(
                  history.items.where((item) => item.actionKey == action),
                  hasLength(
                    role == 'admin' && action == 'crm.lesson_rescheduled'
                        ? 2
                        : 1,
                  ),
                );
              }
              h.facts.add({
                'step': h.currentStep,
                'leadId': leadId,
                'lessonId': lessonId,
                'status': lessons.single['status'],
                'historyCount': history.items.length,
              });
            },
          );
          await h.finish();
        },
      );
    }
    return;
  }
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
            await h.mount(const StaffWorkspaceScreen());
            await h.quiet();
            await h.tap(key('global-people-search-field'));
            await tester.enterText(key('global-people-search-field'), query);
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

  String? leadForDeniedScope;
  for (final (index, role) in ['admin', 'manager', 'director'].indexed) {
    testWidgets(
      '$role lead card creates, edits and cancels a trial lesson',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'lead-trial');
        await h.initialize(size: const Size(1440, 1100));
        final crm = h.scope.read(magicCrmServiceProvider);
        final forms = h.scope.read(clientFormsApiProvider);
        final branch = h.fixture['branchId'] as String;
        final source = (await forms.listSources()).first;
        final pipeline = await crm.getClientPipeline(
          clientType: 'lead',
          branchId: branch,
        );
        final integratedLeadId = role == 'admin'
            ? h.fixture['integratedLeadId'] as String?
            : null;
        final created = integratedLeadId != null
            ? Map<String, dynamic>.from(
                (await crm.getLeadCard(integratedLeadId))['lead'] as Map,
              )
            : await forms.createLead(
                identity: MagicMutationIdentity.create(
                  'audit.fixture.lead-trial',
                ),
                firstName: 'Пробное',
                lastName: 'Занятие',
                phone: '+7999555443$index',
                sourceId: source['id'] as String,
                branchId: branch,
                status: pipeline.activeStages.first.key,
                customFields: [],
              );
        final leadId = created['id'] as String;
        if (role == 'admin') leadForDeniedScope = leadId;
        final initialCardLoad = Completer<void>();
        h.api.rawDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              if (options.method == 'GET' &&
                  options.uri.path == '/api/crm/leads/$leadId/card') {
                await initialCardLoad.future;
              }
              handler.next(options);
            },
          ),
        );
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

        Future<void> selectTime(int hour, int minute) async {
          await h.tap(key('lesson-time-field'));
          final dialog = find.byType(TimePickerDialog);
          final local = MaterialLocalizations.of(tester.element(dialog));
          await h.tap(find.byTooltip(local.inputTimeModeButtonLabel));
          final fields = find.descendant(
            of: dialog,
            matching: find.byType(TextField),
          );
          expect(fields, findsNWidgets(2));
          await tester.enterText(fields.at(0), '$hour');
          await tester.enterText(fields.at(1), '$minute');
          await h.tap(
            find.descendant(
              of: dialog,
              matching: find.text(local.okButtonLabel),
            ),
          );
        }

        await h.check(
          'OPEN',
          'Открыть запись на пробное из карточки лида',
          () async {
            await h.mount(
              StaffWorkspaceScreen(
                initialLink: EntityLink.typed(
                  entityType: EntityLinkType.client,
                  entityId: leadId,
                  variant: 'lead',
                ),
              ),
            );
            try {
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is MagicPageState &&
                      widget.kind == MagicPageStateKind.loading,
                ),
                findsWidgets,
              );
              expect(key('lead-trial-create'), findsNothing);
            } finally {
              initialCardLoad.complete();
            }
            await h.quiet();
            expect(find.byType(ClientCard), findsOneWidget);
            expect(find.text('Пробные занятия не назначены'), findsOneWidget);
            await h.tap(key('lead-trial-create'));
            await h.quiet();
            final editor = tester.widget<CreateLessonDialog>(
              find.byType(CreateLessonDialog),
            );
            expect(editor.leadId, leadId);
            expect(editor.initialIsTrial, true);
            expect(
              find.textContaining(
                integratedLeadId != null ? 'ST02 Входящий' : 'Пробное Занятие',
              ),
              findsWidgets,
            );
          },
        );
        if (role == 'admin') {
          await h.check(
            'REQUIRED',
            'Missing teacher and room keep the trial unsaved',
            () async {
              await h.tap(find.widgetWithText(FilledButton, 'Создать'));
              await h.quiet();
              expect(find.byType(CreateLessonDialog), findsOneWidget);
              expect(
                find.text('Заполните обязательные поля корректно'),
                findsOneWidget,
              );
              expect((await crm.getLeadCard(leadId))['trials'], isEmpty);
              expect(
                h.requests.where(
                  (request) =>
                      request['method'] == 'POST' &&
                      request['path'] == '/api/crm/lessons',
                ),
                isEmpty,
              );
              await h.tap(find.widgetWithText(TextButton, 'Отмена'));
              await h.quiet();
              await h.tap(key('lead-trial-create'));
              await h.quiet();
            },
          );
        }
        await h.check(
          'CREATE',
          'Сохранить пробное и перечитать в карточке и календаре',
          () async {
            await selectFirst('lesson-room-field');
            final tomorrow = DateTime.now().add(const Duration(days: 1));
            await _selectLessonDate(tester, h, tomorrow);
            if (role == 'admin') {
              await selectTime(23, 0);
              await h.quiet();
              final teacher = tester.widget<SearchablePickerField>(
                key('lesson-teacher-field'),
              );
              expect(teacher.items, isEmpty);
              expect(teacher.selectedId, isNull);
              expect((await crm.getLeadCard(leadId))['trials'], isEmpty);
            }
            await selectTime(10, 0);
            await h.quiet();
            await selectFirst('lesson-teacher-field');
            final createRequestsBefore = h.requests.length;
            await h.tap(find.widgetWithText(FilledButton, 'Создать'));
            await h.quiet();
            expect(
              h.requests
                  .skip(createRequestsBefore)
                  .where(
                    (request) =>
                        request['method'] == 'POST' &&
                        request['path'] == '/api/crm/lessons' &&
                        request['status'] == 201,
                  ),
              hasLength(1),
            );
            final card = await crm.getLeadCard(leadId);
            final trials = (card['trials'] as List)
                .cast<Map<String, dynamic>>();
            expect(trials, hasLength(1));
            final lessonId = trials.single['id'] as String;
            trialId = lessonId;
            final calendar = (await crm.listLessons(
              lessonId: lessonId,
              limit: 1,
            )).single;
            expect(calendar['lead_id'], leadId);
            expect(calendar['is_trial'], true);
            expect(calendar['version'], 1);
            expect(calendar['scheduled_at'], trials.single['scheduled_at']);
            expect(
              DateTime.parse(calendar['scheduled_at'] as String).toLocal().hour,
              10,
            );
            h.facts.add({
              'step': h.currentStep,
              'leadId': leadId,
              'lessonId': lessonId,
              'cardTrial': trials.single,
              'calendarLesson': calendar,
            });
            if (role == 'admin') {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await h.mount(
                Scaffold(
                  body: ScheduleWidget(
                    initialBranchId: branch,
                    initialViewState: ContextViewState(
                      date: DateTime.parse(
                        calendar['scheduled_at'] as String,
                      ).toLocal(),
                      filters: {'view': 'day', 'branchId': branch},
                    ),
                  ),
                ),
              );
              await h.quiet();
              expect(key('schedule-lesson-$lessonId'), findsOneWidget);
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await h.mount(
                StaffWorkspaceScreen(
                  initialLink: EntityLink.typed(
                    entityType: EntityLinkType.client,
                    entityId: leadId,
                    variant: 'lead',
                  ),
                ),
              );
              await h.quiet();
              expect(key('lead-trial-edit-$lessonId'), findsOneWidget);
            }
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
          if (role == 'admin') {
            await h.check(
              'OCCUPIED',
              'Занятый преподаватель недоступен до повторной записи',
              () async {
                final existing = (await crm.listLessons(
                  lessonId: trialId,
                  limit: 1,
                )).single;
                await h.tap(key('lead-trial-create'));
                await h.quiet();
                await selectFirst('lesson-room-field');
                final tomorrow = DateTime.now().add(const Duration(days: 1));
                await _selectLessonDate(tester, h, tomorrow);
                await selectTime(10, 0);
                await h.quiet();
                final teacher = tester.widget<SearchablePickerField>(
                  key('lesson-teacher-field'),
                );
                expect(teacher.selectedId, isNull);
                expect(
                  teacher.items.map((item) => item.id),
                  isNot(contains(existing['teacher_id'])),
                );
                expect((await crm.getLeadCard(leadId))['trials'], hasLength(1));
                expect(key('lesson-time-field'), findsOneWidget);
                await h.tap(find.widgetWithText(TextButton, 'Отмена'));
                await h.tap(find.text('Отменить изменения'));
                await h.quiet();
              },
            );
          }
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
              await _selectLessonDate(tester, h, target);
              await selectTime(11, 0);
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
              expect(current['version'], 1);
              expect(current['scheduled_at'], trials.single['scheduled_at']);
              expect(current['scheduled_at'], isNot(old['scheduled_at']));
              expect(
                DateTime.parse(
                  current['scheduled_at'] as String,
                ).toLocal().hour,
                11,
              );
              expect(
                DateUtils.dateOnly(
                  DateTime.parse(current['scheduled_at'] as String).toLocal(),
                ),
                DateUtils.dateOnly(target),
              );
              expect(key('lead-trial-edit-$trialId'), findsOneWidget);
              if (role == 'admin') {
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.pump();
                await h.mount(
                  Scaffold(
                    body: ScheduleWidget(
                      initialBranchId: branch,
                      initialViewState: ContextViewState(
                        date: DateTime.parse(
                          current['scheduled_at'] as String,
                        ).toLocal(),
                        filters: {'view': 'day', 'branchId': branch},
                      ),
                    ),
                  ),
                );
                await h.quiet();
                expect(key('schedule-lesson-$trialId'), findsOneWidget);
                expect(key('schedule-lesson-${old['id']}'), findsNothing);
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await h.mount(
                StaffWorkspaceScreen(
                  initialLink: EntityLink.typed(
                    entityType: EntityLinkType.client,
                    entityId: leadId,
                    variant: 'lead',
                  ),
                ),
              );
              await h.quiet();
              expect(key('lead-trial-edit-$trialId'), findsOneWidget);
              h.facts.add({
                'step': h.currentStep,
                'before': old,
                'current': current,
                'cardTrial': trials.single,
              });
            },
          );
          if (role == 'admin' && trialId != null) {
            await h.check(
              'SECOND-MOVE',
              'Второй перенос оставляет одну актуальную пробную запись',
              () async {
                final first = trialId!;
                await h.tap(key('lead-trial-edit-$first'));
                await h.quiet();
                final target = DateTime.now().add(const Duration(days: 3));
                await _selectLessonDate(tester, h, target);
                await selectTime(12, 0);
                await h.tap(key('lesson-edit-reason'));
                await tester.enterText(
                  key('lesson-edit-reason'),
                  'Повторный перенос пробного занятия',
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
                expect(trialId, isNot(first));
                expect(
                  DateTime.parse(
                    trials.single['scheduled_at'] as String,
                  ).toLocal().hour,
                  12,
                );
                expect(key('lead-trial-edit-$first'), findsNothing);
                expect(key('lead-trial-edit-$trialId'), findsOneWidget);
                final predecessor = (await crm.listLessons(
                  lessonId: first,
                  limit: 1,
                  includeClosed: true,
                )).single;
                expect(predecessor['lifecycle_state'], 'rescheduled');
                h.facts.add({
                  'step': h.currentStep,
                  'first': first,
                  'current': trialId,
                  'predecessor': predecessor,
                });
              },
            );
            await h.check(
              'REOPEN-SECOND-MOVE',
              'Повторно открытая lead-карточка показывает только актуальное пробное',
              () async {
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.pump();
                await h.mount(
                  StaffWorkspaceScreen(
                    initialLink: EntityLink.typed(
                      entityType: EntityLinkType.client,
                      entityId: leadId,
                      variant: 'lead',
                    ),
                  ),
                );
                await h.quiet();
                final trials =
                    ((await crm.getLeadCard(leadId))['trials'] as List)
                        .cast<Map<String, dynamic>>();
                expect(trials, hasLength(1));
                expect(trials.single['id'], trialId);
                expect(key('lead-trial-edit-$trialId'), findsOneWidget);
                final first = h.facts.singleWhere(
                  (fact) => fact['step'] == 'SECOND-MOVE',
                )['first'];
                expect(key('lead-trial-edit-$first'), findsNothing);
              },
            );
          }
          if (integratedLeadId != null && trialId != null) {
            final current = (await crm.getLeadCard(leadId))['trials'] as List;
            expect(current, hasLength(1));
            expect((current.single as Map)['id'], trialId);
            h.facts.add({
              'step': 'INTEGRATED-TRIAL',
              'leadId': leadId,
              'lessonId': trialId,
            });
            await h.finish();
            return;
          }
          if (trialId == null) {
            h.blocked(
              'CANCEL',
              'Отменить пробное из строки карточки',
              'Move was not confirmed',
            );
          } else {
            await h.check(
              'CANCEL',
              'Отменить пробное из строки карточки с сохранением истории',
              () async {
                await h.tap(key('lead-trial-cancel-$trialId'));
                await h.quiet();
                await h.tap(
                  find.widgetWithText(OutlinedButton, 'Закрыть').last,
                );
                await h.quiet();
                expect(key('lead-trial-cancel-$trialId'), findsOneWidget);
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
                expect(trials, isEmpty);
                final cancelled = (await crm.listLessons(
                  lessonId: trialId,
                  limit: 1,
                  includeClosed: true,
                )).single;
                expect(
                  cancelled['lifecycle_state'] ?? cancelled['status'],
                  'cancelled',
                );
                expect(cancelled['version'], 2);
                expect(key('lead-trial-cancel-$trialId'), findsNothing);
                if (role == 'admin') {
                  await tester.pumpWidget(const SizedBox.shrink());
                  await tester.pump();
                  await h.mount(
                    Scaffold(
                      body: ScheduleWidget(
                        initialBranchId: branch,
                        initialViewState: ContextViewState(
                          date: DateTime.parse(
                            cancelled['scheduled_at'] as String,
                          ).toLocal(),
                          filters: {'view': 'day', 'branchId': branch},
                        ),
                      ),
                    ),
                  );
                  await h.quiet();
                  expect(key('schedule-lesson-$trialId'), findsNothing);
                }
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
  testWidgets('client cannot open or change an unrelated lead trial', (
    tester,
  ) async {
    final h = LiveAuditHarness(tester, 'client', 'lead-trial-scope');
    await h.initialize(size: const Size(1440, 1100));
    expect(leadForDeniedScope, isNotNull);
    final leadId = leadForDeniedScope!;
    await h.check(
      'DENIED',
      'Restricted trial section has no create action and lead scope rejects reads',
      () async {
        await h.mount(
          const Scaffold(
            body: LeadTrialLessonsSection(lessons: [], canWrite: false),
          ),
        );
        expect(find.byKey(const Key('lead-trial-create')), findsNothing);
        expect(
          h.requests.where(
            (request) =>
                request['method'] != 'GET' &&
                request['path'].toString().contains('/crm/lessons'),
          ),
          isEmpty,
        );
        Object? denial;
        try {
          await h.scope.read(magicCrmServiceProvider).getLeadCard(leadId);
        } catch (error) {
          denial = error;
        }
        expect(denial, isNotNull);
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        Object? deniedWrite;
        try {
          await h.api.post<Map<String, dynamic>>(
            '/crm/lessons',
            data: {
              'clientRef': {'type': 'lead', 'id': leadId},
              'teacherId': h.fixture['teacherId'],
              'roomId': h.fixture['roomId'],
              'branchId': h.fixture['branchId'],
              'scheduledAt': DateTime(
                tomorrow.year,
                tomorrow.month,
                tomorrow.day,
                10,
              ).toUtc().toIso8601String(),
              'durationMinutes': 60,
              'completionType': 'standard.success',
              'clientChargeType': 'none',
              'clientChargeValue': 0,
              'teacherCompensationType': 'none',
              'teacherCompensationValue': 0,
              'financialDecision': {
                'settlementTypeKey': 'trial_lesson',
                'teacherCompensationRuleKey': 'trial_lesson',
                'clientDecisions': [
                  {'clientId': leadId, 'chargeType': 'none'},
                ],
              },
            },
          );
        } catch (error) {
          deniedWrite = error;
        }
        expect(deniedWrite, isNotNull);
      },
      expectedHttpErrors: [
        (
          method: 'GET',
          path: '/api/crm/leads/$leadId/card',
          status: 403,
          maxCount: 1,
        ),
        (method: 'POST', path: '/api/crm/lessons', status: 403, maxCount: 1),
      ],
    );
    await h.finish();
  });
  testWidgets('manager from another branch cannot open a lead trial', (
    tester,
  ) async {
    final h = LiveAuditHarness(tester, 'manager', 'lead-trial-foreign-scope');
    await h.initialize(
      size: const Size(1440, 1100),
      accountRole: 'foreign-manager',
    );
    final leadId = leadForDeniedScope!;
    expect(h.fixture['foreignBranchId'], isNot(h.fixture['branchId']));
    await h.check(
      'DENIED',
      'Another branch cannot open the lead or start a trial',
      () async {
        await h.mount(
          StaffWorkspaceScreen(
            initialLink: EntityLink.typed(
              entityType: EntityLinkType.client,
              entityId: leadId,
              variant: 'lead',
            ),
          ),
        );
        await h.quiet();
        expect(find.text('Карточка лида недоступна'), findsOneWidget);
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        Object? deniedWrite;
        try {
          await h.api.post<Map<String, dynamic>>(
            '/crm/lessons',
            data: {
              'clientRef': {'type': 'lead', 'id': leadId},
              'teacherId': h.fixture['teacherId'],
              'roomId': h.fixture['roomId'],
              'branchId': h.fixture['branchId'],
              'scheduledAt': DateTime(
                tomorrow.year,
                tomorrow.month,
                tomorrow.day,
                10,
              ).toUtc().toIso8601String(),
              'durationMinutes': 60,
              'completionType': 'standard.success',
              'clientChargeType': 'none',
              'clientChargeValue': 0,
              'teacherCompensationType': 'none',
              'teacherCompensationValue': 0,
              'financialDecision': {
                'settlementTypeKey': 'trial_lesson',
                'teacherCompensationRuleKey': 'trial_lesson',
                'clientDecisions': [
                  {'clientId': leadId, 'chargeType': 'none'},
                ],
              },
            },
          );
        } catch (error) {
          deniedWrite = error;
        }
        expect(deniedWrite, isNotNull);
        expect(find.byKey(const Key('lead-trial-create')), findsNothing);
      },
      expectedErrorStates: ['Карточка лида недоступна'],
      expectedHttpErrors: [
        (
          method: 'GET',
          path: '/api/crm/leads/$leadId/card',
          status: 404,
          maxCount: 1,
        ),
        (method: 'POST', path: '/api/crm/lessons', status: 403, maxCount: 1),
        (method: 'POST', path: '/api/crm/lessons', status: 404, maxCount: 1),
      ],
    );
    await h.finish();
  });
}

Future<void> _selectLessonDate(
  WidgetTester tester,
  LiveAuditHarness h,
  DateTime date,
) async {
  await h.tap(find.byKey(const Key('lesson-date-field')));
  final dialog = find.byType(DatePickerDialog);
  final loc = MaterialLocalizations.of(tester.element(dialog));
  await h.tap(find.byTooltip(loc.inputDateModeButtonLabel));
  final input = find.descendant(
    of: dialog,
    matching: find.byType(TextFormField),
  );
  await h.tap(input);
  await tester.enterText(input, loc.formatCompactDate(date));
  await h.tap(find.text(loc.okButtonLabel).last);
  expect(dialog, findsNothing);
}
