import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/branch_form_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_room_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Branch and room forms persist through the real API',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'branch-rooms');
      await h.initialize(size: const Size(1440, 1400));
      final crm = h.scope.read(magicCrmServiceProvider);
      String? branchId;
      String? roomId;
      var branchName = 'BRANCH-FORM-AUDIT';
      var roomName = 'ROOM-FORM-AUDIT';
      final branchDialog = find.byType(BranchFormDialog);
      final roomDialog = find.byType(CreateRoomDialog);
      Finder field(Finder dialog, String label) => find.descendant(
        of: dialog,
        matching: find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        ),
      );
      Future<void> fill(Finder dialog, String label, String text) async {
        final finder = field(dialog, label);
        await h.tap(finder);
        await tester.enterText(finder, text);
        expect(tester.widget<TextField>(finder).controller!.text, text);
        await tester.pump();
      }

      Future<void> button(Finder dialog, String label) =>
          h.tap(find.descendant(of: dialog, matching: find.text(label)));
      Future<void> catalog() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          SystemSettingsRouteScreen(
            key: UniqueKey(),
            initialArea: 'organization',
          ),
        );
        await h.waitFor(
          () => find.text('HTTP test').evaluate().isNotEmpty,
          'Branch list loaded',
        );
        await h.quiet();
      }

      Future<void> createBranch() async {
        await catalog();
        await h.tap(find.text('Новый филиал'));
        await h.quiet();
      }

      Future<void> editBranch() async {
        await catalog();
        await h.tap(find.text(branchName));
        await h.quiet();
        expect(branchDialog, findsOneWidget);
      }

      Future<Map<String, dynamic>> readBranch() async {
        final row = (await crm.listBranches()).singleWhere(
          (r) => r['id'] == branchId,
        );
        h.facts.add({'step': h.currentStep, 'branch': row});
        return row;
      }

      Future<List<Map<String, dynamic>>> rooms() =>
          crm.listRooms(branchId: branchId);
      Future<Map<String, dynamic>> readRoom() async {
        final row = (await rooms()).singleWhere((r) => r['id'] == roomId);
        h.facts.add({'step': h.currentStep, 'room': row});
        return row;
      }

      Future<void> newRoom() async {
        await editBranch();
        await h.tap(
          find
              .descendant(
                of: branchDialog,
                matching: find.widgetWithText(FilledButton, 'Добавить'),
              )
              .last,
        );
        await h.quiet();
        expect(roomDialog, findsOneWidget);
      }

      Future<void> editRoom() async {
        await editBranch();
        await h.tap(find.text(roomName));
        await h.quiet();
        expect(roomDialog, findsOneWidget);
      }

      int writes() => h.requests
          .where((r) => ['POST', 'PATCH', 'DELETE'].contains(r['method']))
          .length;

      await h.check(
        'BRANCH-CANCEL',
        'Отмена заполненного нового филиала не создаёт запись',
        () async {
          await createBranch();
          await fill(branchDialog, 'Название *', 'BRANCH-CANCELLED');
          await fill(branchDialog, 'Адрес', 'Черновик');
          await button(branchDialog, 'Отмена');
          expect(
            (await crm.listBranches()).any(
              (r) => r['name'] == 'BRANCH-CANCELLED',
            ),
            isFalse,
          );
        },
      );
      await h.check(
        'BRANCH-VALIDATION',
        'Название и хотя бы один рабочий день обязательны',
        () async {
          await createBranch();
          final before = writes();
          await button(branchDialog, 'Сохранить');
          expect(find.text('Введите название филиала'), findsOneWidget);
          await fill(branchDialog, 'Название *', branchName);
          await button(branchDialog, 'Сохранить');
          expect(branchDialog, findsOneWidget);
          expect(writes(), before);
          await button(branchDialog, 'Отмена');
        },
      );
      await h.check(
        'BRANCH-CREATE',
        'Создать филиал с адресом и рабочим понедельником',
        () async {
          await createBranch();
          await fill(branchDialog, 'Название *', branchName);
          await fill(branchDialog, 'Адрес', 'Аудит, дом 1');
          await h.tap(
            find
                .descendant(of: branchDialog, matching: find.byType(Switch))
                .first,
          );
          await button(branchDialog, 'Сохранить');
          await h.quiet();
          expect(branchDialog, findsNothing);
          final rows = (await crm.listBranches())
              .where((r) => r['name'] == branchName)
              .toList();
          expect(rows.length, 1);
          branchId = rows.single['id'] as String;
          expect((await readBranch())['address'], 'Аудит, дом 1');
          expect(find.text(branchName), findsOneWidget);
        },
      );
      if (branchId == null) {
        h.blocked(
          'DEPENDENT-FORMS',
          'Редактирование филиала и аудитории',
          'Branch creation failed',
        );
        await h.finish();
        return;
      }
      await h.check(
        'BRANCH-REOPEN',
        'Повторное открытие сохраняет название, адрес и часовой пояс',
        () async {
          await editBranch();
          expect(
            tester
                .widget<TextField>(field(branchDialog, 'Название *'))
                .controller!
                .text,
            branchName,
          );
          expect(
            tester
                .widget<TextField>(field(branchDialog, 'Адрес'))
                .controller!
                .text,
            'Аудит, дом 1',
          );
          expect(
            tester
                .widget<DropdownButtonFormField<int>>(
                  find.byType(DropdownButtonFormField<int>),
                )
                .initialValue,
            180,
          );
        },
      );
      await h.check(
        'BRANCH-EDIT',
        'Сохранить название, адрес и другой часовой пояс',
        () async {
          await editBranch();
          await fill(branchDialog, 'Название *', 'BRANCH-FORM-UPDATED');
          await fill(branchDialog, 'Адрес', 'Аудит, дом 2');
          await h.tap(find.byType(DropdownButtonFormField<int>));
          await h.tap(find.text('Калининград (+2 ч)').last);
          await button(branchDialog, 'Сохранить');
          await h.quiet();
          final row = await readBranch();
          branchName = row['name'] as String;
          expect(branchName, 'BRANCH-FORM-UPDATED');
          expect(row['address'], 'Аудит, дом 2');
          expect(row['utc_offset_minutes'], 120);
          expect(find.text(branchName), findsOneWidget);
        },
      );
      await h.check(
        'BRANCH-CLEAR',
        'Очистить необязательный адрес и повторно открыть форму',
        () async {
          await editBranch();
          await fill(branchDialog, 'Адрес', '');
          await button(branchDialog, 'Сохранить');
          await h.quiet();
          expect((await readBranch())['address'], anyOf(isNull, ''));
          await editBranch();
          expect(
            tester
                .widget<TextField>(field(branchDialog, 'Адрес'))
                .controller!
                .text,
            '',
          );
          expect(
            tester
                .widget<DropdownButtonFormField<int>>(
                  find.byType(DropdownButtonFormField<int>),
                )
                .initialValue,
            120,
          );
        },
      );
      await h.check(
        'BRANCH-EDIT-CANCEL',
        'Отмена правки сохраняет исходное название филиала',
        () async {
          await editBranch();
          await fill(branchDialog, 'Название *', 'BRANCH-DRAFT');
          await button(branchDialog, 'Отмена');
          expect((await readBranch())['name'], branchName);
        },
      );
      await h.check(
        'BRANCH-TIMEZONE',
        'Часовой пояс расписания соответствует сохранённому выбору Калининграда',
        () async {
          final hours = await h.api.get<Map<String, dynamic>>(
            '/crm/schedule-reference/branches/$branchId/hours',
          );
          h.facts.add({'step': h.currentStep, 'scheduleHours': hours});
          expect((await readBranch())['utc_offset_minutes'], 120);
          expect(hours['timezone'], 'Europe/Kaliningrad');
        },
      );
      await h.check(
        'ROOM-CANCEL',
        'Отмена заполненной аудитории не сохраняет черновик',
        () async {
          await newRoom();
          await fill(roomDialog, 'Название *', 'ROOM-CANCELLED');
          await fill(roomDialog, 'Вместимость, человек', '10');
          await button(roomDialog, 'Отмена');
          expect(await rooms(), isEmpty);
        },
      );
      await h.check(
        'ROOM-VALIDATION',
        'Обязательное название; вместимость допускает целые числа 1–1000',
        () async {
          await newRoom();
          final before = writes();
          await button(roomDialog, 'Сохранить');
          expect(find.text('Введите название аудитории'), findsOneWidget);
          await fill(roomDialog, 'Название *', roomName);
          for (final value in ['0', '1001', '1.5', 'abc']) {
            await fill(roomDialog, 'Вместимость, человек', value);
            await button(roomDialog, 'Сохранить');
            expect(
              find.text('Введите целое число от 1 до 1000'),
              findsOneWidget,
            );
          }
          expect(writes(), before);
          await button(roomDialog, 'Отмена');
        },
      );
      await h.check(
        'ROOM-CREATE',
        'Создать аудиторию с вместимостью 10',
        () async {
          await newRoom();
          await fill(roomDialog, 'Название *', roomName);
          await fill(roomDialog, 'Вместимость, человек', '10');
          await button(roomDialog, 'Сохранить');
          await h.quiet();
          expect(roomDialog, findsNothing);
          final row = (await rooms()).single;
          roomId = row['id'] as String;
          expect(row['name'], roomName);
          expect(row['capacity'], 10);
          expect(find.text(roomName), findsOneWidget);
        },
      );
      if (roomId == null) {
        h.blocked(
          'ROOM-DEPENDENTS',
          'Редактирование аудитории',
          'Room creation failed',
        );
        await h.finish();
        return;
      }
      await h.check(
        'ROOM-REOPEN',
        'Повторное открытие аудитории показывает сохранённые значения',
        () async {
          await editRoom();
          expect(
            tester
                .widget<TextField>(field(roomDialog, 'Название *'))
                .controller!
                .text,
            roomName,
          );
          expect(
            tester
                .widget<TextField>(field(roomDialog, 'Вместимость, человек'))
                .controller!
                .text,
            '10',
          );
        },
      );
      await h.check(
        'ROOM-EDIT',
        'Изменить название и вместимость аудитории',
        () async {
          await editRoom();
          await fill(roomDialog, 'Название *', 'ROOM-FORM-UPDATED');
          await fill(roomDialog, 'Вместимость, человек', '25');
          await button(roomDialog, 'Сохранить');
          await h.quiet();
          final row = await readRoom();
          roomName = row['name'] as String;
          expect(roomName, 'ROOM-FORM-UPDATED');
          expect(row['capacity'], 25);
          expect(find.text(roomName), findsOneWidget);
        },
      );
      await h.check(
        'ROOM-CLEAR',
        'Очистить вместимость и проверить после повторного открытия',
        () async {
          await editRoom();
          await fill(roomDialog, 'Вместимость, человек', '');
          await button(roomDialog, 'Сохранить');
          await h.quiet();
          expect((await readRoom())['capacity'], isNull);
          await editRoom();
          expect(
            tester
                .widget<TextField>(field(roomDialog, 'Вместимость, человек'))
                .controller!
                .text,
            '',
          );
        },
      );
      await h.check(
        'ROOM-EDIT-CANCEL',
        'Отмена редактирования сохраняет итоговые данные аудитории',
        () async {
          await editRoom();
          await fill(roomDialog, 'Название *', 'ROOM-DRAFT');
          await fill(roomDialog, 'Вместимость, человек', '100');
          await button(roomDialog, 'Отмена');
          final row = await readRoom();
          expect(row['name'], roomName);
          expect(row['capacity'], isNull);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
