import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'live_audit_harness.dart';

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
          await h.tap(key('schedule-day-mode-switcher'));
          await h.tap(find.text('По преподавателям').last);
          await h.quiet();
          expect(saved.filters['dayMode'], 'byTeacher');
          await h.tap(key('schedule-day-mode-switcher'));
          await h.tap(find.text('По аудиториям').last);
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
          await h.tap(find.byTooltip('Обозначения и занятость'));
          await h.tap(find.byTooltip('Обозначения и занятость'));
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
          await h.tap(key('magic-modal-close'));
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
