import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
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
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role configured lead transitions',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'statuses');
        await h.initialize(size: const Size(1440, 1100));
        final crm = h.scope.read(magicCrmServiceProvider);
        final forms = h.scope.read(clientFormsApiProvider);
        final access = await h.scope.read(capabilitySnapshotProvider.future);
        final created = await forms.createLead(
          identity: MagicMutationIdentity.create('audit.fixture.lead'),
          firstName: 'Статус',
          lastName: 'STATUS-$role',
          phone: '+79995554433',
          sourceId: (await forms.listSources()).first['id'] as String,
          branchId: h.fixture['branchId'] as String,
          status: 'new',
          customFields: [],
        );
        final id = created['id'] as String;
        Future<Map<String, dynamic>> row() async => Map<String, dynamic>.from(
          (await crm.getLeadCard(id))['lead'] as Map,
        );
        Future<void> open() async {
          await h.mount(
            Scaffold(
              body: ClientCard(
                key: UniqueKey(),
                lead: await row(),
                entityType: 'lead',
                routed: true,
                capabilitySnapshot: access,
              ),
            ),
          );
          await h.waitFor(
            () =>
                find.widgetWithText(TextFormField, 'Имя').evaluate().isNotEmpty,
            'Lead editor loaded',
          );
          await h.quiet();
        }

        Finder picker() => find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Статус',
        );
        Future<void> choose(String label) async {
          await h.tap(picker());
          await h.tap(find.text(label).last);
          await tester.pump(const Duration(seconds: 2));
          await h.quiet();
        }

        await h.check(
          'OPEN',
          'Открыть лид с тремя настроенными этапами',
          () async {
            await open();
            final items = tester
                .widget<DropdownButton<String>>(
                  find.descendant(
                    of: picker(),
                    matching: find.byType(DropdownButton<String>),
                  ),
                )
                .items!;
            expect(items, hasLength(3));
            h.facts.add({
              'step': h.currentStep,
              'id': id,
              'status': (await row())['status_id'],
              'options': items.map((i) => i.value).toList(),
            });
          },
        );
        String? contactedStatus;
        await h.check(
          'NORMAL',
          'Новые → Связались: сохранение и повторное открытие',
          () async {
            await choose('Связались');
            final result = await row();
            contactedStatus = result['status_id'] as String?;
            h.facts.add({'step': h.currentStep, 'id': id, 'row': result});
            expect(contactedStatus, h.fixture['contactStatusId']);
            await open();
            expect(find.text('Связались'), findsWidgets);
          },
        );
        await h.check(
          'REASON',
          'Переход с обязательной причиной предоставляет ввод причины до сохранения',
          () async {
            await open();
            await choose('Закрыт с причиной');
            final after = await row();
            final plain = find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  (w.decoration?.labelText ?? '').toLowerCase().contains(
                    'причин',
                  ),
            );
            h.facts.add({
              'step': h.currentStep,
              'id': id,
              'after': after,
              'reasonFields': plain.evaluate().length,
            });
            expect(
              plain.evaluate().isNotEmpty,
              isTrue,
              reason: 'Configured requiresReason must offer a reason editor',
            );
          },
        );
        await h.check(
          'REOPEN-AFTER-REASON',
          'Повторно открыть карточку после перехода без введённой причины',
          () async {
            await open();
            final after = await row();
            h.facts.add({'step': h.currentStep, 'id': id, 'after': after});
            expect(after['status_id'], contactedStatus);
            expect(find.text('Связались'), findsWidgets);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
