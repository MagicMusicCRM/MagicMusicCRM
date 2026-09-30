import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_view.dart';
import 'live_audit_harness.dart';
import 'evidence_screenshot.dart';

const fills = <String, Color>{
  'lesson': AppColor.settlementLessonFill,
  'trial_lesson': AppColor.settlementTrialFill,
  'partially_paid_lesson': AppColor.settlementPartialFill,
  'free_lesson': AppColor.settlementFreeFill,
  'paid_miss': AppColor.settlementPaidMissFill,
  'unpaid_miss': AppColor.settlementUnpaidFill,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'teacher']) {
    testWidgets(
      '$role live settlement palette and lifecycle',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'lesson-visuals');
        await h.initialize(size: const Size(1600, 1100));
        final crm = h.scope.read(magicCrmServiceProvider);
        final lessons = (h.fixture['lessons'] as List)
            .cast<Map<String, dynamic>>();
        Finder key(String name) => find.byKey(ValueKey(name));
        Future<void> reset(Widget child) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await h.mount(Scaffold(body: child));
          await h.quiet();
        }

        void verify(Map<String, dynamic> row, String surface) {
          final tile = key(
            '${surface == 'month'
                ? 'schedule-month-lesson'
                : surface == 'feed'
                ? 'student-timeline'
                : 'schedule-lesson'}-${row['id']}',
          ).first;
          expect(tile, findsOneWidget);
          final widget = tester.widget(tile);
          final decorations = <Decoration?>[
            if (widget is Container) widget.decoration,
            if (surface == 'feed')
              ...tester
                  .widgetList<Container>(
                    find.descendant(of: tile, matching: find.byType(Container)),
                  )
                  .map((w) => w.decoration),
            if (surface.endsWith('week'))
              ...tester
                  .widgetList<AnimatedContainer>(
                    find.ancestor(
                      of: tile,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .map((w) => w.decoration),
          ];
          final color = decorations
              .whereType<BoxDecoration>()
              .map((box) => box.color)
              .firstWhere(
                (color) => color != null && color != Colors.transparent,
              );
          expect(
            color,
            role == 'teacher'
                ? fills[row['kind'] == 'trial_lesson'
                      ? 'trial_lesson'
                      : 'lesson']
                : fills[row['kind']],
            reason: '${row['kind']} on $surface',
          );
          final completedIcons = find.descendant(
            of: tile,
            matching: find.byIcon(Icons.check_circle_outline_rounded),
          );
          expect(
            completedIcons,
            row['state'] == 'completed' ? findsOneWidget : findsNothing,
          );
          if (row['state'] == 'settlement_pending') {
            expect(
              find.descendant(
                of: tile,
                matching: find.byIcon(Icons.hourglass_top_rounded),
              ),
              findsOneWidget,
            );
          }
          final foreground = AppColor.text.computeLuminance();
          final background = color!.computeLuminance();
          final contrast = (background + .05) / (foreground + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          expect(tester.takeException(), isNull);
          h.facts.add({
            'step': h.currentStep,
            'lessonId': row['id'],
            'surface': surface,
            'kind': row['kind'],
            'state': row['state'],
            'fill': color.toARGB32(),
            'contrast': contrast,
          });
        }

        if (role == 'admin') {
          for (final state in ['completed', 'scheduled']) {
            await h.check(
              'STAFF-WEEK-$state',
              'Цвета в неделе по преподавателю',
              () async {
                final rows = lessons
                    .where((row) => row['state'] == state)
                    .toList();
                await reset(
                  ScheduleWidget(
                    initialBranchId: h.fixture['branchId'],
                    initialViewState: ContextViewState(
                      date: DateTime.parse(rows.first['scheduledAt']).toLocal(),
                      filters: {
                        'view': 'week',
                        'dayMode': 'byTeacher',
                        'teacherId': h.fixture['teacherId'],
                      },
                    ),
                  ),
                );
                for (final row in rows) {
                  verify(row, 'staff-week');
                }
              },
            );
          }
          for (final row in lessons) {
            await h.check(
              'DAY-${row['state']}-${row['kind']}',
              'Тип и статус в дне',
              () async {
                await reset(
                  ScheduleWidget(
                    initialBranchId: h.fixture['branchId'],
                    initialViewState: ContextViewState(
                      date: DateTime.parse(row['scheduledAt']).toLocal(),
                      filters: const {'view': 'day'},
                    ),
                  ),
                );
                verify(row, 'day');
                if (row['state'] == 'settlement_pending') {
                  await h.tap(key('schedule-lesson-${row['id']}').first);
                  await h.quiet();
                  expect(
                    find.textContaining(
                      'На личном счёте недостаточно средств.',
                    ),
                    findsOneWidget,
                  );
                  await h.tap(key('magic-modal-close'));
                }
              },
            );
          }
          final months = <String, List<Map<String, dynamic>>>{};
          for (final row in lessons) {
            final at = DateTime.parse(row['scheduledAt']);
            months.putIfAbsent('${at.year}-${at.month}', () => []).add(row);
          }
          for (final entry in months.entries) {
            await h.check(
              'MONTH-${entry.key}',
              'Все типы в месяце сохраняют заливку и статус',
              () async {
                await reset(
                  ScheduleWidget(
                    initialBranchId: h.fixture['branchId'],
                    initialViewState: ContextViewState(
                      date: DateTime.parse(
                        entry.value.first['scheduledAt'],
                      ).toLocal(),
                      filters: const {'view': 'month'},
                    ),
                  ),
                );
                for (final row in entry.value) {
                  verify(row, 'month');
                }
              },
            );
          }
          for (final studentId
              in lessons.map((row) => row['studentId'] as String).toSet()) {
            await h.check(
              'CLIENT-FEED-$studentId',
              'Лента клиента: будущие и завершённые занятия после повторного чтения',
              () async {
                final studentLessons = lessons
                    .where((row) => row['studentId'] == studentId)
                    .toList();
                await reset(
                  SingleChildScrollView(
                    child: RecurringSchedulePlanSection(
                      studentId: studentId,
                      subjectName: 'Student0 HTTP test',
                      fallbackLessons: const [],
                      branches: await crm.listBranches(),
                      defaultBranchId: h.fixture['branchId'],
                      subscriptions: await crm.listSubscriptions(
                        studentId: studentId,
                      ),
                      canWrite: true,
                      timelineFirst: true,
                      onChanged: () {},
                    ),
                  ),
                );
                StudentLessonTimelineView timeline() =>
                    tester.widget<StudentLessonTimelineView>(
                      find.byType(StudentLessonTimelineView),
                    );
                final seen = <String>{};
                for (var page = 0; page < 8; page++) {
                  for (final row in studentLessons.where(
                    (row) => key(
                      'student-timeline-${row['id']}',
                    ).evaluate().isNotEmpty,
                  )) {
                    verify(row, 'feed');
                    seen.add(row['id']);
                  }
                  await captureEvidence(
                    tester,
                    'lesson-visuals-feed-$studentId-$page',
                  );
                  if (seen.length == studentLessons.length) break;
                  if (page == 0 && timeline().page.hasPrevious) {
                    await h.tap(key('student-lesson-timeline-previous'));
                  } else if (timeline().page.hasNext) {
                    await h.tap(key('student-lesson-timeline-next'));
                  } else {
                    break;
                  }
                  await h.quiet();
                }
                expect(seen, studentLessons.map((row) => row['id']).toSet());
              },
            );
          }
        } else {
          for (final state in ['completed', 'scheduled']) {
            await h.check(
              'TEACHER-WEEK-$state',
              'Преподаватель видит статус и пробность без скрытых финансовых типов',
              () async {
                await reset(const TeacherScheduleWidget());
                await h.tap(
                  find.descendant(
                    of: key('schedule-view-switcher'),
                    matching: find.text('Неделя'),
                  ),
                );
                await h.quiet();
                await h.tap(
                  find.byTooltip(
                    state == 'completed'
                        ? 'Предыдущий неделю'
                        : 'Следующий неделю',
                  ),
                );
                await h.quiet();
                for (final row in lessons.where(
                  (row) =>
                      row['state'] == state ||
                      (state == 'completed' &&
                          row['state'] == 'settlement_pending'),
                )) {
                  final read = (await crm.listLessons(
                    lessonId: row['id'],
                  )).single;
                  expect(read['settlement_type_key'], isNull);
                  expect(read['teacher_compensation_rule_key'], isNull);
                  verify(row, 'teacher-week');
                }
                expect(key('schedule-create-lesson'), findsNothing);
              },
            );
          }
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
