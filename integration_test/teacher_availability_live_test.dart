import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_day_canvas.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_cards.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_settings.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';
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
          Scaffold(
            body: ScheduleReferenceSettings(
              key: UniqueKey(),
              canEdit: true,
              section: ScheduleReferenceSection.teacherSchedule,
              initialTeacherId: teacherId,
            ),
          ),
        );
        await h.quiet();
        await h.waitFor(
          () =>
              picker().evaluate().isNotEmpty &&
              assignments.evaluate().isNotEmpty,
          'Teacher reference editor loaded',
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
        matching: find.widgetWithText(
          FilledButton,
          card == availability ? 'Сохранить график' : 'Сохранить',
        ),
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
      void expectBlockedWeek(ScheduleDayCanvas grid) {
        expect(grid.columns, hasLength(7));
        for (final column in grid.columns) {
          final blocks =
              grid.blockedIntervals
                  .where((row) => row.columnId == column.id)
                  .toList()
                ..sort((a, b) => a.startLocal.compareTo(b.startLocal));
          expect(blocks, isNotEmpty);
          final date = column.date!;
          var end = DateTime(date.year, date.month, date.day, kDayStartHour);
          for (final block in blocks) {
            expect(
              block.startLocal,
              end,
              reason: 'No free gap on ${column.id}',
            );
            end = block.endLocal;
          }
          expect(end, DateTime(date.year, date.month, date.day, kDayEndHour));
          expect(
            blocks.any((row) => row.reason == 'Бессрочная занятость'),
            isTrue,
          );
        }
      }

      Future<void> intervalDialog(bool cancel) async {
        await h.tap(find.byKey(const ValueKey('interval-unavailable-add')));
        final dialog = find.ancestor(
          of: find.text('Занято на дату'),
          matching: find.byType(AlertDialog),
        );
        await h.waitFor(
          () => dialog.evaluate().isNotEmpty,
          'Dated unavailability editor opened',
        );
        if (cancel) {
          await h.tap(
            find.descendant(of: dialog, matching: find.text('Отмена')),
          );
        }
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
        'Отмена добавления не создаёт период недоступности',
        () async {
          await intervalDialog(true);
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
          await intervalDialog(false);
          final dialog = find.ancestor(
            of: find.text('Занято на дату'),
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
      await h.check(
        'MULTI-INTERVAL',
        'Два рабочих интервала в воскресенье сохраняются и перечитываются',
        () async {
          await addSunday();
          await addSunday();
          expect(workingIntervals(7), findsNWidgets(2));
          await persist(availability);
          final stored = (await read())['availability'] as List;
          final sunday = stored.where((row) => row['weekday'] == 7).toList();
          expect(sunday, hasLength(2));
          expect(sunday.map((row) => row['localStart']), ['09:00', '10:00']);
          await open();
          expect(workingIntervals(7), findsNWidgets(2));
        },
      );
      await h.check(
        'INDEFINITE-WEEK',
        'Бессрочная недоступность видна во всей неделе',
        () async {
          final before = await read();
          final rules = (before['availability'] as List)
              .map(
                (row) =>
                    Map<String, dynamic>.from(row as Map)
                      ..removeWhere((key, value) => value == null),
              )
              .toList();
          rules.add({
            'kind': 'interval',
            'available': false,
            'timezone': 'Europe/Moscow',
            'startsAt': DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 14))
                .toIso8601String(),
            'reason': 'Бессрочная занятость',
          });
          await crm.replaceTeacherAvailability(
            teacherId: teacherId,
            expectedVersion: before['version'] as int,
            rules: rules,
          );
          await h.mount(
            ScheduleWidget(
              initialBranchId: branchId,
              fixedTeacherId: teacherId,
              initialViewState: ContextViewState(
                filters: const {'view': 'week', 'dayMode': 'byTeacher'},
              ),
            ),
          );
          await h.quiet();
          final grid = tester.widget<ScheduleDayCanvas>(
            find.byKey(const ValueKey('schedule-teacher-week-view')),
          );
          expectBlockedWeek(grid);
        },
      );
      var failReference = false;
      var previewFailures = 0;
      h.api.rawDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (previewFailures > 0 &&
                options.uri.path.endsWith('/crm/lessons/constraints/preview')) {
              previewFailures--;
              h.trace(options, 503, error: 'injected');
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 503),
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
            if (failReference &&
                options.uri.path.endsWith('/crm/schedule-reference')) {
              h.trace(options, 503, error: 'injected');
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 503),
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
            handler.next(options);
          },
        ),
      );
      await h.check(
        'WEEK-ERROR',
        'Ошибка загрузки графика показывает повтор вместо свободной сетки',
        () async {
          failReference = true;
          await tester.pumpWidget(const SizedBox.shrink());
          await h.mount(
            ScheduleWidget(
              key: UniqueKey(),
              initialBranchId: branchId,
              fixedTeacherId: teacherId,
              initialViewState: ContextViewState(
                filters: const {'view': 'week', 'dayMode': 'byTeacher'},
              ),
            ),
          );
          await h.quiet();
          expect(
            find.text('Не удалось загрузить доступность преподавателя'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('schedule-teacher-week-view')),
            findsNothing,
          );
        },
        expectedHttpErrors: [
          (
            method: 'GET',
            path: '/api/crm/schedule-reference',
            status: 503,
            maxCount: 1,
          ),
        ],
        expectedErrorStates: ['Не удалось загрузить доступность преподавателя'],
      );
      await h.check(
        'WEEK-RETRY',
        'Повтор загружает сохранённую бессрочную занятость',
        () async {
          failReference = false;
          await h.tap(find.text('Повторить'));
          await h.quiet();
          final grid = tester.widget<ScheduleDayCanvas>(
            find.byKey(const ValueKey('schedule-teacher-week-view')),
          );
          expectBlockedWeek(grid);
        },
      );
      await h.check(
        'BUSY-PICKER',
        'Редактор предлагает свободного преподавателя до отправки',
        () async {
          final day = DateTime.now().add(const Duration(days: 1));
          await h.mount(
            CreateLessonDialog(
              initialDate: DateTime(day.year, day.month, day.day, 15),
              initialBranchId: branchId,
              initialRoomId: h.fixture['roomId'] as String,
              clientType: 'student',
              clientId: h.fixture['studentId'] as String,
              clientName: 'Student0 HTTP test',
            ),
          );
          await h.quiet();
          final field = tester.widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-teacher-field')),
          );
          expect(
            field.items.map((item) => item.id),
            isNot(contains(teacherId)),
          );
          expect(field.items.map((item) => item.id), contains(otherTeacherId));
        },
      );
      await h.check(
        'PICKER-ERROR',
        'Ошибка проверки доступности оставляет ввод и показывает повтор',
        () async {
          previewFailures = 1;
          final day = DateTime.now().add(const Duration(days: 2));
          await tester.pumpWidget(const SizedBox.shrink());
          await h.mount(
            CreateLessonDialog(
              key: UniqueKey(),
              initialDate: DateTime(day.year, day.month, day.day, 15),
              initialBranchId: branchId,
              initialRoomId: h.fixture['roomId'] as String,
              clientType: 'student',
              clientId: h.fixture['studentId'] as String,
              clientName: 'Student0 HTTP test',
            ),
          );
          await h.quiet();
          expect(
            find.text('Не удалось проверить доступность преподавателей.'),
            findsOneWidget,
          );
          expect(find.text('Student0 HTTP test'), findsWidgets);
          expect(find.text('15:00'), findsWidgets);
        },
        expectedHttpErrors: [
          (
            method: 'POST',
            path: '/api/crm/lessons/constraints/preview',
            status: 503,
            maxCount: 1,
          ),
        ],
      );
      await h.check(
        'PICKER-RETRY',
        'Повтор загружает только свободного преподавателя без потери времени',
        () async {
          await h.tap(find.text('Повторить проверку'));
          await h.quiet();
          final field = tester.widget<SearchablePickerField>(
            find.byKey(const ValueKey('lesson-teacher-field')),
          );
          expect(field.items.map((item) => item.id), contains(otherTeacherId));
          expect(
            field.items.map((item) => item.id),
            isNot(contains(teacherId)),
          );
          expect(find.text('15:00'), findsWidgets);
        },
      );
      await h.check(
        'LATE-REFERENCE',
        'Ответ старого преподавателя не заменяет график после смены выбора',
        () async {
          final received = Completer<void>();
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          var delay = true;
          h.api.rawDio.interceptors.add(
            InterceptorsWrapper(
              onResponse: (response, handler) async {
                if (delay &&
                    response.requestOptions.uri.path.endsWith(
                      '/crm/schedule-reference',
                    ) &&
                    response.requestOptions.queryParameters['teacherId'] ==
                        teacherId) {
                  delay = false;
                  received.complete();
                  await release.future;
                }
                handler.next(response);
              },
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await h.mount(
            ScheduleWidget(
              initialBranchId: branchId,
              initialViewState: ContextViewState(
                filters: {
                  'view': 'week',
                  'dayMode': 'byTeacher',
                  'teacherId': teacherId,
                },
              ),
            ),
          );
          await h.waitFor(
            () => received.isCompleted,
            'First real reference response delayed',
          );
          final selector = find.byKey(
            ValueKey('schedule-teacher-week-selector-$teacherId'),
          );
          final field = tester.widget<AppDropdownButton<String>>(
            find.descendant(
              of: selector,
              matching: find.byType(AppDropdownButton<String>),
            ),
          );
          final label =
              (field.items!
                          .singleWhere((item) => item.value == otherTeacherId)
                          .child
                      as Text)
                  .data!;
          await h.tap(selector);
          await h.tap(find.text(label).last);
          final gridKey = find.byKey(
            const ValueKey('schedule-teacher-week-view'),
          );
          await h.waitFor(
            () => gridKey.evaluate().isNotEmpty,
            'Second teacher week loaded',
          );
          expect(
            tester
                .widget<ScheduleDayCanvas>(gridKey)
                .blockedIntervals
                .any((row) => row.reason == 'Бессрочная занятость'),
            isFalse,
          );
          release.complete();
          await h.quiet();
          expect(
            find.byKey(
              ValueKey('schedule-teacher-week-selector-$otherTeacherId'),
            ),
            findsOneWidget,
          );
          expect(
            tester
                .widget<ScheduleDayCanvas>(gridKey)
                .blockedIntervals
                .any((row) => row.reason == 'Бессрочная занятость'),
            isFalse,
          );
          h.facts.add({
            'step': h.currentStep,
            'discardedTeacherId': teacherId,
            'selectedTeacherId': otherTeacherId,
          });
        },
      );
      await h.check(
        'PERSONNEL-PATH',
        'Shell → Персонал → карточка преподавателя → график',
        () async {
          tester.view.physicalSize = const Size(1366, 768);
          tester.view.devicePixelRatio = 1.25;
          await h.mount(const StaffWorkspaceScreen());
          await h.tap(find.text('Персонал').first);
          await h.waitFor(
            () => find.byType(PersonnelWorkspace).evaluate().isNotEmpty,
            'Personnel workspace opened',
          );
          await h.waitFor(
            () =>
                find.textContaining('Teacher0 HTTP test').evaluate().isNotEmpty,
            'Teacher directory loaded',
          );
          await h.tap(find.textContaining('Teacher0 HTTP test').first);
          await h.waitFor(
            () => find.byType(TeacherDetailDialog).evaluate().isNotEmpty,
            'Teacher card opened',
          );
          await h.waitFor(
            () => find.byType(TeacherAvailabilityCard).evaluate().isNotEmpty,
            'Availability is editable inside the personnel card',
          );
          await h.quiet();
          expect(find.byType(TeacherAvailabilityCard), findsOneWidget);
        },
      );
      await h.check(
        'STAFF-PATH',
        'Shell → Персонал → карточка сотрудника на стандартном viewport',
        () async {
          await h.mount(const StaffWorkspaceScreen());
          await h.tap(find.text('Персонал').first);
          await h.waitFor(
            () => find.byType(PersonnelWorkspace).evaluate().isNotEmpty,
            'Personnel workspace reopened',
          );
          await h.tap(find.text('Сотрудники').first);
          await h.waitFor(
            () => find.text('HTTP test Audit-admin').evaluate().isNotEmpty,
            'Staff directory loaded',
          );
          await h.tap(find.text('HTTP test Audit-admin').first);
          await h.waitFor(
            () => find.byType(StaffDetailDialog).evaluate().isNotEmpty,
            'Staff card opened',
          );
          expect(
            find.byKey(const Key('personnel-detail-pane')),
            findsOneWidget,
          );
        },
      );
      await h.check(
        'ROOM-WEEK',
        'Обычная неделя по аудиториям сохраняет навигацию',
        () async {
          tester.view.physicalSize = const Size(1920, 1080);
          tester.view.devicePixelRatio = 1;
          await h.mount(
            ScheduleWidget(
              initialBranchId: branchId,
              initialViewState: ContextViewState(
                filters: const {'view': 'week', 'dayMode': 'byRoom'},
              ),
            ),
          );
          await h.quiet();
          expect(
            find.byKey(const ValueKey('schedule-week-view')),
            findsOneWidget,
          );
          await h.tap(find.byTooltip('Следующий неделю'));
          await h.quiet();
          expect(
            find.byKey(const ValueKey('schedule-week-view')),
            findsOneWidget,
          );
        },
      );
      await h.check(
        'CROSS-BRANCH',
        'Занятость в другом филиале исключает преподавателя, смежный слот и собственное занятие доступны',
        () async {
          final before = await read(otherTeacherId);
          final branchAssignments = (before['assignments'] as List)
              .map(
                (row) =>
                    Map<String, dynamic>.from(row as Map)
                      ..removeWhere((key, value) => value == null),
              )
              .toList();
          await crm.replaceTeacherBranches(
            teacherId: otherTeacherId,
            expectedVersion: before['version'] as int,
            assignments: [
              ...branchAssignments,
              {'branchId': extraBranchId, 'activeFrom': '2020-01-01'},
            ],
          );
          final room = await crm.createRoom(
            name: 'CROSS-BRANCH-ROOM',
            branchId: extraBranchId,
          );
          final today = DateTime.now();
          final monday = DateTime(
            today.year,
            today.month,
            today.day + 8 - today.weekday,
            12,
          );
          final student = h.fixture['studentId'] as String;
          final created = await crm.createLessonRaw({
            'clientRef': {'type': 'student', 'id': student},
            'teacherId': otherTeacherId,
            'roomId': room['id'],
            'branchId': extraBranchId,
            'scheduledAt': monday.toUtc().toIso8601String(),
            'durationMinutes': 60,
            'isTrial': true,
            'completionType': 'standard.success',
            'clientChargeType': 'none',
            'clientChargeValue': 0,
            'teacherCompensationType': 'none',
            'teacherCompensationValue': 0,
            'financialDecision': {
              'settlementTypeKey': 'trial_lesson',
              'teacherCompensationRuleKey': 'trial_lesson',
              'clientDecisions': [
                {'clientId': student, 'chargeType': 'none'},
              ],
            },
          });
          Future<void> createAt(DateTime date) async {
            await tester.pumpWidget(const SizedBox.shrink());
            await h.mount(
              CreateLessonDialog(
                initialDate: date,
                initialBranchId: branchId,
                initialRoomId: h.fixture['roomId'] as String,
                clientType: 'student',
                clientId: student,
                clientName: 'Student0 HTTP test',
              ),
            );
            await h.quiet();
          }

          List<String> offered() => tester
              .widget<SearchablePickerField>(
                find.byKey(const ValueKey('lesson-teacher-field')),
              )
              .items
              .map((row) => row.id)
              .toList();
          await createAt(monday);
          expect(offered(), isNot(contains(otherTeacherId)));
          await createAt(monday.add(const Duration(hours: 1)));
          expect(offered(), contains(otherTeacherId));
          final stored = (await crm.listLessons(
            lessonId: created['id'] as String,
            limit: 1,
          )).single;
          await tester.pumpWidget(const SizedBox.shrink());
          await h.mount(CreateLessonDialog(lesson: stored));
          await h.quiet();
          expect(
            offered(),
            contains(otherTeacherId),
            reason: 'Editing excludes this same lesson from overlap checks',
          );
          h.facts.add({
            'step': h.currentStep,
            'lessonId': created['id'],
            'busyBranchId': extraBranchId,
            'testedBranchId': branchId,
            'scheduledAt': monday.toUtc().toIso8601String(),
          });
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 9)),
  );
}
