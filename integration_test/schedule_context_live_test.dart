import 'package:dio/dio.dart';
import 'package:magic_music_crm/core/widgets/responsive_detail_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/shared/widgets/audit_event_card.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role schedule boundary and related navigation',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'schedule-context');
        await h.initialize(size: const Size(1700, 1400));
        final id = h.fixture['lessonId'] as String,
            other = h.fixture['otherLessonId'] as String,
            sid = h.fixture['studentId'] as String,
            branch = h.fixture['branchId'] as String;
        final queries = <Map<String, dynamic>>[];
        h.api.rawDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, handler) {
              if (o.method == 'GET')
                queries.add({
                  'path': o.uri.path,
                  'query': Map<String, dynamic>.from(o.queryParameters),
                });
              handler.next(o);
            },
          ),
        );
        Finder key(String k) => find.byKey(ValueKey(k));
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            StaffWorkspaceScreen(
              initialLink: EntityLink.typed(
                entityType: EntityLinkType.report,
                entityId: '__section__',
                variant: 'lesson_list',
                optionalFocus: EntityLinkFocus(
                  focus: 'schedule',
                  filter: {
                    'date': '2027-01-04',
                    'branchId': branch,
                    'view': 'day',
                  },
                ),
              ),
            ),
          );
          await h.quiet();
        }

        List<ScheduleEntry> entries() => tester
            .widgetList<ScheduleDayCanvas>(find.byType(ScheduleDayCanvas))
            .expand((c) => c.entries)
            .toList();
        ScheduleEntry entry(String value) =>
            entries().singleWhere((e) => e.id == value);
        Future<void> filterBranch(String label) async {
          await h.tap(key('schedule-filter-toggle'));
          await h.tap(key('schedule-filter-branch'));
          await h.tap(find.text(label).last);
          await h.tap(key('schedule-filter-apply'));
          await h.quiet();
        }

        Future<void> details() async {
          await h.tap(key('schedule-lesson-$id').first);
          await h.quiet();
          expect(key('magic-modal-close'), findsOneWidget);
        }

        Future<void> reference(EntityLinkType type) async {
          final label = {
            EntityLinkType.client: 'Ученик',
            EntityLinkType.teacher: 'Педагог',
            EntityLinkType.room: 'Аудитория',
            EntityLinkType.branch: 'Филиал',
          }[type]!;
          final row = find.byWidgetPredicate(
            (w) => w is ResponsiveDetailRow && w.label == '$label: ',
          );
          final f = find.descendant(
            of: row,
            matching: find.byType(EntityLinkText),
          );
          await h.tap(f.first);
          await h.quiet();
          expect(key('magic-modal-close'), findsNothing);
        }

        await h.check(
          'MIDNIGHT',
          'Занятие 00:15 следующей даты видно в хвосте предыдущего вечера',
          () async {
            await open();
            final e = entry(id);
            expect(e.startLocal.day, 5);
            expect(e.startLocal.hour, 0);
            expect(e.startLocal.minute, 15);
            expect(e.startMinute, 1455);
            expect(e.durationMinutes, 30);
            h.facts.add({
              'step': h.currentStep,
              'lessonId': id,
              'startLocal': e.startLocal.toIso8601String(),
              'startMinute': e.startMinute,
            });
          },
        );
        await h.check(
          'NEXT-DAY',
          'Полуночное занятие не дублируется на следующий визуальный день',
          () async {
            await h.tap(find.byTooltip('Следующий день'));
            await h.quiet();
            expect(entries().where((e) => e.id == id), isEmpty);
            await h.tap(find.byTooltip('Предыдущий день'));
            await h.quiet();
            expect(entry(id).startMinute, 1455);
          },
        );
        await h.check(
          'WEEK',
          'Неделя использует тот же вечер и сохраняет календарное время',
          () async {
            await h.tap(
              find.descendant(
                of: key('schedule-view-switcher'),
                matching: find.text('Неделя'),
              ),
            );
            await h.quiet();
            expect(entry(id).startLocal.day, 5);
            expect(entry(id).displayDate!.day, 4);
            await h.tap(
              find.descendant(
                of: key('schedule-view-switcher'),
                matching: find.text('День'),
              ),
            );
            await h.quiet();
          },
        );
        await h.check(
          'BRANCH',
          'Выбрать другой филиал и увидеть то же UTC-время как 07:15 следующего дня',
          () async {
            await filterBranch('AUDIT-VLADIVOSTOK');
            expect(
              entries().where((e) => e.id == id || e.id == other),
              isEmpty,
            );
            await h.tap(find.byTooltip('Следующий день'));
            await h.quiet();
            final e = entry(other);
            expect(e.startLocal.day, 5);
            expect(e.startLocal.hour, 7);
            expect(e.startLocal.minute, 15);
            expect(entries().where((e) => e.id == id), isEmpty);
          },
        );
        await h.check(
          'ALL-BRANCHES',
          'Все филиалы сохраняют локальную дату каждого занятия',
          () async {
            await filterBranch('Все филиалы');
            expect(entry(other).startLocal.hour, 7);
            expect(entries().where((e) => e.id == id), isEmpty);
            await h.tap(find.byTooltip('Предыдущий день'));
            await h.quiet();
            expect(entry(id).startMinute, 1455);
            expect(entries().where((e) => e.id == other), isEmpty);
            await filterBranch('HTTP test');
          },
        );
        await h.check(
          'CLIENT-LINK',
          'Из занятия открыть правильную карточку ученика без оставшейся модали',
          () async {
            await details();
            await reference(EntityLinkType.client);
            expect(find.byType(ClientCard), findsOneWidget);
            expect(
              tester.widget<ClientCard>(find.byType(ClientCard)).lead['id'],
              sid,
            );
          },
        );
        await h.check(
          'RETURN',
          'Вернуться в исходную вкладку расписания с прежней датой и филиалом',
          () async {
            await h.tap(find.widgetWithText(TextButton, 'Расписание').first);
            await h.quiet();
            expect(entry(id).startMinute, 1455);
            expect(entries().where((e) => e.id == other), isEmpty);
          },
        );
        for (final type in [
          EntityLinkType.teacher,
          EntityLinkType.room,
          EntityLinkType.branch,
        ]) {
          await h.check(
            'LINK-${type.name.toUpperCase()}',
            'Связанная сущность ${type.name} открывает расписание с точным фильтром',
            () async {
              await open();
              await details();
              await reference(type);
              final w = tester.widget<ScheduleWidget>(
                find.byType(ScheduleWidget),
              );
              final k = '${type.name}Id', expected = h.fixture[k];
              expect(w.initialLink!.entityType, type);
              expect(w.initialLink!.optionalFocus!.filter[k], expected);
              await h.waitFor(
                () => entries().any((e) => e.id == id),
                'Linked schedule lesson loaded',
              );
              expect(entry(id).id, id);
              h.facts.add({
                'step': h.currentStep,
                'link': w.initialLink!.toJson(),
              });
            },
          );
        }
        await h.check(
          'HISTORY',
          'История ученика содержит настоящую запись о созданном занятии и ссылку',
          () async {
            await open();
            await details();
            await reference(EntityLinkType.client);
            await h.tap(key('client-section-jump-history_tasks'));
            await h.quiet();
            final cards = tester.widgetList<AuditEventCard>(
              find.byType(AuditEventCard),
            );
            h.facts.add({
              'step': h.currentStep,
              'events': cards
                  .map(
                    (w) => {
                      'id': w.event.id,
                      'targetId': w.event.target.id,
                      'routeType': w.event.target.routeType,
                      'title': w.event.title,
                      'canOpen': w.onOpenTarget != null,
                    },
                  )
                  .toList(),
            });
            expect(
              cards.where(
                (c) => c.event.target.id == id && c.onOpenTarget != null,
              ),
              isNotEmpty,
            );
          },
        );
        await h.check(
          'HISTORY-LINK',
          'Из записи истории открыть соответствующее занятие в рабочей области',
          () async {
            final card = find
                .byWidgetPredicate(
                  (w) =>
                      w is AuditEventCard &&
                      w.event.target.id == id &&
                      w.onOpenTarget != null,
                )
                .first;
            await h.tap(
              find
                  .descendant(of: card, matching: find.byType(TextButton))
                  .first,
            );
            await h.quiet();
            expect(find.byType(ScheduleWidget), findsOneWidget);
            expect(
              tester
                  .widget<ScheduleWidget>(find.byType(ScheduleWidget))
                  .initialLink!
                  .entityId,
              id,
            );
            expect(entry(id).id, id);
          },
        );
        h.facts.add({'queries': queries});
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 7)),
    );
  }
}
