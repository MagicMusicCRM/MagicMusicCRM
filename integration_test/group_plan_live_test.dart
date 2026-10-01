import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_group_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_client_funding_fields.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_detail_dialog.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_editor.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/group_schedule_participants_editor.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'director group plan creation and dated membership',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'group-plan');
      await h.initialize(size: const Size(1600, 1500));
      final crm = h.scope.read(magicCrmServiceProvider),
          group = h.fixture['groupId'] as String;
      final students = (h.fixture['students'] as List).cast<String>();
      const title = 'AUDIT-GROUP-PLAN';
      Finder key(String k) => find.byKey(ValueKey(k));
      Future<void> click(String k) => h.tap(key(k));
      Future<List<SchedulePlan>> plans() =>
          crm.listSchedulePlans(groupId: group, includeArchived: true);
      Future<SchedulePlan> current() async {
        final p = (await plans()).singleWhere((p) => p.title == title);
        h.facts.add({
          'step': h.currentStep,
          'planId': p.id,
          'version': p.version,
          'participants': p.currentParticipants
              .map(
                (v) => {
                  'studentId': v.studentId,
                  'subscriptionId': v.subscriptionId,
                },
              )
              .toList(),
        });
        return p;
      }

      Future<void> open({String? groupId}) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final row = await crm.getGroup(groupId ?? group);
        await h.mount(
          Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () =>
                    GroupDetailDialog.show(context, row, canWrite: true),
                child: const Text('Открыть группу'),
              ),
            ),
          ),
        );
        await h.tap(find.text('Открыть группу'));
        await h.quiet();
      }

      Future<void> fill(String k, String value) async {
        await h.tap(key(k));
        await tester.enterText(key(k), value);
        await h.quiet();
      }

      Future<void> weekdays(Set<int> wanted) async {
        for (var day = 1; day <= 7; day++) {
          final f = key('preferred-schedule-weekday-$day');
          if (tester.widget<FilterChip>(f).selected != wanted.contains(day)) {
            await h.tap(f);
          }
        }
      }

      Future<void> select(String k, String label) async {
        await click(k);
        final option = find.text(label);
        await h.waitFor(
          () => option.evaluate().isNotEmpty,
          'Picker option loaded: $label',
        );
        await h.tap(option.last);
        await h.quiet();
      }

      Future<void> date(String k, DateTime d) async {
        await click(k);
        final dialog = find.byType(DatePickerDialog);
        final loc = MaterialLocalizations.of(tester.element(dialog));
        await h.tap(find.byTooltip(loc.inputDateModeButtonLabel));
        final input = find.descendant(
          of: dialog,
          matching: find.byType(TextFormField),
        );
        await h.tap(input);
        await tester.enterText(input, loc.formatCompactDate(d));
        await h.tap(find.text(loc.okButtonLabel));
        await h.quiet();
        expect(dialog, findsNothing);
      }

      Future<void> member(String id) => h.tap(
        find.descendant(
          of: key('group-plan-member-$id'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      await h.check(
        'GROUP-DEFAULTS',
        'Создать группу с типами расчёта вместо числовой цены и ставки',
        () async {
          await h.mount(
            Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showCreateGroupSurface(context),
                  child: const Text('Новая группа'),
                ),
              ),
            ),
          );
          await h.tap(find.text('Новая группа'));
          await h.quiet();
          final name = find.byType(TextFormField).first;
          await tester.enterText(name, 'AUDIT-GROUP-DEFAULTS-UI');
          await select('group-branch-null', 'HTTP test');
          await select('group-teacher-field', 'Teacher1 HTTP test');
          await select('group-room-field', 'Room 1');
          expect(find.text('Цена за занятие'), findsNothing);
          expect(find.text('Ставка педагога по группе'), findsNothing);
          expect(key('group-settlement-lesson'), findsOneWidget);
          final catalog = await crm.getLessonDecisionCatalog(
            branchId: h.fixture['branchId'],
          );
          final noneLabel = (catalog['teacherCompensationRules'] as List)
              .cast<Map>()
              .singleWhere((item) => item['stableKey'] == 'none')['label']
              .toString();
          await select('group-compensation-standard', noneLabel);
          await h.tap(find.widgetWithText(FilledButton, 'Создать группу'));
          await h.quiet();
          expect(find.byType(CreateGroupDialog), findsNothing);
          final saved = (await crm.listGroups(
            limit: 100,
          )).singleWhere((item) => item['name'] == 'AUDIT-GROUP-DEFAULTS-UI');
          expect(saved['teacher_id'], h.fixture['teacherId']);
          expect(saved['settlement_type_key'], 'lesson');
          expect(saved['teacher_compensation_rule_key'], 'none');
          expect(saved['price_per_lesson'], isNull);
          expect(saved['teacher_rate'], isNull);
        },
      );
      await h.check(
        'LEGACY-CANCEL',
        'Оба действия старой группы открывают настройки; отмена ничего не создаёт',
        () async {
          await open();
          for (final action in ['group-single-lesson', 'schedule-plan-add']) {
            await click(action);
            await h.quiet();
            expect(find.byType(CreateGroupDialog), findsOneWidget);
            await h.tap(find.widgetWithText(OutlinedButton, 'Отмена').last);
            await h.quiet();
            await h.tap(find.text('Не сохранять'));
            await h.quiet();
            expect(find.byType(CreateGroupDialog), findsNothing);
            expect((await crm.getGroup(group))['settlement_type_key'], isNull);
            expect(await plans(), isEmpty);
            expect(await crm.listLessons(groupId: group), isEmpty);
          }
        },
      );
      await h.check(
        'BRANCH-REFRESH',
        'После настройки старой группы редактор использует её новый филиал и каталог',
        () async {
          final row = await crm.createGroup(
            name: 'AUDIT-GROUP-BRANCH-REFRESH',
            teacherId: h.fixture['teacherId'],
            branchId: h.fixture['branchId'],
            roomId: h.fixture['roomId'],
            pricePerLesson: 1000,
          );
          await crm.addGroupStudent(
            groupId: row['id'],
            studentId: students.first,
          );
          await open(groupId: row['id']);
          await click('schedule-plan-add');
          await h.quiet();
          await select(
            'group-branch-${h.fixture['branchId']}',
            'GROUP-SECOND-BRANCH',
          );
          await select('group-teacher-field', 'Teacher1 HTTP test');
          await select('group-room-field', 'GROUP-SECOND-ROOM');
          await h.tap(find.widgetWithText(FilledButton, 'Сохранить'));
          await h.quiet();
          await click('group-plan-participants-submit');
          await h.quiet();
          final editor = tester.widget<PreferredScheduleEditor>(
            find.byType(PreferredScheduleEditor),
          );
          expect(
            editor.branches.map((b) => b['id']),
            contains(h.fixture['secondBranchId']),
          );
          expect(
            editor.decisionCatalogs,
            contains(h.fixture['secondBranchId']),
          );
          expect(editor.initialDraft!.branchId, h.fixture['secondBranchId']);
          expect(await crm.listLessons(groupId: row['id']), isEmpty);
          expect(await crm.listSchedulePlans(groupId: row['id']), isEmpty);
          await h.tap(find.text('Отмена').last);
          await h.quiet();
          if (find.text('Не сохранять').evaluate().isNotEmpty) {
            await h.tap(find.text('Не сохранять'));
            await h.quiet();
          }
          await click('group-edit-defaults');
          await h.quiet();
          expect(
            key('group-branch-${h.fixture['secondBranchId']}'),
            findsOneWidget,
          );
          expect(key('group-settlement-lesson'), findsOneWidget);
          expect(key('group-compensation-standard'), findsOneWidget);
        },
      );
      await h.check(
        'OPEN',
        'Сохранить типы старой группы и продолжить создание расписания',
        () async {
          await open();
          await click('schedule-plan-add');
          await h.quiet();
          expect(find.byType(CreateGroupDialog), findsOneWidget);
          expect(key('group-settlement-lesson'), findsOneWidget);
          expect(key('group-compensation-standard'), findsOneWidget);
          await h.tap(find.widgetWithText(FilledButton, 'Сохранить'));
          await h.quiet();
          final updated = await crm.getGroup(group);
          expect(updated['settlement_type_key'], 'lesson');
          expect(updated['teacher_compensation_rule_key'], 'standard');
          expect(find.byType(GroupScheduleParticipantsEditor), findsOneWidget);
          expect(find.byType(CheckboxListTile), findsNWidgets(2));
        },
      );
      await h.check('EMPTY', 'Запретить сохранение без участников', () async {
        for (final id in students) {
          await member(id);
        }
        await click('group-plan-participants-submit');
        expect(key('group-plan-participants-error'), findsOneWidget);
        expect(await plans(), isEmpty);
      });
      await h.check(
        'DRAFT',
        'Выбрать двух участников с абонементами и заполнить план',
        () async {
          for (final id in students) {
            await member(id);
          }
          await click('group-plan-participants-submit');
          await h.quiet();
          expect(find.byType(PreferredScheduleEditor), findsOneWidget);
          expect(
            tester
                .widget<SearchablePickerField>(
                  key('preferred-schedule-teacher'),
                )
                .selectedId,
            h.fixture['teacherId'],
          );
          expect(
            tester
                .widget<SearchablePickerField>(key('preferred-schedule-room'))
                .selectedId,
            h.fixture['roomId'],
          );
          expect(key('schedule-plan-settlement-type'), findsNothing);
          expect(key('schedule-plan-compensation-rule'), findsNothing);
          await fill('schedule-plan-title', title);
          await weekdays({1});
          await select('preferred-schedule-room', 'Room 1');
          await click('schedule-plan-open-ended');
          await date('preferred-schedule-start', DateTime(2027, 1, 4));
          await date('preferred-schedule-end', DateTime(2027, 1, 17));
          if ((h.fixture['performanceTeachers'] as num? ?? 0) > 0) {
            for (var sample = 0; sample < 5; sample++) {
              final requestStart = h.requests.length;
              final timer = Stopwatch()..start();
              await click('preferred-schedule-weekday-2');
              await tester.pump(const Duration(milliseconds: 600));
              await h.waitFor(
                () =>
                    find
                        .text('Проверяем доступность педагогов…')
                        .evaluate()
                        .isEmpty &&
                    h.pending.isEmpty,
                'Teacher availability finished',
              );
              timer.stop();
              final requests = h.requests.skip(requestStart).toList();
              if (h.fixture['performancePhase'] == 'after') {
                expect(
                  requests.length,
                  1,
                  reason: 'One batch per availability refresh',
                );
              }
              h.facts.add({
                'kind': 'teacher-availability-performance',
                'phase': h.fixture['performancePhase'],
                'sample': sample,
                'teachers': h.fixture['performanceTeachers'],
                'wallMs': timer.elapsedMicroseconds / 1000,
                'requestCount': requests.length,
                'apiMs': requests.fold<double>(
                  0,
                  (sum, row) =>
                      sum + (row['durationMs'] as num? ?? 0).toDouble(),
                ),
              });
            }
            await weekdays({1});
            await h.quiet();
          }
          await click('preferred-schedule-save');
          await h.quiet();
          expect(key('schedule-plan-row-group-0'), findsOneWidget);
        },
      );
      await h.check(
        'CREATE',
        'Создать групповые занятия с двумя учениками',
        () async {
          await click('schedule-plan-preview-and-create');
          await h.quiet();
          final p = await current();
          expect(p.isGroup, true);
          expect(
            p.currentParticipants.map((v) => v.studentId).toSet(),
            students.toSet(),
          );
          expect(p.currentRows, hasLength(1));
        },
      );
      await h.check(
        'GROUP-TIMELINE',
        'Созданные занятия видны в списке группы',
        () async {
          await open();
          expect(
            find.text('Занятий группы пока нет.'),
            findsNothing,
            reason: 'The group just created a plan with scheduled lessons',
          );
        },
      );
      Future<void> editMembers() async {
        await open();
        final p = await current();
        if (key('schedule-plan-participants-${p.id}').evaluate().isEmpty) {
          await h.tap(find.text(title).first);
          await h.quiet();
        }
        await click('schedule-plan-participants-${p.id}');
        await h.quiet();
        expect(find.byType(GroupScheduleParticipantsEditor), findsOneWidget);
      }

      await h.check(
        'REMOVE',
        'Убрать второго участника только с 11 января',
        () async {
          await editMembers();
          await date('group-plan-effective-from', DateTime(2027, 1, 11));
          await member(students[1]);
          await click('group-plan-participants-submit');
          await h.quiet();
          await click('schedule-plan-preview-and-create');
          await h.quiet();
          await current();
        },
      );
      await h.check(
        'REOPEN',
        'Переоткрыть состав и вернуть второго участника',
        () async {
          await editMembers();
          final tile = tester.widget<CheckboxListTile>(
            find.descendant(
              of: key('group-plan-member-${students[1]}'),
              matching: find.byType(CheckboxListTile),
            ),
          );
          expect(tile.value, false);
          await date('group-plan-effective-from', DateTime(2027, 1, 11));
          await member(students[1]);
          await click('group-plan-participants-submit');
          await h.quiet();
          await click('schedule-plan-preview-and-create');
          await h.quiet();
          await current();
        },
      );
      await h.check(
        'RESTORED',
        'После открытия состав содержит обоих учеников',
        () async {
          await editMembers();
          for (final id in students) {
            expect(
              tester
                  .widget<CheckboxListTile>(
                    find.descendant(
                      of: key('group-plan-member-$id'),
                      matching: find.byType(CheckboxListTile),
                    ),
                  )
                  .value,
              true,
            );
          }
        },
      );
      await h.check(
        'EDIT-DEFAULTS',
        'Изменить тип оплаты в карточке группы без изменения созданных занятий',
        () async {
          await open();
          await click('group-edit-defaults');
          await h.quiet();
          final catalog = await crm.getLessonDecisionCatalog(
            branchId: h.fixture['branchId'],
          );
          final noneLabel = (catalog['teacherCompensationRules'] as List)
              .cast<Map>()
              .singleWhere((item) => item['stableKey'] == 'none')['label']
              .toString();
          await select('group-compensation-standard', noneLabel);
          await h.tap(find.widgetWithText(FilledButton, 'Сохранить'));
          await h.quiet();
          expect(find.byType(CreateGroupDialog), findsNothing);
          expect(
            (await crm.getGroup(group))['teacher_compensation_rule_key'],
            'none',
          );
          final lessons = await crm.listLessons(groupId: group, limit: 100);
          expect(
            lessons.every(
              (row) =>
                  (row['financial_decision']
                      as Map)['teacherCompensationRuleKey'] ==
                  'standard',
            ),
            true,
          );
        },
      );
      await h.check(
        'SINGLE',
        'Создать одиночное занятие всей группе с её преподавателем и типами расчёта',
        () async {
          await open();
          await click('group-single-lesson');
          await h.quiet();
          expect(find.byType(CreateLessonDialog), findsOneWidget);
          expect(
            tester
                .widget<SearchablePickerField>(key('lesson-teacher-field'))
                .selectedId,
            h.fixture['teacherId'],
          );
          expect(find.textContaining('Из настроек группы:'), findsOneWidget);
          expect(key('settlement-type-dropdown'), findsNothing);
          final funding = tester.widget<LessonClientFundingFields>(
            find.byType(LessonClientFundingFields),
          );
          expect(
            funding.participants.map((item) => item.id).toSet(),
            students.toSet(),
          );
          expect(funding.decisions.length, 2);
          await date('lesson-date-field', DateTime(2027, 1, 19));
          await click('lesson-time-field');
          final dialog = find.byType(TimePickerDialog);
          final local = MaterialLocalizations.of(tester.element(dialog));
          await h.tap(find.byTooltip(local.inputTimeModeButtonLabel));
          final fields = find.descendant(
            of: dialog,
            matching: find.byType(TextField),
          );
          await tester.enterText(fields.at(0), '15');
          await tester.enterText(fields.at(1), '00');
          await h.tap(
            find.descendant(
              of: dialog,
              matching: find.text(local.okButtonLabel),
            ),
          );
          await h.quiet();
          expect(
            tester
                .widget<SearchablePickerField>(key('lesson-teacher-field'))
                .selectedId,
            h.fixture['teacherId'],
          );
          await h.tap(
            find.descendant(
              of: find.byType(CreateLessonDialog),
              matching: find.widgetWithText(FilledButton, 'Создать'),
            ),
          );
          await h.quiet();
          expect(find.byType(CreateLessonDialog), findsNothing);
          final created = (await crm.listLessons(groupId: group, limit: 100))
              .singleWhere(
                (row) =>
                    row['scheduled_at'].toString().startsWith('2027-01-19'),
              );
          expect(created['teacher_id'], h.fixture['teacherId']);
          expect(created['room_id'], h.fixture['roomId']);
          final decision = created['financial_decision'] as Map;
          expect(decision['settlementTypeKey'], 'lesson');
          expect(decision['teacherCompensationRuleKey'], 'none');
          expect((decision['clientDecisions'] as List).length, 2);
          h.facts.add({
            'step': h.currentStep,
            'lessonId': created['id'],
            'groupId': group,
            'participantCount': 2,
          });
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
