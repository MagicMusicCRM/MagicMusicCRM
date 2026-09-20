import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['admin', 'manager', 'director', 'teacher', 'client']) {
    testWidgets('$role own profile persistence', (tester) async {
      final h = LiveAuditHarness(tester, role, 'profile');
      await h.initialize(size: const Size(1440, 1100));
      Finder field(String label) => find.widgetWithText(TextField, label);
      String value(String label) => tester
          .widget<EditableText>(
            find.descendant(
              of: field(label),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      Future<Map<String, dynamic>> read() async {
        final profile = await h.api.get<Map<String, dynamic>>('/profile/me');
        h.facts.add({'step': h.currentStep, 'profile': profile});
        return profile;
      }

      Future<void> open() async {
        // A full close/reopen also disposes the previous snackbar queue.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(ProfileScreen(key: UniqueKey()));
        await h.waitFor(
          () => field('Имя (обязательно)').evaluate().isNotEmpty,
          'Profile fields loaded',
        );
        await h.quiet();
      }

      Future<void> edit(String label, String text) async {
        await h.tap(field(label));
        await tester.enterText(field(label), text);
        await tester.pump();
        expect(value(label), text, reason: 'Text reached actual editor');
      }

      Future<void> save() async {
        final before = h.requests.where((r) => r['method'] == 'PATCH').length;
        await h.tap(find.byTooltip('Сохранить'));
        await h.quiet();
        expect(
          h.requests.where((r) => r['method'] == 'PATCH').length,
          before + 1,
        );
        expect(find.text('Изменения сохранены'), findsOneWidget);
      }

      await h.check(
        'OPEN',
        'Открыть собственный профиль и проверить данные API',
        () async {
          await open();
          final row = await read();
          expect(value('Имя (обязательно)'), row['firstName'] ?? '');
          expect(value('Фамилия (необязательно)'), row['lastName'] ?? '');
          expect(find.byTooltip('Сохранить'), findsNothing);
        },
      );
      await h.check(
        'NAME-SAVE',
        'Изменить имя и фамилию, сохранить и открыть повторно',
        () async {
          await edit('Имя (обязательно)', 'Профиль');
          await edit('Фамилия (необязательно)', 'PROFILE-$role');
          await save();
          final row = await read();
          expect(row['firstName'], 'Профиль');
          expect(row['lastName'], 'PROFILE-$role');
          await open();
          expect(value('Имя (обязательно)'), 'Профиль');
          expect(value('Фамилия (необязательно)'), 'PROFILE-$role');
        },
      );
      await h.check(
        'LASTNAME-CLEAR',
        'Очистить необязательную фамилию и сохранить',
        () async {
          await edit('Фамилия (необязательно)', '');
          await save();
          final row = await read();
          await open();
          expect(
            row['lastName'] ?? '',
            '',
            reason: 'Empty optional surname persisted',
          );
          expect(value('Фамилия (необязательно)'), '');
        },
      );
      final phone =
          '+79990000${['admin', 'manager', 'director', 'teacher', 'client'].indexOf(role) + 101}';
      await h.check(
        'PHONE-SAVE',
        'Изменить телефон и проверить сохранение в API и форме',
        () async {
          final phoneField = find.widgetWithText(TextField, 'Номер телефона');
          await h.tap(phoneField);
          await tester.enterText(phoneField, phone);
          await tester.pump();
          await save();
          final row = await read();
          expect(row['phone'], phone);
          await open();
          final text = tester
              .widget<EditableText>(
                find.descendant(
                  of: phoneField,
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text;
          expect(text.replaceAll(RegExp(r'\D'), ''), phone.substring(1));
        },
      );
      await h.check('PHONE-CLEAR', 'Очистить телефон и сохранить', () async {
        final phoneField = find.widgetWithText(TextField, 'Номер телефона');
        await h.tap(phoneField);
        await tester.enterText(phoneField, '');
        await tester.pump();
        await save();
        final row = await read();
        await open();
        expect(row['phone'] ?? '', '', reason: 'Phone removal persisted');
      });
      await h.check(
        'FIRSTNAME-REQUIRED',
        'Пустое обязательное имя отклоняется без PATCH',
        () async {
          await open();
          final before = h.requests.where((r) => r['method'] == 'PATCH').length;
          await edit('Имя (обязательно)', '');
          await h.tap(find.byTooltip('Сохранить'));
          await h.quiet();
          expect(find.text('Имя обязательно'), findsOneWidget);
          expect(
            h.requests.where((r) => r['method'] == 'PATCH').length,
            before,
          );
          expect((await read())['firstName'], 'Профиль');
          await open();
        },
      );
      await h.check(
        'DOB-CANCEL',
        'Отмена выбора дня рождения не изменяет профиль',
        () async {
          await open();
          final before = await read();
          await h.tap(find.text('День рождения'));
          final l10n = MaterialLocalizations.of(
            tester.element(find.byType(DatePickerDialog)),
          );
          await h.tap(find.text(l10n.cancelButtonLabel));
          expect(find.byType(DatePickerDialog), findsNothing);
          expect(find.byTooltip('Сохранить'), findsNothing);
          expect((await read())['dob'], before['dob']);
        },
      );
      await h.check(
        'DOB-SAVE',
        'Выбрать день рождения, сохранить и открыть повторно',
        () async {
          await open();
          await h.tap(find.text('День рождения'));
          final l10n = MaterialLocalizations.of(
            tester.element(find.byType(DatePickerDialog)),
          );
          await h.tap(find.byTooltip(l10n.inputDateModeButtonLabel));
          final input = find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextFormField),
          );
          await h.tap(input);
          await tester.enterText(
            input,
            l10n.formatCompactDate(DateTime(1994, 5, 17)),
          );
          await h.tap(find.text(l10n.okButtonLabel));
          expect(find.byType(DatePickerDialog), findsNothing);
          await save();
          expect(
            (await read())['dob'].toString().substring(0, 10),
            '1994-05-17',
          );
          await open();
          expect(find.text('1994-05-17'), findsOneWidget);
        },
      );
      await h.finish();
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
