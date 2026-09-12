import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/upcoming_lessons_list.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['client', 'teacher', 'admin', 'manager', 'director']) {
    testWidgets(
      '$role real workspace functional entrances',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'navigation');
        await h.initialize(
          size: ['client', 'teacher'].contains(role)
              ? const Size(412, 915)
              : const Size(1280, 900),
        );
        await h.check(
          'NAV-ROOT',
          'Рабочее пространство после реальной авторизации',
          () async {
            await h.mount(
              role == 'client'
                  ? const ClientDashboardScreen()
                  : const StaffWorkspaceScreen(),
            );
            await h.waitFor(
              () => find.byType(MessengerScreen).evaluate().isNotEmpty,
              'Initial chat destination mounted',
            );
            final visible = role == 'client'
                ? ['Чат', 'Занятия', 'Абонемент', 'Профиль']
                : role == 'teacher'
                ? ['Чат', 'Расписание', 'Ученики']
                : role == 'admin'
                ? ['Чат', 'Расписание', 'Клиенты', 'Задачи']
                : [
                    'Чат',
                    'Обзор',
                    'Расписание',
                    'Клиенты',
                    'Задачи',
                    'Аналитика',
                    'Настройки',
                  ];
            for (final label in visible) {
              await h.waitFor(
                () => find.text(label).evaluate().isNotEmpty,
                'Visible menu: $label',
              );
            }
            for (final label in [
              'Обзор',
              'Клиенты',
              'Задачи',
              'Аналитика',
              'Настройки',
            ].where((label) => !visible.contains(label))) {
              expect(
                find.text(label),
                findsNothing,
                reason: 'Hidden menu for $role: $label',
              );
            }
          },
        );
        Future<void> section(String id, String label, Type widget) =>
            h.check(id, 'Меню → $label', () async {
              await h.tap(find.text(label).first);
              await h.waitFor(
                () => find.byType(widget).evaluate().isNotEmpty,
                'Product destination $widget mounted',
              );
            });
        if (role == 'client') {
          await section('CLIENT-LESSONS-01', 'Занятия', UpcomingLessonsList);
          await h.check(
            'CLIENT-LESSONS-02',
            'История занятий',
            () async => h.tap(find.text('История')),
          );
          await h.check(
            'CLIENT-LESSONS-06',
            'Домашние задания: загрузка списка',
            () async => h.tap(find.text('Задания')),
          );
          await h.check(
            'CLIENT-MONEY-01',
            'Меню → Абонемент',
            () async => h.tap(find.text('Абонемент').last),
          );
          await h.check(
            'CLIENT-MONEY-02',
            'Абонемент → Оплаты',
            () async => h.tap(find.text('Оплаты')),
          );
          await section('PROFILE-OPEN', 'Профиль', ProfileScreen);
        } else if (role == 'teacher') {
          await section('TEACHER-01', 'Расписание', TeacherScheduleWidget);
          if (h.steps.last['status'] != 'PASS') {
            h.blocked(
              'TEACHER-NO-CREATE',
              'Нет кнопки создания занятия',
              'TEACHER-01',
            );
          } else {
            await h.check(
              'TEACHER-NO-CREATE',
              'Нет кнопки создания занятия',
              () async {
                expect(
                  find.byKey(const Key('teacher-calendar-grid')),
                  findsOneWidget,
                  reason:
                      'Permissions cannot be accepted on an unloaded schedule',
                );
                expect(find.text('Создать занятие'), findsNothing);
              },
            );
          }
          await h.check(
            'TEACHER-IDENTITY-LOOKUP',
            'Поиск собственного профиля по email для загрузки расписания',
            () async {
              final profile = await h.scope
                  .read(magicAuthServiceProvider)
                  .currentProfile();
              final crm = h.scope.read(magicCrmServiceProvider);
              final unfiltered = await crm.listTeachers(limit: 100);
              final own = unfiltered
                  .where((row) => row['profile_user_id'] == profile.userId)
                  .length;
              h.facts.add({'id': 'teacher-identity', 'ownWithoutSearch': own});
              expect(own, 1, reason: 'Fixture has a correctly linked teacher');
            },
          );
          await section('TEACHER-CLIENTS', 'Ученики', TeacherStudentsWidget);
        } else {
          if (role != 'admin') {
            await section('OVERVIEW-OPEN', 'Обзор', ManagerOverviewWidget);
          }
          await section('SCHEDULE-OPEN', 'Расписание', ScheduleWidget);
          await section('CRM-LIST-OPEN', 'Клиенты', ClientsWidget);
          await h.check(
            'CRM-CREATE-LEAD-ENTRANCE',
            'Клиенты → Лиды → создать → отменить',
            () async {
              await h.tap(find.text('Лиды'));
              await h.tap(find.byTooltip('Новый контакт'));
              await h.waitFor(
                () => find
                    .byKey(const Key('lead-first-name'))
                    .evaluate()
                    .isNotEmpty,
                'Real lead form loaded',
              );
              await h.tap(find.text('Отмена').last);
              await h.waitFor(
                () =>
                    find.byKey(const Key('lead-first-name')).evaluate().isEmpty,
                'Lead creation closed',
              );
            },
          );
          await h.check(
            'CRM-CREATE-STUDENT-ENTRANCE',
            'Клиенты → Ученики → создать → отменить',
            () async {
              await h.tap(find.text('Ученики'));
              await h.tap(find.byKey(const Key('students-create')));
              await h.waitFor(
                () => find
                    .byKey(const Key('student-first-name'))
                    .evaluate()
                    .isNotEmpty,
                'Real student form loaded',
              );
              await h.tap(find.text('Отмена').last);
              await h.waitFor(
                () => find
                    .byKey(const Key('student-first-name'))
                    .evaluate()
                    .isEmpty,
                'Student creation closed',
              );
            },
          );
          await section('TASKS-OPEN', 'Задачи', SharedTasksPanel);
          if (role != 'admin') {
            await section('REPORTS-OPEN', 'Аналитика', ReportsWidget);
            await section(
              'SETTINGS-OPEN',
              'Настройки',
              SystemSettingsWorkspace,
            );
            await h.check(
              'SETTINGS-COMMERCE-OPEN',
              'Настройки → Продажи и оплаты',
              () async {
                await h.tap(find.text('Продажи и оплаты'));
                await h.waitFor(
                  () => find.text('Каталог абонементов').evaluate().isNotEmpty,
                  'Product package catalog mounted',
                );
              },
            );
          }
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
