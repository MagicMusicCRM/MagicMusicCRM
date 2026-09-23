import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_cancel_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role actual purchase and lead conversion',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'partial-purchase');
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
                  firstName: 'Покупатель',
                  lastName: 'PURCHASE-$role',
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
                  firstName: 'Покупатель',
                  lastName: 'PURCHASE-$role',
                  phone: '+79995554433',
                  sourceId: source['id'] as String,
                  branchId: branch,
                  status: pipeline.activeStages.first.key,
                  customFields: [],
                );
          final id = created['id'] as String;
          final entityRequestStart = h.requests.length;
          String? studentId = entity == 'student' ? id : null;
          bool closed = false;
          Future<void> open() async {
            final row = entity == 'lead'
                ? Map<String, dynamic>.from(
                    (await crm.getLeadCard(id))['lead'] as Map,
                  )
                : await crm.getStudent(id);
            closed = false;
            await h.mount(
              Scaffold(
                body: ClientCard(
                  key: UniqueKey(),
                  lead: row,
                  entityType: entity,
                  routed: true,
                  initialSection: 'subscriptions',
                  capabilitySnapshot: access,
                  onClose: (_) => closed = true,
                ),
              ),
            );
            await h.waitFor(
              () => find
                  .byKey(const Key('subscription-add'))
                  .evaluate()
                  .isNotEmpty,
              'Subscription section loaded',
            );
            await h.quiet();
            await h.tap(
              find.byKey(const Key('client-section-heading-subscriptions')),
            );
          }

          Future<void> form() async {
            await h.tap(find.byKey(const Key('subscription-add')));
            await h.waitFor(
              () => find.byType(SubscriptionIssueForm).evaluate().isNotEmpty,
              'Purchase form loaded',
            );
            await h.quiet();
          }

          Future<void> assertNoPurchase() async {
            if (entity == 'lead') {
              expect((await crm.getLeadCard(id))['linked_students'], isEmpty);
            } else {
              expect(
                (await crm.getStudentCommerceProjection(
                  id,
                )).student.subscriptions,
                isEmpty,
              );
            }
          }

          await h.check(
            '$entity-OPEN',
            'Карточка → Абонементы → форма продажи',
            () async {
              await open();
              await assertNoPurchase();
              await form();
              expect(
                find.byKey(const Key('subscription-issue-submit')),
                findsOneWidget,
              );
              final amountField = find.widgetWithText(
                TextFormField,
                'Оплачено сейчас',
              );
              final amount = tester
                  .widget<EditableText>(
                    find.descendant(
                      of: amountField,
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text;
              h.facts.add({
                'step': h.currentStep,
                'id': id,
                'entity': entity,
                'paymentInput': amount,
              });
              expect(amount, '8000');
            },
          );
          await h.check(
            '$entity-CANCEL',
            'Отмена продажи сохраняет отсутствие абонемента и не конвертирует лида',
            () async {
              final cancel = find.descendant(
                of: find.byType(SubscriptionIssueForm),
                matching: find.text('Отмена'),
              );
              await h.tap(cancel);
              await h.quiet();
              if (find.text('Не сохранять').evaluate().isNotEmpty) {
                await h.tap(find.text('Не сохранять'));
              }
              await h.waitFor(
                () => find.byType(SubscriptionIssueForm).evaluate().isEmpty,
                'Form closed after cancel',
              );
              await assertNoPurchase();
              expect(closed, isFalse);
              expect(
                h.requests
                    .skip(entityRequestStart)
                    .where(
                      (r) =>
                          r['method'] == 'POST' &&
                          (r['path'] as String).endsWith(
                            '/subscriptions/purchase',
                          ),
                    ),
                isEmpty,
              );
            },
          );
          String? subscriptionId;
          await h.check(
            '$entity-PURCHASE',
            'Частичная оплата 2000 ₽, скидка 10%, доплата 500 ₽, срок и рассрочка сохраняются',
            () async {
              await open();
              await form();
              await h.tap(find.byKey(const Key('subscription-indefinite')));
              await h.tap(
                find.byKey(const Key('subscription-discount-percent')),
              );
              await tester.enterText(
                find.byKey(const Key('subscription-discount-value')),
                '10',
              );
              await tester.enterText(
                find.byKey(const Key('subscription-discount-reason')),
                'AUDIT-DISCOUNT',
              );
              await h.tap(
                find.byKey(const Key('subscription-surcharge-toggle')),
              );
              await tester.enterText(
                find.byKey(const Key('subscription-surcharge-amount')),
                '500',
              );
              await tester.enterText(
                find.byKey(const Key('subscription-surcharge-reason')),
                'AUDIT-SURCHARGE',
              );
              await h.tap(
                find.byKey(const Key('subscription-funding-installment')),
              );
              await tester.enterText(
                find.widgetWithText(TextFormField, 'Оплачено сейчас'),
                '2000',
              );
              await tester.enterText(
                find.byKey(const Key('subscription-purchase-reason')),
                'AUDIT-PARTIAL',
              );
              await tester.pump();
              final start = h.requests.length;
              await h.tap(find.byKey(const Key('subscription-issue-submit')));
              await h.waitFor(
                () => find.byType(SubscriptionIssueForm).evaluate().isEmpty,
                'Successful purchase closes the form',
              );
              await h.quiet();
              if (entity == 'lead') {
                final linked =
                    (await crm.getLeadCard(id))['linked_students'] as List;
                expect(linked, hasLength(1));
                studentId = (linked.single as Map)['id'] as String;
                expect(closed, isFalse);
                await h.waitFor(() {
                  final header = find.byKey(const Key('client-header-name'));
                  if (header.evaluate().isEmpty) return false;
                  final name = tester.widget<Text>(header).data ?? '';
                  return name.contains('Покупатель') &&
                      name.contains('PURCHASE-$role');
                }, 'Converted card shows the student name');
                expect(find.text('Ученик не найден'), findsNothing);
              }
              final commerce = (await crm.getStudentCommerceProjection(
                studentId!,
              )).student;
              expect(commerce.subscriptions, hasLength(1));
              final subscription = commerce.subscriptions.single;
              subscriptionId = subscription.id;
              h.facts.add({
                'step': h.currentStep,
                'id': id,
                'entity': entity,
                'studentId': studentId,
                'subscription': subscription.toLegacyMap(studentId!),
                'actualPaidMinor': subscription.financial.actualPaidMinor
                    .toString(),
                'remainingObligationMinor': subscription
                    .financial
                    .remainingObligationMinor
                    .toString(),
                'closed': closed,
              });
              expect(subscription.status, 'active');
              expect(subscription.units.total, 8);
              expect(subscription.units.paid, inExclusiveRange(0, 8));
              expect(
                subscription.financial.actualPaidMinor,
                BigInt.from(200000),
              );
              expect(
                subscription.financial.remainingObligationMinor,
                BigInt.from(570000),
              );
              final writes = h.requests
                  .skip(start)
                  .where((r) => r['method'] == 'POST')
                  .toList();
              expect(
                writes.where(
                  (r) => (r['path'] as String).endsWith(
                    '/subscriptions/purchase/preview',
                  ),
                ),
                hasLength(1),
              );
              expect(
                writes.where(
                  (r) =>
                      (r['path'] as String).endsWith('/subscriptions/purchase'),
                ),
                hasLength(1),
              );
            },
          );
          if (subscriptionId == null) {
            h.blocked(
              '$entity-REOPEN',
              'Повторное открытие купленного абонемента',
              'Purchase was not confirmed',
            );
          } else {
            await h.check(
              '$entity-REOPEN',
              'Повторно открыть карточку: абонемент и оплата сохранены',
              () async {
                await open();
                expect(find.text('PURCHASE-PACKAGE'), findsWidgets);
                final commerce = (await crm.getStudentCommerceProjection(
                  studentId!,
                )).student;
                expect(commerce.subscriptions.single.id, subscriptionId);
                expect(
                  commerce.subscriptions.single.financial.actualPaidMinor,
                  BigInt.from(200000),
                );
                if (entity == 'lead') {
                  expect(find.text('Лид → Ученик'), findsWidgets);
                }
              },
            );
          }
          if (h.fixture['auditCancellation'] == true &&
              subscriptionId != null) {
            final cancelButton = find.byKey(
              Key('subscription-cancel-$subscriptionId'),
            );
            Future<void> cancellationForm() async {
              await h.tap(cancelButton);
              await h.waitFor(
                () => find
                    .byType(SubscriptionCancellationForm)
                    .evaluate()
                    .isNotEmpty,
                'Cancellation preview rendered',
              );
              await h.quiet();
            }

            Future<void> assertStatus(String status) async {
              final commerce = (await crm.getStudentCommerceProjection(
                studentId!,
              )).student;
              final subscription = commerce.subscriptions.singleWhere(
                (s) => s.id == subscriptionId,
              );
              h.facts.add({
                'step': h.currentStep,
                'id': id,
                'entity': entity,
                'studentId': studentId,
                'subscription': subscription.toLegacyMap(studentId!),
                'status': subscription.status,
              });
              expect(subscription.status, status);
              expect(
                subscription.financial.actualPaidMinor,
                BigInt.from(200000),
                reason: 'The original paid fact remains in history',
              );
            }

            await h.check(
              '$entity-PACKAGE-CANCEL-PREVIEW',
              'Отмена оплаченного абонемента: открыть расчёт возврата',
              () async {
                await open();
                await cancellationForm();
                final preview = tester
                    .widget<SubscriptionCancellationForm>(
                      find.byType(SubscriptionCancellationForm),
                    )
                    .preview;
                expect(
                  preview.financial.recommendedRefundMinor.toString(),
                  '800000',
                );
                await assertStatus('active');
              },
            );
            await h.check(
              '$entity-PACKAGE-CANCEL-ABORT',
              'Назад из расчёта отмены не меняет абонемент',
              () async {
                await h.tap(
                  find.descendant(
                    of: find.byType(SubscriptionCancellationForm),
                    matching: find.text('Назад'),
                  ),
                );
                await h.quiet();
                if (find.text('Не сохранять').evaluate().isNotEmpty) {
                  await h.tap(find.text('Не сохранять'));
                }
                await h.waitFor(
                  () => find
                      .byType(SubscriptionCancellationForm)
                      .evaluate()
                      .isEmpty,
                  'Cancelled preview closed',
                );
                await assertStatus('active');
              },
            );
            await h.check(
              '$entity-PACKAGE-CANCEL-UNCONFIRMED',
              'Отмена без флажка подтверждения не отправляет команду',
              () async {
                await cancellationForm();
                final count = h.requests
                    .where((r) => r['method'] == 'POST')
                    .length;
                await h.tap(
                  find.byKey(const Key('subscription-cancel-submit')),
                );
                await h.quiet();
                expect(
                  find.text('Подтвердите последствия отмены.'),
                  findsOneWidget,
                );
                expect(
                  h.requests.where((r) => r['method'] == 'POST').length,
                  count,
                );
                await assertStatus('active');
              },
            );
            await h.check(
              '$entity-PACKAGE-CANCEL-COMMIT',
              'Выбрать причину и подтвердить отмену оплаченного абонемента',
              () async {
                await h.tap(
                  find.byKey(const Key('subscription-cancel-reason')),
                );
                await h.tap(find.text('Изменилось расписание').last);
                await h.tap(
                  find.byKey(const Key('subscription-cancel-confirmation')),
                );
                await h.tap(
                  find.byKey(const Key('subscription-cancel-submit')),
                );
                await h.waitFor(
                  () => find
                      .byType(SubscriptionCancellationForm)
                      .evaluate()
                      .isEmpty,
                  'Cancellation committed',
                );
                await h.quiet();
                await assertStatus('cancelled');
                expect(cancelButton, findsNothing);
              },
            );
            await h.check(
              '$entity-PACKAGE-CANCEL-REOPEN',
              'Повторное открытие показывает отмену и сохраняет оплаченный факт',
              () async {
                await open();
                await assertStatus('cancelled');
                expect(cancelButton, findsNothing);
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
