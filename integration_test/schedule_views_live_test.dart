import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'live_audit_harness.dart';
import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets('$role schedule views and filters', (tester) async {
      final h = LiveAuditHarness(tester, role, 'schedule-views');
      await h.initialize(size: const Size(1600, 1200));
      final lesson = Map<String, dynamic>.from(h.fixture['lesson'] as Map);
      final date = DateTime.parse(lesson['scheduled_at'] as String).toLocal();
      ContextViewState saved = ContextViewState(
        date: date,
        filters: {'view': 'day', 'branchId': h.fixture['branchId']},
      );
      Future<void> mount() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          Scaffold(
            body: ScheduleWidget(
              initialViewState: saved,
              initialBranchId: h.fixture['branchId'] as String,
              onViewStateChanged: (s) => saved = s,
            ),
          ),
        );
        await h.quiet();
      }

      Finder key(String s) => find.byKey(ValueKey(s));
      Future<void> view(String label, String value) async {
        await h.tap(
          find.descendant(
            of: key('schedule-view-switcher'),
            matching: find.text(label),
          ),
        );
        await h.quiet();
        expect(saved.filters['view'], value);
      }

      Future<void> filter(String field, String label) async {
        await h.tap(key('schedule-filter-$field'));
        await h.tap(find.text(label).last);
      }

      Future<void> apply() async {
        await h.tap(key('schedule-filter-apply'));
        await h.quiet();
      }

      if (Platform.environment['SCHEDULE_AUDIT_SEARCH_ONLY'] == 'true') {
        await mount();
        await h.check(
          'SEARCH',
          'Поиск по Enter, число совпадений и очистка',
          () async {
            await tester.enterText(
              key('schedule-search-field'),
              'AUDIT-NO-MATCH',
            );
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await h.quiet();
            expect(saved.filters['scheduleQuery'], 'audit-no-match');
            expect(find.text('Совпадений: 0'), findsOneWidget);
            expect(find.text('Поиск: audit-no-match'), findsOneWidget);
            await h.tap(find.byTooltip('Очистить поиск'));
            await h.quiet();
            expect(saved.filters['scheduleQuery'], isNull);
            expect(find.text('Поиск: audit-no-match'), findsNothing);
            expect(key('schedule-lesson-${lesson['id']}'), findsWidgets);
          },
        );
        await h.finish();
        return;
      }

      await h.check(
        'OPEN',
        'Открыть расписание на дату реального занятия',
        () async {
          await mount();
          expect(key('schedule-lesson-${lesson['id']}'), findsWidgets);
        },
      );
      await h.check('DETAIL', 'Открыть и закрыть карточку занятия', () async {
        await h.tap(key('schedule-lesson-${lesson['id']}').first);
        expect(key('magic-modal-close'), findsOneWidget);
        await h.tap(key('magic-modal-close'));
      });
      await h.check(
        'BRANCH-TOOLBAR',
        'Филиал на экране, компактная дата и выбор в обоих режимах',
        () async {
          final branch = key('schedule-branch-control');
          final branchName =
              (await MagicCrmService(h.api).listBranches()).firstWhere(
                    (row) => row['id'] == h.fixture['branchId'],
                  )['name']
                  as String;
          for (final mode in ['byRoom', 'byTeacher']) {
            await h.tap(key('schedule-workspace-tab-$mode'));
            await h.quiet();
            for (final width in [1600.0, 1200.0, 1000.0, 720.0]) {
              tester.view.physicalSize = Size(width, 1200);
              await tester.pumpAndSettle();
              expect(branch, findsOneWidget);
              final branchRect = tester.getRect(branch);
              final viewRect = tester.getRect(key('schedule-view-switcher'));
              expect(branchRect.right, lessThanOrEqualTo(viewRect.left));
              expect(
                (branchRect.center.dy - viewRect.center.dy).abs(),
                lessThan(24),
              );
              expect(
                tester.getRect(key('schedule-date-label')).left,
                lessThan(100),
              );
              expect(tester.takeException(), isNull);
              expect(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is Tooltip &&
                      (widget.message?.startsWith('Часовой пояс:') ?? false),
                ),
                findsNothing,
              );
              if (width >= (mode == 'byRoom' ? 1200 : 1600)) {
                final searchRect = tester.getRect(key('schedule-search-field'));
                final filterRect = tester.getRect(
                  key('schedule-filter-toggle'),
                );
                final dateRect = tester.getRect(key('schedule-date-label'));
                expect(searchRect.left, greaterThanOrEqualTo(viewRect.right));
                expect(searchRect.right, lessThanOrEqualTo(filterRect.left));
                expect(searchRect.width, lessThanOrEqualTo(260));
                expect(
                  (searchRect.center.dy - viewRect.center.dy).abs(),
                  lessThan(24),
                );
                expect(
                  (dateRect.center.dy - viewRect.center.dy).abs(),
                  lessThan(24),
                );
                await captureEvidence(
                  tester,
                  'compact-toolbar-$role-$mode-${width.toInt()}',
                );
              }
            }
            tester.view.physicalSize = const Size(1600, 1200);
            await tester.pumpAndSettle();
            await h.tap(branch);
            await h.tap(find.text('Все филиалы').last);
            await h.quiet();
            expect(saved.filters['branchScope'], 'all');
            await h.tap(branch);
            await h.tap(find.text(branchName).last);
            await h.quiet();
            expect(saved.filters['branchId'], h.fixture['branchId']);
            await captureEvidence(tester, 'branch-toolbar-$role-$mode');
          }
          await h.tap(key('schedule-workspace-tab-byRoom'));
          await h.quiet();
          await h.tap(key('schedule-filter-toggle'));
          expect(key('schedule-filter-branch'), findsNothing);
          await apply();
          expect(saved.filters['branchId'], h.fixture['branchId']);
        },
      );
      await h.check('DAY-NAV', 'Следующий и предыдущий день', () async {
        final before = saved.date;
        await h.tap(find.byTooltip('Следующий день'));
        await h.quiet();
        expect(saved.date!.difference(before!).inDays, 1);
        await h.tap(find.byTooltip('Предыдущий день'));
        expect(saved.date, before);
      });
      await h.check(
        'GROUPING',
        'Группировка по преподавателям и аудиториям',
        () async {
          await h.tap(key('schedule-workspace-tab-byTeacher'));
          await h.quiet();
          expect(saved.filters['dayMode'], 'byTeacher');
          await h.tap(key('schedule-workspace-tab-byRoom'));
          expect(saved.filters['dayMode'], 'byRoom');
        },
      );
      await h.check(
        'DENSITY',
        'Масштаб дня переключается и возвращается',
        () async {
          final before = saved.filters['fitDayToViewport'];
          await h.tap(key('schedule-density-toggle'));
          expect(saved.filters['fitDayToViewport'], isNot(before));
          await h.tap(key('schedule-density-toggle'));
          expect(saved.filters['fitDayToViewport'], before);
        },
      );
      await h.check(
        'TEACHER-DRAG',
        'Перенос времени выбранного преподавателя и отмена',
        () async {
          final before = saved;
          saved = ContextViewState(
            date: date,
            filters: {
              'view': 'day',
              'dayMode': 'byTeacher',
              'branchId': h.fixture['branchId'],
              'teacherId': lesson['teacher_id'],
              'fitDayToViewport': true,
            },
          );
          await mount();
          final canvas = tester.widget<ScheduleDayCanvas>(
            key('schedule-teacher-day-view'),
          );
          expect(canvas.onProposeMove, isNotNull);
          final card = key('schedule-lesson-${lesson['id']}').first;
          final entry = canvas.entries.singleWhere(
            (entry) => entry.id == lesson['id'],
          );
          final hourHeight =
              tester.getSize(card).height / (entry.durationMinutes / 60);
          await tester.dragFrom(
            tester.getRect(card).center,
            Offset(0, hourHeight),
            kind: PointerDeviceKind.mouse,
          );
          await h.quiet();
          expect(key('lesson-time-field'), findsOneWidget);
          final target = scheduleDayMoveStart(
            entry.startLocal,
            verticalDelta: hourHeight,
            hourHeight: hourHeight,
          );
          expect(
            find.descendant(
              of: key('lesson-time-field'),
              matching: find.text(
                TimeOfDay.fromDateTime(
                  target,
                ).format(tester.element(key('lesson-time-field'))),
              ),
            ),
            findsOneWidget,
          );
          await h.tap(key('magic-modal-close'));
          await h.quiet();
          expect(
            tester
                .widget<ScheduleDayCanvas>(key('schedule-teacher-day-view'))
                .entries
                .singleWhere((entry) => entry.id == lesson['id'])
                .startLocal,
            entry.startLocal,
          );
          saved = before;
          await mount();
        },
      );
      await h.check('WEEK', 'Неделя и соседние недели', () async {
        await view('Неделя', 'week');
        final before = saved.date;
        await h.tap(find.byTooltip('Следующий неделю'));
        await h.quiet();
        expect(saved.date!.difference(before!).inDays, 7);
        await h.tap(find.byTooltip('Предыдущий неделю'));
        expect(saved.date, before);
      });
      await h.check('MONTH', 'Месяц и соседние месяцы', () async {
        await view('Месяц', 'month');
        final before = tester.widget<Text>(key('schedule-date-label')).data;
        await h.tap(find.byTooltip('Следующий месяц'));
        await h.quiet();
        expect(
          tester.widget<Text>(key('schedule-date-label')).data,
          isNot(before),
        );
        await h.tap(find.byTooltip('Предыдущий месяц'));
        expect(tester.widget<Text>(key('schedule-date-label')).data, before);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'schedule-month-lesson-',
                ),
          ),
          findsWidgets,
        );
      });
      await h.check('DAY-RETURN', 'Вернуться к дневному виду', () async {
        await view('День', 'day');
      });
      await h.check(
        'SEARCH',
        'Поиск по Enter, число совпадений и очистка',
        () async {
          await tester.enterText(
            key('schedule-search-field'),
            'AUDIT-NO-MATCH',
          );
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await h.quiet();
          expect(saved.filters['scheduleQuery'], 'audit-no-match');
          expect(find.text('Совпадений: 0'), findsOneWidget);
          expect(find.text('Поиск: audit-no-match'), findsOneWidget);
          await h.tap(find.byTooltip('Очистить поиск'));
          await h.quiet();
          expect(key('schedule-lesson-${lesson['id']}'), findsWidgets);
        },
      );
      await h.check(
        'LEGEND',
        'Открыть и закрыть обозначения занятости',
        () async {
          expect(find.text('Забронировано'), findsNothing);
          await h.tap(find.byTooltip('Обозначения и занятость'));
          expect(find.text('Забронировано'), findsOneWidget);
          await h.tap(find.byTooltip('Обозначения и занятость'));
          expect(find.text('Забронировано'), findsNothing);
          await view('Месяц', 'month');
          expect(find.text('Забронировано'), findsNothing);
          await h.tap(find.byTooltip('Обозначения и занятость'));
          expect(find.text('Забронировано'), findsOneWidget);
          await h.tap(find.byTooltip('Обозначения и занятость'));
          await view('День', 'day');
          tester.view.physicalSize = const Size(390, 1200);
          await tester.pumpAndSettle();
          expect(find.text('Забронировано'), findsNothing);
          await h.tap(find.byTooltip('Обозначения и занятость'));
          expect(find.text('Забронировано'), findsOneWidget);
          await h.tap(find.byTooltip('Обозначения и занятость'));
          expect(tester.takeException(), isNull);
          tester.view.physicalSize = const Size(1600, 1200);
          await tester.pumpAndSettle();
        },
      );
      await h.check(
        'FILTER-CANCEL',
        'Закрытие фильтров без применения сохраняет состояние',
        () async {
          await h.tap(key('schedule-filter-toggle'));
          await filter('lesson-type', 'Только пробные');
          await h.tap(key('schedule-filter-toggle'));
          expect(saved.filters['trial'], isNot(true));
        },
      );
      await h.check('TRIAL', 'Применение фильтра пробных занятий', () async {
        await h.tap(key('schedule-filter-toggle'));
        await filter('lesson-type', 'Только пробные');
        await apply();
        expect(saved.filters['trial'], true);
      });
      await h.check('CONFLICTS', 'Применение фильтра конфликтов', () async {
        await h.tap(key('schedule-filter-toggle'));
        await filter('conflicts', 'Только с конфликтами');
        await apply();
        expect(saved.filters['conflicts'], true);
      });
      await h.check(
        'REOPEN',
        'Повторное открытие восстанавливает переданное состояние фильтров',
        () async {
          await mount();
          expect(saved.filters['trial'], true);
          expect(saved.filters['conflicts'], true);
        },
      );
      await h.check(
        'RESET',
        'Сброс дополнительных фильтров возвращает занятие',
        () async {
          await h.tap(key('schedule-filter-toggle'));
          await h.tap(find.text('Сбросить'));
          await apply();
          expect(saved.filters['trial'], isNot(true));
          expect(saved.filters['conflicts'], isNot(true));
          expect(key('schedule-lesson-${lesson['id']}'), findsWidgets);
        },
      );
      await h.check(
        'CREATE-CANCEL',
        'Открыть и отменить создание занятия из расписания',
        () async {
          await h.tap(key('schedule-create-lesson'));
          final crm = MagicCrmService(h.api);
          final clients = await crm.searchClientRefs(
            type: 'student',
            limit: 50,
          );
          for (final client in [
            clients.first,
            clients.singleWhere(
              (client) =>
                  (client['ref'] as Map)['id'] == h.fixture['activeStudentId'],
            ),
          ]) {
            final id = (client['ref'] as Map)['id'].toString();
            final balance = (await crm.getStudentCommerceProjection(
              id,
            )).student.lessonBalance;
            final branches = await crm.listBranches();
            final branch = branches
                .where((branch) => branch['id'] == client['branchId'])
                .firstOrNull;
            await h.tap(key('lesson-client-field'));
            final textField = find.descendant(
              of: key('lesson-client-field'),
              matching: find.byType(TextField),
            );
            await tester.enterText(textField, client['label'].toString());
            await tester.pump(const Duration(milliseconds: 400));
            await h.quiet();
            final info = key('client-details-student-$id');
            expect(info, findsWidgets);
            final text = tester.widget<Text>(info.first).data!;
            expect(
              text,
              contains(branch?['name']?.toString() ?? 'Филиал не выбран'),
            );
            expect(
              text,
              contains(
                balance.activeSubscriptionCount == 0
                    ? 'Нет абонемента'
                    : 'Есть абонемент · осталось ${NumberFormat('0.##', 'ru').format((balance.total - balance.used).clamp(0, double.infinity))} астр. ч',
              ),
            );
            await h.tap(
              find
                  .widgetWithText(MenuItemButton, client['label'].toString())
                  .last,
            );
            await h.quiet();
            expect(info, findsWidgets);
            await captureEvidence(tester, 'client-picker-$role-$id');
          }
          await h.tap(key('magic-modal-close'));
          if (find
              .widgetWithText(FilledButton, 'Отменить изменения')
              .evaluate()
              .isNotEmpty) {
            await h.tap(
              find.widgetWithText(FilledButton, 'Отменить изменения'),
            );
          }
          await h.quiet();
          expect(key('lesson-client-field'), findsNothing);
        },
      );
      await h.check(
        'REFRESH-TODAY',
        'Обновление и возврат к сегодняшнему дню',
        () async {
          await h.tap(find.byTooltip('Обновить расписание'));
          await h.quiet();
          await h.tap(find.text('Сегодня'));
          final now = DateTime.now();
          expect(saved.date!.year, now.year);
          expect(saved.date!.month, now.month);
          expect(saved.date!.day, now.day);
        },
      );
      h.facts.add({
        'filters': saved.filters,
        'date': saved.date?.toIso8601String(),
      });
      await h.finish();
    });
  }
}
