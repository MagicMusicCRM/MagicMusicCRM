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
      '$role family and comments persist',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'collaboration');
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
                  firstName: 'Связи',
                  lastName: 'COLLAB-$role',
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
                  firstName: 'Связи',
                  lastName: 'COLLAB-$role',
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
              'Card loaded',
            );
            await h.quiet();
          }

          Future<Map<String, dynamic>> family() async {
            final value = await crm.getFamilyForEntity(
              entityType: entity,
              entityId: id,
            );
            h.facts.add({
              'step': h.currentStep,
              'entity': entity,
              'id': id,
              'family': value,
            });
            return value;
          }

          Future<void> familySection() =>
              h.tap(find.byKey(const Key('client-section-heading-contacts')));
          Future<void> addSheet() async {
            await familySection();
            await h.tap(find.widgetWithText(TextButton, 'Добавить'));
            await h.waitFor(
              () => find.text('Добавить участника').evaluate().isNotEmpty,
              'Family sheet opened',
            );
          }

          await h.check(
            '$entity-OPEN',
            'Открыть карточку для семьи и комментариев',
            open,
          );
          await h.check(
            '$entity-FAMILY-CANCEL',
            'Отмена добавления не создаёт семью',
            () async {
              expect((await family())['family'], isNull);
              await addSheet();
              await h.tap(find.widgetWithText(TextButton, 'Отмена'));
              await h.quiet();
              expect((await family())['family'], isNull);
            },
          );
          String? memberId;
          await h.check(
            '$entity-FAMILY-ADD',
            'Добавить текущую запись как родителя и основной контакт',
            () async {
              await addSheet();
              await h.tap(
                find.widgetWithText(CheckboxListTile, 'Основной контакт'),
              );
              await h.tap(find.widgetWithText(FilledButton, 'Добавить'));
              await h.quiet();
              final value = await family();
              final members = value['members'] as List;
              expect(members, hasLength(1));
              final member = members.single as Map;
              expect(member['entity_id'], id);
              expect(member['entity_type'], entity);
              expect(member['role'], 'parent');
              expect(member['is_primary_contact'], isTrue);
              memberId = member['id'] as String;
            },
          );
          if (memberId != null) {
            await h.check(
              '$entity-FAMILY-REOPEN',
              'Участник семьи остаётся после повторного открытия',
              () async {
                await open();
                await familySection();
                expect((await family())['members'], hasLength(1));
                expect(
                  find.byKey(Key('family-primary-payer-$memberId')),
                  findsOneWidget,
                );
              },
            );
            await h.check(
              '$entity-FAMILY-PAYER',
              'Назначить участника основным плательщиком',
              () async {
                await h.tap(find.byKey(Key('family-primary-payer-$memberId')));
                await h.quiet();
                expect(
                  ((await family())['family']
                      as Map)['primary_payer_member_id'],
                  memberId,
                );
                await open();
                await familySection();
                expect(
                  find.byKey(Key('family-primary-payer-$memberId')),
                  findsNothing,
                );
              },
            );
            Future<void> removeDialog() async {
              await h.tap(find.byTooltip('Удалить участника'));
              await h.waitFor(
                () => find.text('Удалить участника?').evaluate().isNotEmpty,
                'Unlink confirmation opened',
              );
            }

            await h.check(
              '$entity-FAMILY-REMOVE-CANCEL',
              'Отмена удаления сохраняет связь семьи',
              () async {
                await removeDialog();
                await h.tap(find.widgetWithText(TextButton, 'Отмена'));
                await h.quiet();
                expect((await family())['members'], hasLength(1));
              },
            );
            await h.check(
              '$entity-FAMILY-REMOVE',
              'Удалить связь семьи, сохранив карточку клиента',
              () async {
                await removeDialog();
                await h.tap(find.widgetWithText(FilledButton, 'Удалить'));
                await h.quiet();
                expect((await family())['members'], isEmpty);
                expect((await read())['id'], id);
                await open();
                await familySection();
                expect(find.byTooltip('Удалить участника'), findsNothing);
              },
            );
          } else {
            for (final suffix in [
              'REOPEN',
              'PAYER',
              'REMOVE-CANCEL',
              'REMOVE',
            ]) {
              h.blocked(
                '$entity-FAMILY-$suffix',
                'Зависимая проверка семьи',
                '$entity-FAMILY-ADD',
              );
            }
          }
          Future<void> commentsSection() =>
              h.tap(find.byKey(const Key('client-section-heading-history_tasks')));
          final commentField = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == 'Написать комментарий...',
          );
          Future<List<Map<String, dynamic>>> comments() async {
            final value = await crm.listComments(
              entityType: entity,
              entityId: id,
            );
            h.facts.add({
              'step': h.currentStep,
              'entity': entity,
              'id': id,
              'comments': value,
            });
            return value;
          }

          Future<void> send(String body) async {
            await tester.ensureVisible(commentField);
            // Native focus can be lost to the send button while the test
            // binding still remembers this EditableText. Focus it explicitly.
            await h.tap(commentField);
            await tester.enterText(commentField, body);
            await tester.pump();
            expect(
              tester.widget<TextField>(commentField).controller!.text,
              body,
              reason: 'The input event must reach the actual product editor',
            );
            await h.tap(find.byTooltip('Отправить комментарий'));
            await h.quiet();
            if (body.trim().isNotEmpty) {
              expect(
                tester.widget<TextField>(commentField).controller!.text,
                isEmpty,
              );
            }
          }

          await h.check(
            '$entity-COMMENT-EMPTY',
            'Пустой комментарий не отправляется',
            () async {
              await open();
              await commentsSection();
              final before = h.requests.length;
              await send('   ');
              expect(
                h.requests
                    .skip(before)
                    .where(
                      (r) =>
                          r['method'] == 'POST' &&
                          r['path'].toString().contains('/comments'),
                    ),
                isEmpty,
              );
              expect(await comments(), isEmpty);
            },
          );
          final body = 'Комментарий $role $entity';
          await h.check(
            '$entity-COMMENT-CREATE',
            'Сохранить обычный комментарий и проверить ответ API',
            () async {
              await send(body);
              final rows = await comments();
              expect(rows, hasLength(1));
              expect(rows.single['body'], body);
              if (entity == 'student') {
                expect(rows.single['kind'], 'admin_comment');
              }
            },
          );
          await h.check(
            '$entity-COMMENT-REOPEN',
            'Комментарий виден после повторного открытия карточки',
            () async {
              await open();
              await commentsSection();
              expect(find.text(body), findsWidgets);
              expect((await comments()).single['body'], body);
            },
          );
          if (entity == 'student') {
            for (final visible in [true, false]) {
              await h.check(
                '$entity-COMMENT-${visible ? "SHARE" : "UNSHARE"}',
                visible
                    ? 'Показать обычный комментарий преподавателю'
                    : 'Скрыть обычный комментарий от преподавателя',
                () async {
                  final before = (await comments()).singleWhere(
                    (row) => row['body'] == body,
                  );
                  await h.tap(
                    find.byKey(ValueKey('comment-share-${before['id']}')),
                  );
                  await h.quiet();
                  final after = (await comments()).singleWhere(
                    (row) => row['id'] == before['id'],
                  );
                  expect(after['shared_with_teacher'], visible);
                  expect(after['version'], (before['version'] as int) + 1);
                  expect(after['body'], body);
                  expect(after['kind'], 'admin_comment');
                  await open();
                  await commentsSection();
                  final control = find.byKey(
                    ValueKey('comment-share-${before['id']}'),
                  );
                  expect(
                    find.descendant(
                      of: control,
                      matching: find.text(
                        visible
                            ? 'Виден преподавателю'
                            : 'Показать преподавателю',
                      ),
                    ),
                    findsOneWidget,
                  );
                },
              );
            }
            await h.check(
              '$entity-COMMENT-SECOND',
              'Создать второй унифицированный комментарий',
              () async {
                await send('Педагогу $role');
                final rows = await comments();
                expect(rows, hasLength(2));
                expect(
                  rows.singleWhere(
                    (row) => row['body'] == 'Педагогу $role',
                  )['kind'],
                  'admin_comment',
                );
                await open();
                await commentsSection();
                expect(find.text('Педагогу $role'), findsWidgets);
              },
            );
          }
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
