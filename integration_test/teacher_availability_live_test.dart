import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_cards.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Teacher assignments and availability persist independently',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'teacher-availability');
      await h.initialize(size: const Size(1440, 1800));
      final crm = h.scope.read(magicCrmServiceProvider);
      final teacherId = h.fixture['teacherId'] as String;
      final otherTeacherId = h.fixture['otherTeacherId'] as String;
      final branchId = h.fixture['branchId'] as String;
      final extraBranchId = h.fixture['extraBranchId'] as String;
      final assignments = find.byType(TeacherAssignmentsCard);
      final availability = find.byType(TeacherAvailabilityCard);
      Finder picker() => find.byWidgetPredicate(
        (w) => w is SearchablePickerField && w.label == 'Преподаватель',
      );
      Future<void> selectTeacher(String id) async {
        final widget = tester.widget<SearchablePickerField>(picker());
        if (widget.selectedId == id) return;
        final label = widget.items.singleWhere((r) => r.id == id).label;
        await h.tap(picker());
        await h.tap(find.widgetWithText(MenuItemButton, label));
        await h.quiet();
      }

      Future<void> open() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'schedule'),
        );
        await h.quiet();
        await h.tap(find.text('Графики преподавателей').last);
        await h.quiet();
        await h.waitFor(
          () =>
              picker().evaluate().isNotEmpty &&
              assignments.evaluate().isNotEmpty,
          'Teacher settings loaded',
        );
        await selectTeacher(teacherId);
        await h.quiet();
      }

      Future<Map<String, dynamic>> read([String? id]) async {
        final data = await crm.getScheduleReference(
          branchId: branchId,
          teacherId: id ?? teacherId,
        );
        final teacher = Map<String, dynamic>.from(data['teacher'] as Map);
        h.facts.add({'step': h.currentStep, 'teacher': teacher});
        return teacher;
      }

      Finder save(Finder card) => find.descendant(
        of: card,
        matching: find.widgetWithText(FilledButton, 'Сохранить'),
      );
      Future<void> persist(Finder card) async {
        await h.tap(save(card));
        await h.quiet();
      }

      Finder assignment(String name) => find.descendant(
        of: assignments,
        matching: find.widgetWithText(CheckboxListTile, name),
      );
      Finder day(int weekday) =>
          find.byKey(ValueKey('teacher-availability-day-$weekday'));
      Finder workingIntervals(int weekday) => find.descendant(
        of: day(weekday),
        matching: find.byTooltip('Удалить рабочий интервал'),
      );
      Future<void> removeSunday() async => h.tap(workingIntervals(7).first);
      Future<void> addSunday() async =>
          h.tap(find.byKey(const Key('teacher-availability-add-7')));
      Future<void> datePicker(bool cancel) async {
        await h.tap(
          find.descendant(
            of: availability,
            matching: find.widgetWithText(TextButton, 'Добавить'),
          ),
        );
        final dialog = find.byType(DatePickerDialog);
        await h.waitFor(
          () => dialog.evaluate().isNotEmpty,
          'Date picker opened',
        );
        final local = MaterialLocalizations.of(tester.element(dialog));
        await h.tap(
          find.descendant(
            of: dialog,
            matching: find.text(
              cancel ? local.cancelButtonLabel : local.okButtonLabel,
            ),
          ),
        );
      }

      Future<void> acceptTime() async {
        final dialog = find.byType(TimePickerDialog);
        await h.waitFor(
          () => dialog.evaluate().isNotEmpty,
          'Time picker opened',
        );
        final local = MaterialLocalizations.of(tester.element(dialog));
        await h.tap(
          find.descendant(of: dialog, matching: find.text(local.okButtonLabel)),
        );
      }

      await h.check(
        'OPEN',
        'График выбранного преподавателя загружен с назначением и семью днями',
        () async {
          await open();
          expect(
            tester.widget<CheckboxListTile>(assignment('HTTP test')).value,
            true,
          );
          expect((await read())['availability'], hasLength(7));
        },
      );
      await h.check(
        'ASSIGN-EMPTY',
        'Редактор не отправляет пустой список назначений',
        () async {
          await h.tap(assignment('HTTP test'));
          expect(
            tester.widget<FilledButton>(save(assignments)).onPressed,
            isNull,
          );
          expect((await read())['assignments'], hasLength(1));
          await open();
        },
      );
      await h.check(
        'ASSIGN-ADD',
        'Добавить второй филиал и проверить после повторного открытия',
        () async {
          await h.tap(assignment('ZZ-TEACHER-BRANCH'));
          await persist(assignments);
          expect(
            ((await read())['assignments'] as List).any(
              (r) => r['branchId'] == extraBranchId,
            ),
            true,
          );
          await open();
          expect(
            tester
                .widget<CheckboxListTile>(assignment('ZZ-TEACHER-BRANCH'))
                .value,
            true,
          );
        },
      );
      await h.check(
        'ASSIGN-REMOVE',
        'Убрать второе назначение, сохранив исходный филиал',
        () async {
          await h.tap(assignment('ZZ-TEACHER-BRANCH'));
          await persist(assignments);
          final list = (await read())['assignments'] as List;
          expect(list, hasLength(1));
          expect(list.single['branchId'], branchId);
        },
      );
      await h.check(
        'AVAILABILITY-SAVE',
        'Изменить рабочий день после сохранения назначений без конфликта собственной версии',
        () async {
          await removeSunday();
          await persist(availability);
          expect(
            ((await read())['availability'] as List).where(
              (r) => r['kind'] == 'recurring',
            ),
            hasLength(6),
          );
          await open();
          expect(workingIntervals(7), findsNothing);
        },
      );
      await h.check(
        'INTERVAL-CANCEL',
        'Отмена выбора даты не создаёт период недоступности',
        () async {
          await datePicker(true);
          await h.quiet();
          expect(
            ((await read())['availability'] as List).where(
              (r) => r['kind'] == 'interval',
            ),
            isEmpty,
          );
        },
      );
      await h.check(
        'INTERVAL-SAVE',
        'Добавить период недоступности 09–18 с обязательной причиной и сохранить',
        () async {
          await datePicker(false);
          await acceptTime();
          await acceptTime();
          final dialog = find.ancestor(
            of: find.text('Причина недоступности'),
            matching: find.byType(AlertDialog),
          );
          final add = find.descendant(
            of: dialog,
            matching: find.widgetWithText(FilledButton, 'Добавить'),
          );
          expect(tester.widget<FilledButton>(add).onPressed, isNull);
          final field = find.descendant(
            of: dialog,
            matching: find.byType(TextField),
          );
          await h.tap(field);
          await tester.enterText(field, 'TEACHER-AUDIT');
          await tester.pump();
          await h.tap(add);
          await persist(availability);
          final intervals = ((await read())['availability'] as List)
              .where((r) => r['kind'] == 'interval')
              .toList();
          expect(intervals, hasLength(1));
          expect(intervals.single['reason'], 'TEACHER-AUDIT');
          expect(intervals.single['available'], false);
          await open();
          expect(find.text('TEACHER-AUDIT'), findsOneWidget);
        },
      );
      await h.check(
        'INTERVAL-REMOVE',
        'Удалить период недоступности и перечитать',
        () async {
          await h.tap(find.byTooltip('Удалить период'));
          await persist(availability);
          expect(
            ((await read())['availability'] as List).where(
              (r) => r['kind'] == 'interval',
            ),
            isEmpty,
          );
        },
      );
      await h.check(
        'OTHER-TEACHER',
        'Смена преподавателя не переносит изменения в чужой график',
        () async {
          await selectTeacher(otherTeacherId);
          expect(workingIntervals(7), findsOneWidget);
          expect((await read(otherTeacherId))['availability'], hasLength(7));
          await selectTeacher(teacherId);
          expect(workingIntervals(7), findsNothing);
        },
      );
      await h.check(
        'STALE',
        'Старая версия доступности не перезаписывает конкурентное сохранение',
        () async {
          await addSunday();
          final before = await read();
          final rules = (before['availability'] as List)
              .map(
                (r) =>
                    Map<String, dynamic>.from(r as Map)
                      ..removeWhere((key, value) => value == null),
              )
              .toList();
          rules.singleWhere(
            (r) => r['kind'] == 'recurring' && r['weekday'] == 1,
          )['localStart'] = '09:00';
          await crm.replaceTeacherAvailability(
            teacherId: teacherId,
            expectedVersion: before['version'] as int,
            rules: rules,
          );
          await persist(availability);
          final stored = (await read())['availability'] as List;
          expect(stored.where((r) => r['kind'] == 'recurring'), hasLength(6));
          expect(
            stored.singleWhere((r) => r['weekday'] == 1)['localStart'],
            '09:00',
          );
          expect(workingIntervals(7), findsOneWidget);
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
            path:
                '/api/crm/schedule-reference/teachers/$teacherId/availability',
            status: 409,
            maxCount: 1,
          ),
        ],
      );
      await h.check(
        'REOPEN-SERVER',
        'Повторное открытие показывает серверные дни и время',
        () async {
          await open();
          expect(workingIntervals(7), findsNothing);
          expect(
            find.descendant(of: day(1), matching: find.text('09:00')),
            findsOneWidget,
          );
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 9)),
  );
}
