import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_cards.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Director saves working hours and exceptions through real forms',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'branch-hours');
      await h.initialize(size: const Size(1440, 1400));
      final crm = h.scope.read(magicCrmServiceProvider);
      final id = h.fixture['branchId'] as String;
      Future<Map<String, dynamic>> read() async {
        final data = await crm.getBranchScheduleHours(id);
        h.facts.add({'step': h.currentStep, 'hours': data});
        return data;
      }

      Finder row(String label) => find.byWidgetPredicate(
        (w) => w is ScheduleTimeRow && w.label == label,
      );
      Finder toggle(String label) =>
          find.descendant(of: row(label), matching: find.byType(Switch));
      final card = find.byType(BranchHoursCard);
      Finder save() => find.descendant(
        of: card,
        matching: find.widgetWithText(FilledButton, 'Сохранить'),
      );
      Future<void> open() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'schedule'),
        );
        await h.waitFor(
          () =>
              card.evaluate().isNotEmpty &&
              find.byType(Switch).evaluate().length == 7,
          'Hours loaded',
        );
        await h.quiet();
      }

      Future<void> persist() async {
        await h.tap(save());
        await h.quiet();
      }

      Future<void> exceptionDate({required bool cancel}) async {
        await h.tap(
          find.descendant(
            of: card,
            matching: find.widgetWithText(TextButton, 'Добавить'),
          ),
        );
        await h.waitFor(
          () => find.byType(DatePickerDialog).evaluate().isNotEmpty,
          'Date picker opened',
        );
        final local = MaterialLocalizations.of(
          tester.element(find.byType(DatePickerDialog)),
        );
        await h.tap(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text(
              cancel ? local.cancelButtonLabel : local.okButtonLabel,
            ),
          ),
        );
        await h.quiet();
      }

      await h.check(
        'OPEN',
        'Настройки → часы филиала показывают семь сохранённых дней',
        () async {
          await open();
          expect(
            tester
                .widgetList<Switch>(find.byType(Switch))
                .every((w) => w.value),
            true,
          );
          expect((await read())['weekly'], hasLength(7));
        },
      );
      await h.check(
        'WEEKLY-SAVE',
        'Выключение воскресенья сохраняется после повторного открытия',
        () async {
          await h.tap(toggle('Воскресенье'));
          await persist();
          expect(
            ((await read())['weekly'] as List).any((r) => r['weekday'] == 7),
            false,
          );
          await open();
          expect(tester.widget<Switch>(toggle('Воскресенье')).value, false);
        },
      );
      await h.check(
        'ALL-CLOSED',
        'Пустая рабочая неделя не отправляется; кнопка сохранения выключена',
        () async {
          await open();
          final before = h.requests.where((r) => r['method'] == 'PUT').length;
          for (final day in [
            'Понедельник',
            'Вторник',
            'Среда',
            'Четверг',
            'Пятница',
            'Суббота',
          ]) {
            await h.tap(toggle(day));
          }
          expect(tester.widget<FilledButton>(save()).onPressed, isNull);
          expect(h.requests.where((r) => r['method'] == 'PUT').length, before);
          expect((await read())['weekly'], hasLength(6));
        },
      );
      await h.check(
        'TIME-CANCEL',
        'Отмена выбора времени сохраняет интервал',
        () async {
          await open();
          await h.tap(
            find
                .descendant(
                  of: row('Понедельник'),
                  matching: find.byType(TextButton),
                )
                .first,
          );
          final dialog = find.byType(TimePickerDialog);
          final local = MaterialLocalizations.of(tester.element(dialog));
          await h.tap(
            find.descendant(
              of: dialog,
              matching: find.text(local.cancelButtonLabel),
            ),
          );
          expect(
            find.descendant(
              of: row('Понедельник'),
              matching: find.text('08:00'),
            ),
            findsOneWidget,
          );
        },
      );
      await h.check(
        'TIME-SAVE',
        'Сохранить время открытия понедельника 10:30',
        () async {
          await h.tap(
            find
                .descendant(
                  of: row('Понедельник'),
                  matching: find.byType(TextButton),
                )
                .first,
          );
          final dialog = find.byType(TimePickerDialog);
          final local = MaterialLocalizations.of(tester.element(dialog));
          await h.tap(find.byTooltip(local.inputTimeModeButtonLabel));
          final fields = find.descendant(
            of: dialog,
            matching: find.byType(TextField),
          );
          expect(fields, findsNWidgets(2));
          await h.tap(fields.at(0));
          await tester.enterText(fields.at(0), '10');
          await h.tap(fields.at(1));
          await tester.enterText(fields.at(1), '30');
          await h.tap(
            find.descendant(
              of: dialog,
              matching: find.text(local.okButtonLabel),
            ),
          );
          await persist();
          final weekly = (await read())['weekly'] as List;
          expect(weekly.singleWhere((r) => r['weekday'] == 1)['open'], '10:30');
          await open();
          expect(
            find.descendant(
              of: row('Понедельник'),
              matching: find.text('10:30'),
            ),
            findsOneWidget,
          );
        },
      );
      await h.check(
        'EXCEPTION-CANCEL',
        'Отмена календаря не создаёт исключение',
        () async {
          await exceptionDate(cancel: true);
          expect((await read())['exceptions'], isEmpty);
        },
      );
      await h.check(
        'EXCEPTION-SAVE',
        'Создать исключение «Закрыт» на выбранную дату и сохранить',
        () async {
          await exceptionDate(cancel: false);
          await h.tap(find.text('Закрыт'));
          await h.quiet();
          expect(
            (await read())['exceptions'],
            isEmpty,
            reason: 'Draft is not persisted before Save',
          );
          await persist();
          final exceptions = (await read())['exceptions'] as List;
          expect(exceptions, hasLength(1));
          expect(exceptions.single['closed'], true);
          await open();
          expect(find.text('Закрыто'), findsOneWidget);
        },
      );
      await h.check(
        'EXCEPTION-REMOVE',
        'Удалить исключение, сохранить и перечитать',
        () async {
          await h.tap(find.byTooltip('Удалить исключение'));
          await persist();
          expect((await read())['exceptions'], isEmpty);
          await open();
          expect(find.byTooltip('Удалить исключение'), findsNothing);
        },
      );
      await h.check(
        'STALE',
        'Устаревший редактор не перезаписывает новые часы',
        () async {
          await h.tap(toggle('Среда'));
          final current = await read();
          final weekly = (current['weekly'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          weekly.singleWhere((r) => r['weekday'] == 1)['open'] = '11:00';
          await crm.replaceBranchHours(
            branchId: id,
            expectedVersion: current['version'] as int,
            timezone: current['timezone'] as String,
            weekly: weekly,
            exceptions: [],
          );
          await persist();
          final updated = (await read())['weekly'] as List;
          expect(
            updated.singleWhere((r) => r['weekday'] == 1)['open'],
            '11:00',
          );
          expect(updated.any((r) => r['weekday'] == 3), true);
          expect(
            tester.widget<Switch>(toggle('Среда')).value,
            false,
            reason: 'Local draft retained on rejection',
          );
          expect(
            h.requests.any(
              (r) => r['step'] == h.currentStep && r['status'] == 409,
            ),
            true,
          );
        },
        expectedHttpErrors: [
          (
            method: 'PUT',
            path: '/api/crm/schedule-reference/branches/$id/hours',
            status: 409,
            maxCount: 1,
          ),
        ],
      );
      await h.check(
        'REOPEN-SERVER',
        'После повторного открытия показана актуальная версия сервера',
        () async {
          await open();
          expect(tester.widget<Switch>(toggle('Среда')).value, true);
          expect(
            find.descendant(
              of: row('Понедельник'),
              matching: find.text('11:00'),
            ),
            findsOneWidget,
          );
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
