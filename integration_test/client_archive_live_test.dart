import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_api.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role archive controls and persistence',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'archive');
        await h.initialize(size: const Size(1440, 1100));
        final access = await h.scope.read(capabilitySnapshotProvider.future);
        final crm = h.scope.read(magicCrmServiceProvider);
        final cards = h.scope.read(clientCardApiProvider);
        final forms = h.scope.read(clientFormsApiProvider);
        final source = (await forms.listSources()).first;
        final pipeline = await crm.getClientPipeline(
          clientType: 'lead',
          branchId: h.fixture['branchId'] as String,
        );
        final lead = await forms.createLead(
          identity: MagicMutationIdentity.create('audit.fixture.lead'),
          firstName: 'Архив',
          lastName: 'ARCHIVE-$role',
          phone: '+79993334455',
          sourceId: source['id'] as String,
          branchId: h.fixture['branchId'] as String,
          status: pipeline.activeStages.first.key,
          customFields: [],
        );
        for (final entity in ['lead', 'student']) {
          final id = entity == 'lead'
              ? lead['id'] as String
              : h.fixture['studentId'] as String;
          bool closed = false;
          Map<String, dynamic>? preview;
          Future<void> open() async {
            final row = entity == 'lead'
                ? Map<String, dynamic>.from(
                    (await crm.getLeadCard(id))['lead'] as Map,
                  )
                : await crm.getStudent(id);
            await h.mount(
              Scaffold(
                body: ClientCard(
                  key: UniqueKey(),
                  lead: row,
                  entityType: entity,
                  routed: true,
                  capabilitySnapshot: access,
                  onClose: (value) => closed = value == true,
                ),
              ),
            );
            await h.waitFor(
              () => find
                  .widgetWithText(TextFormField, 'Имя')
                  .evaluate()
                  .isNotEmpty,
              'Card loaded',
            );
            await h.quiet();
          }

          await h.check(
            '$entity-ACCESS',
            'Доступность архивирования в настоящей карточке',
            () async {
              await open();
              expect(
                find.byKey(const ValueKey('client-archive-open')),
                role == 'director' ? findsOneWidget : findsNothing,
              );
              h.facts.add({
                'step': h.currentStep,
                'entity': entity,
                'id': id,
                'archiveVisible': role == 'director',
              });
            },
          );
          if (role != 'director') continue;
          await h.check(
            '$entity-PREVIEW-CANCEL',
            'Предпросмотр → отмена сохраняет активную карточку',
            () async {
              preview = await cards.previewArchive(
                entityType: entity,
                entityId: id,
              );
              expect(preview!['tombstone'], false);
              await h.tap(find.byKey(const ValueKey('client-archive-open')));
              await h.waitFor(
                () => find
                    .byKey(const ValueKey('client-archive-preview'))
                    .evaluate()
                    .isNotEmpty,
                'Preview dialog',
              );
              if (entity == 'student') {
                expect(
                  find.text(
                    'Активные абонементы не будут отменены или удалены.',
                  ),
                  findsOneWidget,
                );
              }
              await h.tap(find.widgetWithText(TextButton, 'Отмена'));
              await h.waitFor(
                () => find
                    .byKey(const ValueKey('client-archive-preview'))
                    .evaluate()
                    .isEmpty,
                'Preview cancelled',
              );
              final after = await cards.previewArchive(
                entityType: entity,
                entityId: id,
              );
              expect(after['tombstone'], false);
              expect(after['version'], preview!['version']);
              expect(closed, false);
            },
          );
          if (h.steps.last['status'] != 'PASS') {
            h.blocked(
              '$entity-COMMIT',
              'Архивирование и readback',
              '$entity-PREVIEW-CANCEL',
            );
            continue;
          }
          await h.check(
            '$entity-COMMIT',
            'Подтверждение → архив → серверный readback',
            () async {
              await h.tap(find.byKey(const ValueKey('client-archive-open')));
              await h.waitFor(
                () => find
                    .byKey(const ValueKey('client-archive-preview'))
                    .evaluate()
                    .isNotEmpty,
                'Fresh preview',
              );
              await h.tap(find.byKey(const ValueKey('client-archive-confirm')));
              await h.waitFor(
                () => closed,
                'Card closes after committed archive',
              );
              final after = await cards.previewArchive(
                entityType: entity,
                entityId: id,
              );
              h.facts.add({
                'step': h.currentStep,
                'entity': entity,
                'id': id,
                'before': preview,
                'after': after,
              });
              expect(after['tombstone'], true);
              expect(
                after['version'],
                (preview!['version'] as num).toInt() + 1,
              );
            },
          );
          if (h.steps.last['status'] != 'PASS') {
            h.blocked(
              '$entity-REPLAY',
              'Повтор команды архивирования',
              '$entity-COMMIT',
            );
            continue;
          }
          await h.check(
            '$entity-REPLAY',
            'Повтор HTTP-команды возвращает тот же архив без нового изменения',
            () async {
              final again = await cards.archive(
                entityType: entity,
                entityId: id,
                expectedVersion: (preview!['version'] as num).toInt(),
                reason: 'crm.client.archive.inactive',
              );
              expect(again['replayed'], true);
              expect(
                (again['tombstone'] as Map)['version'],
                (preview!['version'] as num).toInt() + 1,
              );
              h.facts.add({
                'step': h.currentStep,
                'entity': entity,
                'id': id,
                'replayed': again['replayed'],
              });
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
