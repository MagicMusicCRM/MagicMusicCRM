import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role persisted fields in lead and student cards',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'fields');
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
          // Preparation uses the same production service and a single create;
          // creation retry is already covered by the separate defect regression.
          final created = entity == 'lead'
              ? await forms.createLead(
                  identity: MagicMutationIdentity.create('audit.fixture.lead'),
                  firstName: 'Исходный',
                  lastName: 'FIELDS-$role',
                  phone: '+79995554433',
                  sourceId: source['id'] as String,
                  branchId: branch,
                  status: pipeline.activeStages.first.key,
                  customFields: [],
                )
              : await forms.createStudent(
                  identity: MagicMutationIdentity.create(
                    'audit.fixture.student',
                  ),
                  firstName: 'Исходный',
                  lastName: 'FIELDS-$role',
                  phone: '+79995554433',
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
            final row = await read();
            await h.mount(
              Scaffold(
                body: ClientCard(
                  key: UniqueKey(),
                  lead: row,
                  entityType: entity,
                  routed: true,
                  initialSection: 'overview',
                  capabilitySnapshot: access,
                ),
              ),
            );
            await h.waitFor(
              () => find
                  .widgetWithText(TextFormField, 'Имя')
                  .evaluate()
                  .isNotEmpty,
              'Card fields loaded',
            );
            await h.quiet();
          }

          Finder textField(String label) =>
              find.widgetWithText(TextFormField, label);
          Finder phoneField() => find
              .descendant(
                of: find.byType(RuPhoneField),
                matching: find.byType(TextField),
              )
              .first;
          String visibleValue(Finder finder) =>
              tester.widget<TextFormField>(finder).controller?.text ??
              tester.widget<TextFormField>(finder).initialValue ??
              '';
          bool saved() => find
              .byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label == 'Изменения сохранены',
              )
              .evaluate()
              .isNotEmpty;
          Future<void> edit(Finder finder, String value) async {
            final writesBefore = h.requests
                .where((request) => request['method'] == 'PATCH')
                .length;
            await tester.ensureVisible(finder);
            await tester.enterText(finder, value);
            await tester.pump(const Duration(seconds: 2));
            await h.quiet();
            await h.waitFor(
              () =>
                  h.requests
                      .where((request) => request['method'] == 'PATCH')
                      .length >
                  writesBefore,
              'Field edit sends a new PATCH',
            );
            await h.waitFor(saved, 'Core card fields show persisted status');
          }

          Future<void> assertValue(String field, String? expected) async {
            final row = await read();
            final actual = row[field]?.toString();
            h.facts.add({
              'step': h.currentStep,
              'entity': entity,
              'id': id,
              'field': field,
              'expected': expected,
              'actual': actual,
              'uiSaved': saved(),
            });
            expect(actual?.isEmpty == true ? null : actual, expected);
          }

          await h.check('$entity-OPEN', 'Открыть карточку с API-данными', open);
          if (entity == 'student') {
            await h.check(
              'student-CONTACT-READ-CONTRACT',
              'Контакты GET ученика совпадают с данными GET карточки',
              () async {
                final row = await read();
                final card = (await crm.getStudentCard(id))['student'] as Map;
                h.facts.add({
                  'step': h.currentStep,
                  'id': id,
                  'directoryPhone': row['phone'],
                  'cardPhone': card['phone'],
                  'directoryEmail': row['email'],
                  'cardEmail': card['email'],
                });
                expect(card['phone'], row['phone']);
                expect(card['email'], row['email']);
              },
            );
          }
          await h.check(
            '$entity-PHONE-EDIT',
            'Изменить телефон → сохранение → повторное открытие',
            () async {
              await edit(phoneField(), '9991234567');
              await assertValue('phone', '+79991234567');
              await open();
              expect(
                tester
                    .widget<TextField>(phoneField())
                    .controller!
                    .text
                    .replaceAll(RegExp(r'\D'), ''),
                '79991234567',
              );
            },
          );
          await h.check(
            '$entity-PHONE-CLEAR',
            'Очистить телефон: сохранить пустое значение или явно запретить',
            () async {
              await open();
              // Establish a populated editor independently of the card-read bug.
              // This prevents an already empty field from masquerading as clear.
              await edit(phoneField(), '9997654321');
              await assertValue('phone', '+79997654321');
              await edit(phoneField(), '');
              // No validation message is shown and the UI claims "saved"; then the
              // backend value must agree with the empty field, not silently revert.
              await assertValue('phone', null);
              await open();
              expect(
                tester
                    .widget<TextField>(phoneField())
                    .controller!
                    .text
                    .replaceAll(RegExp(r'\D'), ''),
                isEmpty,
              );
            },
          );
          await h.check(
            '$entity-EMAIL-EDIT',
            'Изменить email → сохранение → повторное открытие',
            () async {
              await open();
              final email = 'fields-$role-$entity@example.test';
              await edit(textField('Электронная почта'), email);
              await assertValue('email', email);
              await open();
              expect(visibleValue(textField('Электронная почта')), email);
            },
          );
          await h.check(
            '$entity-EMAIL-INVALID',
            'Невалидный email не отправляется и не заменяет сохранённый',
            () async {
              await open();
              final before = (await read())['email'];
              final writes = h.requests
                  .where((request) => request['method'] == 'PATCH')
                  .length;
              await tester.ensureVisible(textField('Электронная почта'));
              await tester.enterText(
                textField('Электронная почта'),
                'invalid-email',
              );
              await tester.pump(const Duration(seconds: 2));
              await h.quiet();
              expect(
                find.text('Введите корректный адрес электронной почты'),
                findsOneWidget,
              );
              expect(
                h.requests
                    .where((request) => request['method'] == 'PATCH')
                    .length,
                writes,
              );
              expect((await read())['email'], before);
              expect(
                visibleValue(textField('Электронная почта')),
                'invalid-email',
              );
            },
          );
          await h.check(
            '$entity-EMAIL-CLEAR',
            'Очистить email → сохранение → повторное открытие',
            () async {
              await open();
              await edit(
                textField('Электронная почта'),
                'clear-$role-$entity@example.test',
              );
              await assertValue('email', 'clear-$role-$entity@example.test');
              await edit(textField('Электронная почта'), '');
              await assertValue('email', null);
              await open();
              expect(visibleValue(textField('Электронная почта')), '');
            },
          );
          await h.check(
            '$entity-NAME-RAPID',
            'Серия быстрых правок сохраняет последнее имя',
            () async {
              await open();
              await tester.ensureVisible(textField('Имя'));
              for (final name in ['Первое', 'Второе', 'Последнее']) {
                await tester.enterText(textField('Имя'), name);
                await tester.pump(const Duration(milliseconds: 100));
              }
              await tester.pump(const Duration(seconds: 2));
              await h.quiet();
              await h.waitFor(saved, 'Latest name saved');
              await assertValue('first_name', 'Последнее');
              await open();
              expect(visibleValue(textField('Имя')), 'Последнее');
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 7)),
    );
  }
}
