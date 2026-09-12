import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_teacher_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['director', 'manager']) {
    testWidgets(
      '$role creates and edits teachers without login credentials',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'teacher-forms');
        await h.initialize(size: const Size(1440, 1800));
        final crm = h.scope.read(magicCrmServiceProvider);
        final first = 'TEACHER-AUDIT-$role';
        String last = 'Исходная';
        String? id;
        final create = find.byType(CreateTeacherDialog),
            detail = find.byType(TeacherDetailDialog);
        Finder field(Finder modal, String label) => find.descendant(
          of: modal,
          matching: find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label,
          ),
        );
        Future<void> fill(Finder modal, String label, String value) async {
          final target = field(modal, label);
          await h.tap(target);
          await tester.enterText(target, value);
          await tester.pump();
        }

        Future<void> button(Finder modal, String label) =>
            h.tap(find.descendant(of: modal, matching: find.text(label)));
        Future<void> catalog() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'users'),
          );
          await h.quiet();
          await h.tap(find.text('Преподаватели'));
          await h.quiet();
        }

        Future<void> newTeacher() async {
          await catalog();
          await h.tap(find.text('Новый преподаватель'));
          await h.quiet();
          expect(create, findsOneWidget);
        }

        Future<void> identity(String name) async {
          await fill(create, 'Имя *', name);
          await fill(create, 'Фамилия', last);
          await h.tap(find.widgetWithText(FilterChip, 'HTTP test'));
          if (role == 'director') {
            await h.tap(
              find.descendant(
                of: find.byType(TeacherRateSelector),
                matching: find.byType(DropdownButtonFormField<String>),
              ),
            );
            await h.tap(find.text('750 ₽').last);
          }
        }

        Future<Map<String, dynamic>> current() async {
          final row = (await crm.listTeachers(
            q: first,
          )).singleWhere((r) => r['id'] == id);
          h.facts.add({'step': h.currentStep, 'teacher': row});
          return row;
        }

        Future<void> open() async {
          await catalog();
          await h.tap(find.text('$first $last'));
          await h.quiet();
          expect(detail, findsOneWidget);
        }

        await h.check(
          'CANCEL',
          'Отмена заполненного создания не оставляет преподавателя',
          () async {
            await newTeacher();
            await identity('TEACHER-CANCELLED-$role');
            await button(create, 'Отмена');
            expect(
              await crm.listTeachers(q: 'TEACHER-CANCELLED-$role'),
              isEmpty,
            );
          },
        );
        await h.check(
          'VALIDATION',
          'Пустое имя и отрицательный оклад блокируют создание',
          () async {
            await newTeacher();
            await button(create, 'Создать');
            expect(find.text('Обязательное поле'), findsOneWidget);
            await identity(first);
            await fill(create, 'Оклад, ₽/мес', '-1');
            await button(create, 'Создать');
            expect(find.text('Введите сумму не меньше нуля'), findsOneWidget);
            expect(
              h.requests.where(
                (r) =>
                    r['step'] == h.currentStep &&
                    r['method'] == 'POST' &&
                    r['path'] == '/api/crm/teachers',
              ),
              isEmpty,
            );
            await button(create, 'Отмена');
          },
        );
        await h.check(
          'CREATE',
          'Создать преподавателя без аккаунта с филиалом и разрешёнными условиями',
          () async {
            await newTeacher();
            await identity(first);
            expect(
              find.byType(TeacherRateSelector),
              role == 'director' ? findsOneWidget : findsNothing,
            );
            await button(create, 'Создать');
            await h.quiet();
            expect(create, findsNothing);
            final row = (await crm.listTeachers(q: first)).single;
            id = row['id'] as String;
            h.facts.add({'step': h.currentStep, 'teacher': row});
            expect(row['first_name'], first);
            expect(row['last_name'], last);
            expect(row['is_app_account'], false);
            if (role == 'director') expect(row['current_rate'], 750);
          },
        );
        if (id == null) {
          h.blocked(
            'EDIT-DEPENDENTS',
            'Изменение и повторное открытие',
            'Teacher creation failed',
          );
          await h.finish();
          return;
        }
        await h.check(
          'REOPEN',
          'Повторное открытие показывает сохранённое имя и назначенный филиал',
          () async {
            await open();
            expect(
              tester
                  .widget<TextField>(field(detail, 'Имя Фамилия'))
                  .controller!
                  .text,
              '$first $last',
            );
            expect(
              tester
                  .widget<FilterChip>(
                    find.widgetWithText(FilterChip, 'HTTP test'),
                  )
                  .selected,
              true,
            );
            await button(detail, 'Отмена');
          },
        );
        await h.check(
          'EDIT-CANCEL',
          'Отмена изменения имени оставляет исходного преподавателя',
          () async {
            await open();
            await fill(detail, 'Имя Фамилия', '$first Отменена');
            await button(detail, 'Отмена');
            expect((await current())['last_name'], last);
          },
        );
        await h.check(
          'EDIT-SAVE',
          'Имя сохраняется без изменения ставки и доступа',
          () async {
            await open();
            await fill(detail, 'Имя Фамилия', '$first Изменена');
            await button(detail, 'Сохранить');
            await h.quiet();
            expect(detail, findsNothing);
            final row = await current();
            expect(row['last_name'], 'Изменена');
            expect(row['is_app_account'], false);
            last = 'Изменена';
            if (role == 'director') expect(row['current_rate'], 750);
          },
        );
        await h.check(
          'BRANCH-EMPTY',
          'Снятие единственного филиала не сохраняется',
          () async {
            await open();
            await h.tap(find.widgetWithText(FilterChip, 'HTTP test'));
            await button(detail, 'Сохранить');
            expect(find.text('Выберите хотя бы один филиал.'), findsOneWidget);
            await button(detail, 'Отмена');
            await open();
            expect(
              tester
                  .widget<FilterChip>(
                    find.widgetWithText(FilterChip, 'HTTP test'),
                  )
                  .selected,
              true,
            );
            await button(detail, 'Отмена');
          },
        );
        await h.check(
          'REOPEN-SAVED',
          'Сохранённое имя читается после закрытия карточки и повторного открытия',
          () async {
            await open();
            expect(
              tester
                  .widget<TextField>(field(detail, 'Имя Фамилия'))
                  .controller!
                  .text,
              '$first Изменена',
            );
            await button(detail, 'Отмена');
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
