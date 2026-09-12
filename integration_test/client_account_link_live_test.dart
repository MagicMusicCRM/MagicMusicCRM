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
      '$role app account linking and subsequent editing',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'account-link');
        await h.initialize(size: const Size(1440, 1100));
        final access = await h.scope.read(capabilitySnapshotProvider.future);
        final crm = h.scope.read(magicCrmServiceProvider);
        final forms = h.scope.read(clientFormsApiProvider);
        final source = (await forms.listSources()).first;
        final account = h.fixture['linkAccount'] as Map;
        final userId = account['userId'] as String;
        for (final entity in ['lead', 'student']) {
          final branch = h.fixture['branchId'] as String;
          final pipeline = await crm.getClientPipeline(
            clientType: entity,
            branchId: branch,
          );
          final created = entity == 'lead'
              ? await forms.createLead(
                  identity: MagicMutationIdentity.create('audit.fixture.lead'),
                  firstName: 'Аккаунт',
                  lastName: 'ACCOUNT-$role',
                  phone: account['phone'] as String,
                  sourceId: source['id'] as String,
                  branchId: branch,
                  status: pipeline.activeStages.first.key,
                  customFields: [],
                )
              : await forms.createStudent(
                  identity: MagicMutationIdentity.create(
                    'audit.fixture.student',
                  ),
                  firstName: 'Аккаунт',
                  lastName: 'ACCOUNT-$role',
                  phone: account['phone'] as String,
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
                  .byKey(const Key('client-app-access'))
                  .evaluate()
                  .isNotEmpty,
              'Account section loaded',
            );
            await h.quiet();
            await h.tap(find.byKey(const Key('client-section-jump-contacts')));
          }

          Future<List<Map<String, dynamic>>> linked() async {
            final items = await crm.getClientLinkedUsers(entity, id);
            h.facts.add({
              'step': h.currentStep,
              'entity': entity,
              'id': id,
              'linked': items,
              'record': await read(),
            });
            return items;
          }

          final linkButton = find.byKey(Key('client-link-user-$userId'));
          await h.check(
            '$entity-OPEN',
            'Открыть доступ в приложение в карточке',
            open,
          );
          await h.check(
            '$entity-CANDIDATE',
            'Показать аккаунт с совпадающим телефоном',
            () async {
              final candidates = await crm.listClientUserCandidates(entity, id);
              expect(candidates.map((row) => row['userId']), contains(userId));
              expect(
                find.descendant(
                  of: find.byKey(const Key('client-app-access')),
                  matching: linkButton,
                ),
                findsOneWidget,
              );
              expect(
                (await linked()).where((row) => row['userId'] == userId),
                isEmpty,
              );
            },
          );
          await h.check(
            '$entity-LINK',
            'Связать аккаунт и убрать его из кандидатов',
            () async {
              final before = await read();
              await h.tap(linkButton);
              await h.quiet();
              expect(
                (await linked()).where((row) => row['userId'] == userId),
                hasLength(1),
              );
              expect(
                (await crm.listClientUserCandidates(
                  entity,
                  id,
                )).where((row) => row['userId'] == userId),
                isEmpty,
              );
              expect(find.byKey(Key('client-link-user-$userId')), findsNothing);
              expect((await read())['version'], (before['version'] as num) + 1);
            },
          );
          await h.check(
            '$entity-EDIT-AFTER-LINK',
            'Сохранить имя после привязки аккаунта без переоткрытия',
            () async {
              await h.tap(
                find.byKey(const Key('client-section-jump-overview')),
              );
              final name = find.widgetWithText(TextFormField, 'Имя');
              await h.tap(name);
              await tester.enterText(name, 'После привязки');
              await tester.pump(const Duration(seconds: 2));
              await h.quiet();
              final after = await read();
              h.facts.add({
                'step': h.currentStep,
                'entity': entity,
                'id': id,
                'record': after,
              });
              expect(after['first_name'], 'После привязки');
              expect(
                find.byWidgetPredicate(
                  (w) =>
                      w is Semantics &&
                      w.properties.label == 'Изменения сохранены',
                ),
                findsWidgets,
              );
            },
          );
          await h.check(
            '$entity-REOPEN',
            'Привязка аккаунта видна после повторного открытия',
            () async {
              await open();
              expect(
                (await linked()).where((row) => row['userId'] == userId),
                hasLength(1),
              );
              expect(
                find.descendant(
                  of: find.byKey(const Key('client-app-access')),
                  matching: find.text('Связанный аккаунт'),
                ),
                findsOneWidget,
              );
              expect(linkButton, findsNothing);
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
