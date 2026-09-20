import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_employee_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['director', 'manager']) {
    testWidgets(
      '$role creates and edits staff without provisioning access',
      (tester) async {
        final previousError = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint(
            'STAFF_FRAME_ERROR ${details.exceptionAsString()}\n${details.stack}',
          );
          previousError?.call(details);
        };
        addTearDown(() => FlutterError.onError = previousError);
        final h = LiveAuditHarness(tester, role, 'staff-forms');
        await h.initialize(size: const Size(1440, 1500));
        final crm = h.scope.read(magicCrmServiceProvider);
        final first = 'STAFF-AUDIT-$role';
        String last = 'Исходная';
        String? id;
        final create = find.byType(CreateEmployeeDialog),
            detail = find.byType(StaffDetailDialog);
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
          await h.tap(find.text('Сотрудники'));
          await h.quiet();
        }

        Future<void> newStaff() async {
          await catalog();
          await h.tap(find.text('Новый сотрудник'));
          await h.quiet();
          expect(create, findsOneWidget);
        }

        Future<void> identity(String name) async {
          await fill(create, 'Имя *', name);
          await fill(create, 'Фамилия *', last);
          await h.tap(
            find.byKey(
              ValueKey('create-employee-branch-${h.fixture['branchId']}'),
            ),
          );
        }

        Future<Map<String, dynamic>> current() async {
          final row = (await crm.listStaff(
            q: first,
          )).singleWhere((r) => r['id'] == id);
          h.facts.add({'step': h.currentStep, 'staff': row});
          return row;
        }

        Future<void> open() async {
          await catalog();
          final target = find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.data == '$last $first' || w.data == '$first $last'),
          );
          await h.tap(target);
          await h.quiet();
          expect(detail, findsOneWidget);
        }

        await h.check(
          'CANCEL',
          'Отмена заполненного создания не оставляет сотрудника',
          () async {
            await newStaff();
            await identity('STAFF-CANCELLED-$role');
            await button(create, 'Отмена');
            expect(await crm.listStaff(q: 'STAFF-CANCELLED-$role'), isEmpty);
          },
        );
        await h.check(
          'VALIDATION',
          'Пустые имя и фамилия, отсутствующий филиал не отправляют создание',
          () async {
            await newStaff();
            await button(create, 'Добавить сотрудника');
            expect(find.text('Обязательное поле'), findsNWidgets(2));
            await fill(create, 'Имя *', first);
            await fill(create, 'Фамилия *', last);
            await button(create, 'Добавить сотрудника');
            expect(find.text('Выберите хотя бы один филиал.'), findsOneWidget);
            expect(
              h.requests.where(
                (r) =>
                    r['step'] == h.currentStep &&
                    r['method'] == 'POST' &&
                    r['path'] == '/api/crm/staff',
              ),
              isEmpty,
            );
            await button(create, 'Отмена');
          },
        );
        await h.check(
          'EMAIL-PAIR',
          'Некорректная почта и почта без пароля блокируют создание',
          () async {
            await newStaff();
            await identity(first);
            await fill(create, 'Электронная почта (необязательно)', 'invalid');
            await button(create, 'Добавить сотрудника');
            expect(find.text('Введите корректный адрес почты'), findsOneWidget);
            await fill(
              create,
              'Электронная почта (необязательно)',
              'audit@example.test',
            );
            await button(create, 'Добавить сотрудника');
            expect(find.text('Укажите пароль вместе с почтой'), findsOneWidget);
            expect(
              h.requests.where(
                (r) =>
                    r['step'] == h.currentStep &&
                    r['method'] == 'POST' &&
                    r['path'] == '/api/crm/staff',
              ),
              isEmpty,
            );
            await button(create, 'Отмена');
          },
        );
        await h.check(
          'CREATE',
          'Создать сотрудника без почты и пароля в выбранном филиале',
          () async {
            await newStaff();
            await identity(first);
            await button(create, 'Добавить сотрудника');
            await h.quiet();
            expect(create, findsNothing);
            final row = (await crm.listStaff(q: first)).single;
            id = row['id'] as String;
            h.facts.add({'step': h.currentStep, 'staff': row});
            expect(row['first_name'], first);
            expect(row['last_name'], last);
            expect(row['is_app_account'], false);
          },
        );
        if (id == null) {
          h.blocked(
            'EDIT-DEPENDENTS',
            'Изменение и повторное открытие',
            'Staff creation failed',
          );
          await h.finish();
          return;
        }
        await h.check(
          'REOPEN',
          'Повторное открытие карточки показывает сохранённые имя, фамилию и филиал',
          () async {
            await open();
            expect(
              tester.widget<TextField>(field(detail, 'Имя')).controller!.text,
              first,
            );
            expect(
              tester
                  .widget<TextField>(field(detail, 'Фамилия'))
                  .controller!
                  .text,
              last,
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
          'Отмена правки должности и фамилии оставляет исходные данные',
          () async {
            await open();
            await fill(detail, 'Фамилия', 'Отменена');
            await fill(detail, 'Должность', 'Отменена');
            await button(detail, 'Отмена');
            expect((await current())['last_name'], last);
            expect((await current())['position'], 'Администратор');
          },
        );
        await h.check(
          'EDIT-SAVE',
          'Фамилия и должность сохраняются без изменения доступа',
          () async {
            await open();
            await fill(detail, 'Фамилия', 'Изменена');
            await fill(detail, 'Должность', 'Координатор');
            await button(detail, 'Сохранить');
            await h.quiet();
            expect(detail, findsNothing);
            final row = await current();
            expect(row['last_name'], 'Изменена');
            expect(row['position'], 'Координатор');
            expect(row['is_app_account'], false);
            last = 'Изменена';
          },
        );
        await h.check(
          'POSITION-CLEAR',
          'Очистка должности сохраняется после повторного открытия',
          () async {
            await open();
            expect(
              tester
                  .widget<TextField>(field(detail, 'Должность'))
                  .controller!
                  .text,
              'Координатор',
            );
            await fill(detail, 'Должность', '');
            await button(detail, 'Сохранить');
            await h.quiet();
            expect((await current())['position'] ?? '', '');
            await open();
            expect(
              tester
                  .widget<TextField>(field(detail, 'Должность'))
                  .controller!
                  .text,
              '',
            );
            await button(detail, 'Отмена');
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
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
