import 'dart:io';
import 'package:magic_music_crm/core/api/magic_api_client.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  final notesOnly = Platform.environment['CLIENT_CONTEXT_NOTES_ONLY'] == '1';
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role notes and contact persons persist',
      (tester) async {
        final h = LiveAuditHarness(
          tester,
          role,
          notesOnly ? 'notes' : 'context',
        );
        await h.initialize(size: const Size(1440, 1100));
        final access = await h.scope.read(capabilitySnapshotProvider.future);
        final crm = h.scope.read(magicCrmServiceProvider);
        final forms = h.scope.read(clientFormsApiProvider);
        final source = (await forms.listSources()).first;
        for (final entity in ['lead', 'student']) {
          final branch = h.fixture['branchId'] as String;
          final pipeline = await crm.getClientPipeline(
            clientType: entity,
            branchId: branch,
          );
          final created = entity == 'lead'
              ? await forms.createLead(
                  identity: MagicMutationIdentity.create('audit.fixture.lead'),
                  firstName: 'Контекст',
                  lastName: 'CONTEXT-$role',
                  phone: '+79991112233',
                  sourceId: source['id'] as String,
                  branchId: branch,
                  status: pipeline.activeStages.first.key,
                  customFields: [],
                )
              : await forms.createStudent(
                  identity: MagicMutationIdentity.create(
                    'audit.fixture.student',
                  ),
                  firstName: 'Контекст',
                  lastName: 'CONTEXT-$role',
                  phone: '+79991112233',
                  sourceId: source['id'] as String,
                  branchId: branch,
                  status: pipeline.activeStages.first.key,
                  customFields: [],
                );
          final id = created['id'] as String;
          Future<Map<String, dynamic>> read() async => entity == 'student'
              ? await crm.getStudent(id)
              : Map<String, dynamic>.from(
                  (await crm.getLeadCard(id))['lead'] as Map,
                );
          Future<void> open() async {
            await h.mount(
              Scaffold(
                body: ClientCard(
                  key: UniqueKey(),
                  lead: await read(),
                  entityType: entity,
                  routed: true,
                  initialSection: 'overview',
                  capabilitySnapshot: access,
                ),
              ),
            );
            await h.waitFor(
              () => find
                  .byKey(const Key('client-internal-note-input'))
                  .evaluate()
                  .isNotEmpty,
              'Note editor loaded',
            );
            await h.quiet();
          }

          final noteField = find.byKey(const Key('client-internal-note-input'));
          Future<void> note(String text) async {
            final before = await crm.getClientInternalNote(
              clientType: entity,
              clientId: id,
            );
            await tester.ensureVisible(noteField);
            await tester.enterText(noteField, text);
            await tester.pump(const Duration(seconds: 2));
            await h.quiet();
            final after = await crm.getClientInternalNote(
              clientType: entity,
              clientId: id,
            );
            h.facts.add({
              'step': h.currentStep,
              'entity': entity,
              'id': id,
              'body': after.body,
              'version': after.version,
            });
            expect(after.body, text);
            expect(after.version, before.version + 1);
          }

          Future<List<Map<String, dynamic>>> contacts() async {
            final row = await read();
            final data = row['custom_data'] as Map? ?? {};
            return (data['contactPersons'] as List? ?? [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
          }

          Future<void> coreSaved() async {
            await tester.pump(const Duration(seconds: 2));
            await h.quiet();
            await h.waitFor(
              () => find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Semantics &&
                        widget.properties.label == 'Изменения сохранены',
                  )
                  .evaluate()
                  .isNotEmpty,
              'Core card save completed',
            );
          }

          Finder contactTile(String name) => find
              .ancestor(of: find.text(name), matching: find.byType(ListTile))
              .first;
          Future<void> fillContact(String name) async {
            final dialog = find.byType(AlertDialog);
            await h.waitFor(
              () => dialog.evaluate().isNotEmpty,
              'Contact dialog opened',
            );
            Finder field(String label) => find.descendant(
              of: dialog,
              matching: find.widgetWithText(TextField, label),
            );
            await tester.enterText(field('Имя'), name);
            await tester.enterText(field('Телефон'), '+79992221100');
            await tester.enterText(
              field('Почта'),
              'contact-$role-$entity@example.test',
            );
            await h.tap(
              find.descendant(
                of: dialog,
                matching: find.widgetWithText(FilledButton, 'Сохранить'),
              ),
            );
            await h.waitFor(
              () => dialog.evaluate().isEmpty,
              'Contact dialog saved',
            );
            await coreSaved();
          }

          Future<void> assertContacts(List<String> names) async {
            final rows = await contacts();
            h.facts.add({
              'step': h.currentStep,
              'entity': entity,
              'id': id,
              'contacts': rows,
            });
            expect(rows.map((row) => row['name']).toList(), names);
          }

          await h.check(
            '$entity-OPEN',
            'Открыть карточку с заметкой и контактами',
            open,
          );
          await h.check(
            '$entity-NOTE-CREATE',
            'Записать многострочную заметку → версия и API',
            () => note('Первая строка\nВторая строка'),
          );
          await h.check(
            '$entity-NOTE-REOPEN',
            'Повторное открытие восстанавливает заметку',
            () async {
              await open();
              expect(
                tester.widget<TextField>(noteField).controller!.text,
                'Первая строка\nВторая строка',
              );
            },
          );
          await h.check(
            '$entity-NOTE-UPDATE',
            'Изменить внутреннюю заметку',
            () => note('Обновлённая заметка'),
          );
          await h.check(
            '$entity-NOTE-CLEAR',
            'Очистить заметку → API → повторное открытие',
            () async {
              await note('');
              await open();
              expect(tester.widget<TextField>(noteField).controller!.text, '');
            },
          );
          if (notesOnly) continue;
          await h.check(
            '$entity-CONTACT-CANCEL',
            'Отмена нового контактного лица не сохраняет запись',
            () async {
              final before = await contacts();
              await h.tap(find.text('Добавить контактное лицо'));
              await h.waitFor(
                () => find.byType(AlertDialog).evaluate().isNotEmpty,
                'Contact dialog',
              );
              await h.tap(find.widgetWithText(TextButton, 'Отмена'));
              expect(await contacts(), before);
            },
          );
          await h.check(
            '$entity-CONTACT-CREATE',
            'Добавить первое контактное лицо → API',
            () async {
              await h.tap(find.text('Добавить контактное лицо'));
              await fillContact('Контакт один');
              await assertContacts(['Контакт один']);
            },
          );
          if (h.steps.last['status'] != 'PASS') {
            for (final step in ['SECOND', 'EDIT', 'REMOVE', 'REOPEN']) {
              h.blocked(
                '$entity-CONTACT-$step',
                'Требует сохранённого контакта',
                '$entity-CONTACT-CREATE',
              );
            }
            continue;
          }
          await h.check(
            '$entity-CONTACT-SECOND',
            'Добавить второе лицо, сохранив первое',
            () async {
              await h.tap(find.text('Добавить контактное лицо'));
              await fillContact('Контакт два');
              await assertContacts(['Контакт один', 'Контакт два']);
            },
          );
          if (h.steps.last['status'] != 'PASS') {
            for (final step in ['EDIT', 'REMOVE', 'REOPEN']) {
              h.blocked(
                '$entity-CONTACT-$step',
                'Требует двух сохранённых контактов',
                '$entity-CONTACT-SECOND',
              );
            }
            continue;
          }
          await h.check(
            '$entity-CONTACT-EDIT',
            'Изменить первое контактное лицо',
            () async {
              await h.tap(
                find.descendant(
                  of: contactTile('Контакт один'),
                  matching: find.byTooltip('Изменить'),
                ),
              );
              await fillContact('Контакт изменён');
              await assertContacts(['Контакт изменён', 'Контакт два']);
            },
          );
          if (h.steps.last['status'] != 'PASS') {
            for (final step in ['REMOVE', 'REOPEN']) {
              h.blocked(
                '$entity-CONTACT-$step',
                'Требует изменённого контакта',
                '$entity-CONTACT-EDIT',
              );
            }
            continue;
          }
          await h.check(
            '$entity-CONTACT-REMOVE',
            'Удалить одно контактное лицо, сохранив другое',
            () async {
              await h.tap(
                find.descendant(
                  of: contactTile('Контакт изменён'),
                  matching: find.byTooltip('Удалить'),
                ),
              );
              await coreSaved();
              await assertContacts(['Контакт два']);
            },
          );
          await h.check(
            '$entity-CONTACT-REOPEN',
            'Повторное открытие показывает сохранённые контактные лица',
            () async {
              await open();
              await assertContacts(['Контакт два']);
              expect(find.text('Контакт два'), findsOneWidget);
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 7)),
    );
  }
}
