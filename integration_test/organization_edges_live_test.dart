import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_schedule_section.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_reference_cards.dart';
import 'live_audit_harness.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets(
    'Director real future work blockers and account destination',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'organization-edges');
      await h.initialize(size: const Size(1650, 1700));
      final crm = h.scope.read(magicCrmServiceProvider);
      Finder modal() => find.byWidgetPredicate(
        (w) =>
            w is AlertDialog &&
            w.title is Text &&
            (w.title as Text).data == 'Отключить и архивировать',
      );
      Future<void> workspace() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          StaffWorkspaceScreen(
            initialLink: EntityLink.typed(
              entityType: EntityLinkType.user,
              entityId: '__section__',
              optionalFocus: EntityLinkFocus(focus: 'users'),
            ),
          ),
        );
        await h.quiet();
      }

      for (final type in ['teacher', 'staff']) {
        final id = h.fixture[type + 'Id'] as String;
        Map<String, dynamic>? preview;
        Future<void> open() async {
          await workspace();
          await h.tap(
            find.text(type == 'teacher' ? 'Преподаватели' : 'Сотрудники'),
          );
          await h.quiet();
          await h.tap(find.text(h.fixture[type + 'Name'] as String).last);
          await h.quiet();
          await h.tap(
            find.text(
              type == 'teacher'
                  ? 'Отключить преподавателя'
                  : 'Отключить сотрудника',
            ),
          );
          await h.quiet();
          expect(modal(), findsOneWidget);
        }

        await h.check(
          '$type-BLOCKERS',
          'Карточка показывает реальные блокирующие связи $type',
          () async {
            await open();
            preview = await crm.previewPersonLifecycle(
              personType: type,
              personId: id,
            );
            expect(preview!['canOffboard'], false);
            final blockers = preview!['blockers'] as List,
                codes = blockers.map((b) => b['code']).toSet();
            expect(
              codes,
              containsAll(
                type == 'teacher'
                    ? ['FUTURE_LESSONS', 'ACTIVE_SERIES', 'ACTIVE_GROUPS']
                    : ['OPEN_TASKS', 'ACTIVE_LEADS'],
              ),
            );
            for (final b in blockers) {
              expect(find.textContaining(b['message']), findsOneWidget);
            }
            final commit = tester.widget<FilledButton>(
              find.descendant(of: modal(), matching: find.byType(FilledButton)),
            );
            expect(commit.onPressed, isNull);
            h.facts.add({'step': h.currentStep, 'preview': preview});
          },
        );
        await h.check(
          '$type-BACKEND',
          'Прямой запрос также отвергает отключение занятого сотрудника',
          () async {
            try {
              await crm.changePersonLifecycle(
                personType: type,
                personId: id,
                restore: false,
                expectedVersion: preview!['person']['version'],
                reasonText: 'AUDIT-BLOCKED-OFFBOARD',
              );
              fail('Blocked person was offboarded');
            } on MagicApiException catch (e) {
              expect(e.statusCode, 422);
            }
            expect(
              (await crm.previewPersonLifecycle(
                personType: type,
                personId: id,
              ))['person']['lifecycleState'],
              'active',
            );
          },
          expectedHttpErrors: [
            (
              method: 'POST',
              path:
                  '/api/crm/${type == 'teacher' ? 'teachers' : 'staff'}/$id/offboard',
              status: 422,
              maxCount: 1,
            ),
          ],
        );
        await h.check(
          '$type-CANCEL',
          'Отмена и повторное открытие сохраняют блокировки и доступ',
          () async {
            await h.tap(
              find.descendant(of: modal(), matching: find.text('Отмена')),
            );
            await open();
            expect(
              (await crm.previewPersonLifecycle(
                personType: type,
                personId: id,
              ))['blockers'],
              preview!['blockers'],
            );
            await h.tap(
              find.descendant(of: modal(), matching: find.text('Отмена')),
            );
          },
        );
      }
      await h.check(
        'ACCOUNT-LINK',
        'Найти в пользователях открывает поиск связанного аккаунта в рабочей области',
        () async {
          await workspace();
          await h.tap(find.text('Сотрудники'));
          await h.quiet();
          await h.tap(find.text(h.fixture['staffName'] as String).last);
          await h.quiet();
          await h.tap(find.text('Найти в пользователях'));
          await h.quiet();
          expect(find.byType(UserRolesWidget), findsOneWidget);
          expect(
            tester
                .widget<UserRolesWidget>(find.byType(UserRolesWidget))
                .initialSearch,
            h.fixture['staffEmail'],
          );
          expect(find.text(h.fixture['staffEmail'] as String), findsWidgets);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
  for (final role in ['manager', 'director']) {
    testWidgets(
      '$role cross branch conflicts and changed working hours',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'organization-hours');
        await h.initialize(size: const Size(1650, 1700));
        final crm = h.scope.read(magicCrmServiceProvider),
            sid = h.fixture['studentId'] as String,
            b = h.fixture['secondBranchId'] as String;
        h.api.rawDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, next) {
              if (o.uri.path.endsWith('/lessons/constraints/preview'))
                h.facts.add({'step': h.currentStep, 'payload': o.data});
              next.next(o);
            },
          ),
        );
        Finder key(String k) => find.byKey(ValueKey(k));
        Future<void> editor(int hour) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => CreateLessonDialog.show(
                    context,
                    initialDate: DateTime(2027, 1, 18, hour),
                    initialBranchId: b,
                    initialRoomId: h.fixture['secondRoomId'],
                    clientType: 'student',
                    clientId: sid,
                    clientName: 'Student1 HTTP test',
                  ),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          );
          await h.tap(find.text('Открыть'));
          await h.quiet();
          final branchPicker = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                (w.key as ValueKey?)?.value.toString().startsWith(
                      'lesson-branch-field:',
                    ) ==
                    true,
          );
          await h.tap(branchPicker);
          await h.tap(find.text('AUDIT-HOURS-EAST').last);
          await h.quiet();
          final room = key('lesson-room-field'),
              roomItem = tester
                  .widget<SearchablePickerField>(room)
                  .items
                  .singleWhere((r) => r.id == h.fixture['secondRoomId']);
          await h.tap(room);
          await h.tap(find.widgetWithText(MenuItemButton, roomItem.label));
          await h.quiet();
          final t = key('lesson-teacher-field');
          await h.tap(t);
          await tester.enterText(
            find.descendant(of: t, matching: find.byType(TextField)),
            'Teacher0',
          );
          await h.quiet();
          await h.tap(
            find.widgetWithText(MenuItemButton, 'Teacher0 HTTP test').last,
          );
          await h.quiet();
          await h.tap(key('lesson-client-charge-type-$sid'));
          await h.tap(find.text('С личного счёта').last);
          await h.quiet();
          await h.tap(key('lesson-client-price-$sid'));
          await tester.enterText(key('lesson-client-price-$sid'), '1000');
          await h.tap(key('lesson-run-schedule-analyzer'));
          await h.quiet();
        }

        await h.check(
          'CROSS-BRANCH',
          '20:00 во Владивостоке конфликтует с 13:00 в Москве у того же преподавателя',
          () async {
            await editor(20);
            final a = tester
                .widget<LessonScheduleSection>(
                  find.byType(LessonScheduleSection),
                )
                .model
                .analysis;
            expect(a?.valid, false);
            expect(
              key('conflict-lesson-${h.fixture['lessonId']}'),
              findsWidgets,
            );
            h.facts.add({'step': h.currentStep, 'valid': a?.valid});
          },
        );
        await h.check(
          'FREE-TIME',
          'Другое время проходит проверку обоих часовых поясов',
          () async {
            await editor(18);
            expect(
              tester
                  .widget<LessonScheduleSection>(
                    find.byType(LessonScheduleSection),
                  )
                  .model
                  .analysis
                  ?.valid,
              true,
            );
          },
        );
        await h.check(
          'EAST-13-FREE',
          '13:00 Владивостока не даёт ложный конфликт с 13:00 Москвы',
          () async {
            await editor(13);
            expect(
              tester
                  .widget<LessonScheduleSection>(
                    find.byType(LessonScheduleSection),
                  )
                  .model
                  .analysis
                  ?.valid,
              true,
            );
          },
        );
        await h.check(
          'EAST-11-FREE',
          '11:00 Владивостока остаётся свободным после UTC-конвертации',
          () async {
            await editor(11);
            expect(
              tester
                  .widget<LessonScheduleSection>(
                    find.byType(LessonScheduleSection),
                  )
                  .model
                  .analysis
                  ?.valid,
              true,
            );
          },
        );
        if (role == 'manager') {
          await h.check(
            'HOURS-READONLY',
            'Управляющий видит часы без запрещённой кнопки сохранения',
            () async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await h.mount(SystemSettingsRouteScreen(initialArea: 'schedule'));
              await h.quiet();
              expect(
                tester
                    .widget<BranchHoursCard>(find.byType(BranchHoursCard))
                    .controller
                    .canEdit,
                false,
              );
              expect(
                find.descendant(
                  of: find.byType(BranchHoursCard),
                  matching: find.widgetWithText(FilledButton, 'Сохранить'),
                ),
                findsNothing,
              );
            },
          );
        } else {
          await h.check(
            'HOURS-SAVE',
            'В настройках выключить понедельник выбранного филиала',
            () async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await h.mount(SystemSettingsRouteScreen(initialArea: 'schedule'));
              await h.quiet();
              final picker = find.byWidgetPredicate(
                (w) => w is SearchablePickerField && w.label == 'Филиал',
              );
              final pw = tester.widget<SearchablePickerField>(picker),
                  item = pw.items.singleWhere((i) => i.id == b);
              await h.tap(picker);
              await h.tap(find.widgetWithText(MenuItemButton, item.label));
              await h.quiet();
              final row = find.byWidgetPredicate(
                    (w) => w is ScheduleTimeRow && w.label == 'Понедельник',
                  ),
                  toggle = find.descendant(
                    of: row,
                    matching: find.byType(Switch),
                  );
              expect(tester.widget<Switch>(toggle).value, true);
              await h.tap(toggle);
              await h.tap(
                find.descendant(
                  of: find.byType(BranchHoursCard),
                  matching: find.widgetWithText(FilledButton, 'Сохранить'),
                ),
              );
              await h.quiet();
              expect(
                ((await crm.getBranchScheduleHours(b))['weekly'] as List).any(
                  (r) => r['weekday'] == 1,
                ),
                false,
              );
            },
          );
          await h.check(
            'HOURS-APPLIED',
            'Ранее свободное время теперь запрещено новыми часами работы',
            () async {
              await editor(11);
              expect(
                tester
                    .widget<LessonScheduleSection>(
                      find.byType(LessonScheduleSection),
                    )
                    .model
                    .analysis
                    ?.valid,
                false,
              );
              h.facts.add({'step': h.currentStep, 'blockedByHours': true});
            },
          );
          await h.check(
            'HOURS-RESTORE',
            'Включение понедельника возвращает свободное время',
            () async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await h.mount(SystemSettingsRouteScreen(initialArea: 'schedule'));
              await h.quiet();
              final picker = find.byWidgetPredicate(
                (w) => w is SearchablePickerField && w.label == 'Филиал',
              );
              final pw = tester.widget<SearchablePickerField>(picker),
                  item = pw.items.singleWhere((i) => i.id == b);
              await h.tap(picker);
              await h.tap(find.widgetWithText(MenuItemButton, item.label));
              await h.quiet();
              final row = find.byWidgetPredicate(
                    (w) => w is ScheduleTimeRow && w.label == 'Понедельник',
                  ),
                  toggle = find.descendant(
                    of: row,
                    matching: find.byType(Switch),
                  );
              expect(tester.widget<Switch>(toggle).value, false);
              await h.tap(toggle);
              await h.tap(
                find.descendant(
                  of: find.byType(BranchHoursCard),
                  matching: find.widgetWithText(FilledButton, 'Сохранить'),
                ),
              );
              await h.quiet();
              expect(
                ((await crm.getBranchScheduleHours(b))['weekly'] as List).any(
                  (r) => r['weekday'] == 1,
                ),
                true,
              );
              await editor(11);
              expect(
                tester
                    .widget<LessonScheduleSection>(
                      find.byType(LessonScheduleSection),
                    )
                    .model
                    .analysis
                    ?.valid,
                true,
              );
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
