import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_cancel_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';

import 'live_audit_harness.dart';
import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role actual purchase and lead conversion',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'partial-purchase');
        await h.initialize(size: const Size(1440, 1100));
        final cycle = h.fixture['auditInstallmentCycle'] == true;
        final integratedLeadId = role == 'admin'
            ? h.fixture['integratedLeadId'] as String?
            : null;
        final access = await h.scope.read(capabilitySnapshotProvider.future);
        final crm = h.scope.read(magicCrmServiceProvider);
        final restartStudentId = h.fixture['cycleRestartStudentId']?.toString();
        if (restartStudentId != null) {
          if (role == 'admin') {
            await h.check(
              'RESTART',
              'Новый Windows процесс видит оплату и наступивший срок',
              () async {
                final row = await crm.getStudent(restartStudentId);
                await h.mount(
                  Scaffold(
                    body: ClientCard(
                      key: UniqueKey(),
                      lead: row,
                      entityType: 'student',
                      routed: true,
                      initialSection: 'subscriptions',
                      capabilitySnapshot: access,
                      onClose: (_) {},
                    ),
                  ),
                );
                await h.waitFor(
                  () => find
                      .byKey(const Key('subscription-add'))
                      .evaluate()
                      .isNotEmpty,
                  'Restarted card loaded',
                );
                await h.quiet();
                await h.tap(
                  find.byKey(const Key('client-section-heading-subscriptions')),
                );
                expect(find.textContaining('срок наступил:'), findsWidgets);
                await h.tap(
                  find.byKey(const Key('payment-installments-expansion')),
                );
                expect(
                  find.textContaining('Первоначальный взнос · Оплачен'),
                  findsOneWidget,
                );
                expect(
                  find.textContaining('Срок после расходования объёма'),
                  findsOneWidget,
                );
                final subscription = (await crm.getStudentCommerceProjection(
                  restartStudentId,
                )).student.subscriptions.single;
                expect(subscription.units.used, 2);
                expect(subscription.installments.single.dueKind, 'actual');
              },
            );
          }
          await h.finish();
          return;
        }
        final forms = h.scope.read(clientFormsApiProvider);
        final source = (await forms.listSources()).first;
        String? cycleStudentId;
        String? cycleSubscriptionId;
        for (final entity in ['lead', 'student']) {
          final branch = h.fixture['branchId'] as String;
          final pipeline = await crm.getClientPipeline(
            clientType: entity,
            branchId: branch,
          );
          final created = entity == 'lead' && integratedLeadId != null
              ? Map<String, dynamic>.from(
                  (await crm.getLeadCard(integratedLeadId))['lead'] as Map,
                )
              : entity == 'lead'
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
            await h.tap(find.byKey(const Key('subscription-package-selector')));
            await h.tap(
              find.widgetWithText(MenuItemButton, 'PURCHASE-PACKAGE').last,
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
              expect(amount, cycle ? '14400' : '8000');
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
            cycle
                ? '14400 ₽ / 4 занятия: первый платёж 7200 ₽ и один прогнозный 7200 ₽'
                : 'Частичная оплата 2000 ₽, скидка 10%, доплата 500 ₽, срок и рассрочка сохраняются',
            () async {
              await open();
              await form();
              await h.tap(find.byKey(const Key('subscription-indefinite')));
              if (cycle) {
                // Use a past date inside the purchased period regardless of the run hour.
                await h.tap(
                  find.widgetWithText(TextFormField, 'Начало действия'),
                );
                final picker = find.byType(DatePickerDialog);
                final locale = MaterialLocalizations.of(tester.element(picker));
                await h.tap(find.byTooltip(locale.inputDateModeButtonLabel));
                await tester.enterText(
                  find.descendant(of: picker, matching: find.byType(TextField)),
                  locale.formatCompactDate(
                    DateTime.now().subtract(const Duration(days: 2)),
                  ),
                );
                await h.tap(
                  find.descendant(
                    of: picker,
                    matching: find.text(locale.okButtonLabel),
                  ),
                );
              }
              if (!cycle) {
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
              }
              await h.tap(
                find.byKey(const Key('subscription-funding-installment')),
              );
              if (cycle) {
                final rejectedAt = h.requests.length;
                await tester.enterText(
                  find.widgetWithText(TextFormField, 'Оплачено сейчас'),
                  '-1',
                );
                await h.tap(find.byKey(const Key('subscription-issue-submit')));
                expect(find.byType(SubscriptionIssueForm), findsOneWidget);
                expect(
                  h.requests
                      .skip(rejectedAt)
                      .where(
                        (request) =>
                            request['method'] == 'POST' &&
                            (request['path'] as String).endsWith(
                              '/subscriptions/purchase',
                            ),
                      ),
                  isEmpty,
                );
                expect(find.text('-1'), findsWidgets);
              }
              final paymentField = find.widgetWithText(
                TextFormField,
                'Оплачено сейчас',
              );
              expect(
                tester.widget<TextFormField>(paymentField).enabled,
                isTrue,
              );
              await h.tap(paymentField);
              await tester.enterText(
                find.descendant(
                  of: paymentField,
                  matching: find.byType(EditableText),
                ),
                cycle ? '7200' : '2000',
              );
              await h.quiet();
              expect(
                tester
                    .widget<EditableText>(
                      find.descendant(
                        of: paymentField,
                        matching: find.byType(EditableText),
                      ),
                    )
                    .controller
                    .text,
                cycle ? '7200' : '2000',
              );
              await tester.enterText(
                find.byKey(const Key('subscription-purchase-reason')),
                'AUDIT-PARTIAL',
              );
              await h.quiet();
              if (cycle) {
                await captureEvidence(
                  tester,
                  'installment-preview-$role-$entity',
                );
                expect(
                  find.byKey(const Key('subscription-installment-initial')),
                  findsOneWidget,
                );
                expect(
                  find.byKey(const Key('subscription-installment-future-0')),
                  findsOneWidget,
                );
                expect(
                  find.byKey(const Key('subscription-installment-future-1')),
                  findsNothing,
                );
                expect(find.textContaining('Прогноз:'), findsOneWidget);
                expect(find.textContaining('Итого по графику'), findsOneWidget);
              }
              final start = h.requests.length;
              final submit = find.byKey(const Key('subscription-issue-submit'));
              if (cycle) {
                await tester.ensureVisible(submit);
                await tester.tap(submit);
                await tester.tap(submit);
                await tester.pump(const Duration(milliseconds: 300));
              } else {
                await h.tap(submit);
              }
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
                  return integratedLeadId != null
                      ? name.contains('ST02') && name.contains('Входящий')
                      : name.contains('Покупатель') &&
                            name.contains('PURCHASE-$role');
                }, 'Converted card shows the student name');
                expect(find.text('Ученик не найден'), findsNothing);
                if (integratedLeadId != null) {
                  final trialId = h.fixture['integratedTrialId'] as String;
                  final trial = (await crm.listLessons(
                    lessonId: trialId,
                  )).single;
                  expect(trial['student_id'], studentId);
                  expect(trial['lead_id'], isNull);
                  await h.waitFor(
                    () => find
                        .byKey(const Key('client-next-lesson'))
                        .evaluate()
                        .isNotEmpty,
                    'Converted student retains the moved trial',
                  );
                  await h.tap(find.byKey(const Key('client-next-lesson')));
                  await h.quiet();
                  expect(
                    tester
                        .widget<CreateLessonDialog>(
                          find.byType(CreateLessonDialog),
                        )
                        .lesson!['id'],
                    trialId,
                  );
                  await captureEvidence(tester, 'integrated-converted-trial');
                  await h.tap(
                    find.descendant(
                      of: find.byType(CreateLessonDialog),
                      matching: find.widgetWithText(TextButton, 'Отмена'),
                    ),
                  );
                  await h.quiet();
                  h.facts.add({
                    'step': 'INTEGRATED-CONVERTED-TRIAL',
                    'lessonId': trialId,
                    'studentId': studentId,
                  });
                }
              }
              final commerce = (await crm.getStudentCommerceProjection(
                studentId!,
              )).student;
              expect(commerce.subscriptions, hasLength(1));
              final subscription = commerce.subscriptions.single;
              subscriptionId = subscription.id;
              if (cycle &&
                  entity == (integratedLeadId == null ? 'student' : 'lead')) {
                cycleStudentId = studentId;
                cycleSubscriptionId = subscription.id;
              }
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
              expect(subscription.units.total, cycle ? 4 : 8);
              expect(
                subscription.units.paid,
                cycle ? 2 : inExclusiveRange(0, 8),
              );
              expect(
                subscription.financial.actualPaidMinor,
                BigInt.from(cycle ? 720000 : 200000),
              );
              expect(
                subscription.financial.remainingObligationMinor,
                BigInt.from(cycle ? 720000 : 570000),
              );
              if (cycle) {
                expect(subscription.installments, hasLength(1));
                expect(
                  subscription.installments.single.amountMinor,
                  BigInt.from(720000),
                );
                expect(subscription.installments.single.dueKind, 'forecast');
                expect(
                  commerce.accounts.every(
                    (account) => account.balanceMinor == BigInt.zero,
                  ),
                  isTrue,
                );
              }
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
                  BigInt.from(cycle ? 720000 : 200000),
                );
                if (cycle) {
                  expect(
                    find.textContaining('Остаток к оплате:'),
                    findsWidgets,
                  );
                  expect(find.textContaining('Долг: 7 200'), findsNothing);
                  await h.tap(
                    find.byKey(const Key('payment-installments-expansion')),
                  );
                  expect(
                    find.byKey(
                      Key('payment-installment-initial-$subscriptionId'),
                    ),
                    findsOneWidget,
                  );
                  expect(
                    find.textContaining('Первоначальный взнос · Оплачен'),
                    findsOneWidget,
                  );
                  expect(find.textContaining('Прогноз:'), findsOneWidget);
                }
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
        if (cycle && role == 'admin' && cycleStudentId != null) {
          final studentId = cycleStudentId!;
          final subscriptionId = cycleSubscriptionId!;
          Future<String?> createPaidLesson(
            int hour, {
            bool mayReject = false,
          }) async {
            final before = (await crm.listLessons(
              studentId: studentId,
              includeClosed: true,
            )).map((lesson) => lesson['id']?.toString()).toSet();
            final today = DateTime.now().toLocal();
            final scheduled = DateTime(
              today.year,
              today.month,
              today.day - 1,
              hour,
            );
            await h.mount(
              Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => CreateLessonDialog.show(
                      context,
                      initialDate: scheduled,
                      clientType: 'student',
                      clientId: studentId,
                      clientName: 'Покупатель PURCHASE-admin',
                      initialBranchId: h.fixture['branchId'] as String,
                      initialRoomId: h.fixture['roomId'] as String,
                    ),
                    child: const Text('Записать'),
                  ),
                ),
              ),
            );
            await h.tap(find.text('Записать'));
            final teacher = find.byKey(const Key('lesson-teacher-field'));
            await h.waitFor(
              () =>
                  teacher.evaluate().isNotEmpty &&
                  tester.widget<SearchablePickerField>(teacher).enabled,
              'Teacher availability loaded before selection',
            );
            await h.tap(teacher);
            await tester.enterText(
              find.descendant(of: teacher, matching: find.byType(TextField)),
              'Teacher1',
            );
            await h.quiet();
            await h.tap(
              find.widgetWithText(MenuItemButton, 'Teacher1 HTTP test').last,
            );
            final source = find.byKey(
              ValueKey('lesson-client-charge-type-$studentId'),
            );
            expect(source, findsOneWidget);
            final subscription = find.byKey(
              ValueKey('lesson-client-subscription-$studentId'),
            );
            await h.quiet();
            if (mayReject && subscription.evaluate().isEmpty) return null;
            await h.waitFor(
              () => subscription.evaluate().isNotEmpty,
              'Subscription funding loaded',
            );
            final selected = tester
                .widget<SearchablePickerField>(subscription)
                .selectedId;
            if (mayReject && selected != subscriptionId) return null;
            expect(selected, subscriptionId);
            await h.tap(find.text('Создать'));
            await h.quiet();
            for (var attempt = 0; attempt < 60; attempt++) {
              final rows = await crm.listLessons(
                studentId: studentId,
                includeClosed: true,
              );
              final added = rows
                  .where((row) => !before.contains(row['id']?.toString()))
                  .toList();
              if (added.isNotEmpty) return added.single['id'] as String;
              if (mayReject) return null;
              await tester.pump(const Duration(milliseconds: 300));
            }
            throw StateError('Lesson was not saved through the UI');
          }

          Future<void> waitCompleted(String lessonId) async {
            for (var attempt = 0; attempt < 80; attempt++) {
              final row = (await crm.listLessons(
                lessonId: lessonId,
                limit: 1,
              )).single;
              if (row['status'] == 'completed') return;
              await tester.pump(const Duration(milliseconds: 300));
            }
            throw StateError('Completion worker did not settle $lessonId');
          }

          String? firstLessonId;
          String? secondLessonId;
          await h.check(
            'PAID-LESSON-1',
            'Первый урок проводится через UI; взнос остаётся прогнозом',
            () async {
              firstLessonId = await createPaidLesson(9);
              await waitCompleted(firstLessonId!);
              final subscription =
                  (await crm.getStudentCommerceProjection(studentId))
                      .student
                      .subscriptions
                      .singleWhere((item) => item.id == subscriptionId);
              expect(subscription.units.used, 1);
              expect(subscription.units.paid, 2);
              expect(subscription.installments.single.dueKind, 'forecast');
              h.facts.add({
                'step': h.currentStep,
                'lessonId': firstLessonId,
                'used': subscription.units.used,
                'dueKind': subscription.installments.single.dueKind,
              });
            },
          );
          await h.check(
            'PAID-LESSON-2',
            'Второй урок проводится через UI; worker фиксирует один срок',
            () async {
              secondLessonId = await createPaidLesson(10);
              await waitCompleted(secondLessonId!);
              for (var attempt = 0; attempt < 50; attempt++) {
                final subscription =
                    (await crm.getStudentCommerceProjection(studentId))
                        .student
                        .subscriptions
                        .singleWhere((item) => item.id == subscriptionId);
                if (subscription.installments.single.dueKind == 'actual') {
                  expect(subscription.units.used, 2);
                  expect(subscription.units.available, 0);
                  h.facts.add({
                    'step': h.currentStep,
                    'lessonIds': [firstLessonId, secondLessonId],
                    'used': subscription.units.used,
                    'dueKind': 'actual',
                  });
                  return;
                }
                await tester.pump(const Duration(milliseconds: 300));
              }
              throw StateError(
                'Installment due worker did not record the second consumption',
              );
            },
          );
          await h.check(
            'PAID-LESSON-3-GUARD',
            'Третий урок через UI не создаёт неоплаченное списание',
            () async {
              final thirdLessonId = await createPaidLesson(11, mayReject: true);
              if (thirdLessonId != null) {
                for (var attempt = 0; attempt < 30; attempt++) {
                  final row = (await crm.listLessons(
                    lessonId: thirdLessonId,
                    limit: 1,
                  )).single;
                  if (row['status'] == 'settlement_pending' ||
                      row['status'] == 'review_required') {
                    break;
                  }
                  await tester.pump(const Duration(milliseconds: 300));
                }
                final row = (await crm.listLessons(
                  lessonId: thirdLessonId,
                  limit: 1,
                )).single;
                expect(
                  row['status'],
                  anyOf('settlement_pending', 'review_required'),
                );
              }
              final subscription =
                  (await crm.getStudentCommerceProjection(studentId))
                      .student
                      .subscriptions
                      .singleWhere((item) => item.id == subscriptionId);
              expect(subscription.units.used, 2);
              expect(
                subscription.financial.actualPaidMinor,
                BigInt.from(720000),
              );
              h.facts.add({
                'step': h.currentStep,
                'thirdLessonId': thirdLessonId,
                'used': subscription.units.used,
              });
            },
            expectedHttpErrors: const [
              (
                method: 'POST',
                path: '/api/crm/lessons',
                status: 400,
                maxCount: 1,
              ),
              (
                method: 'POST',
                path: '/api/crm/lessons',
                status: 409,
                maxCount: 1,
              ),
              (
                method: 'POST',
                path: '/api/crm/lessons',
                status: 422,
                maxCount: 1,
              ),
            ],
          );
          await h.check(
            'PAID-LESSON-REOPEN',
            'Карточка повторно показывает наступивший срок и оплату',
            () async {
              final row = await crm.getStudent(studentId);
              await h.mount(
                Scaffold(
                  body: ClientCard(
                    key: UniqueKey(),
                    lead: row,
                    entityType: 'student',
                    routed: true,
                    initialSection: 'subscriptions',
                    capabilitySnapshot: access,
                    onClose: (_) {},
                  ),
                ),
              );
              await h.waitFor(
                () => find
                    .byKey(const Key('subscription-add'))
                    .evaluate()
                    .isNotEmpty,
                'Reopened student card loaded',
              );
              await h.quiet();
              await h.tap(
                find.byKey(const Key('client-section-heading-subscriptions')),
              );
              expect(find.textContaining('срок наступил:'), findsWidgets);
              await h.tap(
                find.byKey(const Key('payment-installments-expansion')),
              );
              expect(
                find.byKey(Key('payment-installment-initial-$subscriptionId')),
                findsOneWidget,
              );
              expect(
                find.textContaining('Срок после расходования объёма'),
                findsOneWidget,
              );
            },
          );
          await h.check(
            'PAID-LESSON-CALENDAR',
            'Оба проведённых урока видны в связанном календаре',
            () async {
              final lesson = (await crm.listLessons(
                lessonId: firstLessonId,
                limit: 1,
              )).single;
              await h.mount(
                Scaffold(
                  body: ScheduleWidget(
                    initialBranchId: h.fixture['branchId'] as String,
                    initialViewState: ContextViewState(
                      date: DateTime.parse(
                        lesson['scheduled_at'] as String,
                      ).toLocal(),
                      filters: {
                        'view': 'day',
                        'branchId': h.fixture['branchId'] as String,
                      },
                    ),
                  ),
                ),
              );
              await h.quiet();
              expect(
                find.byKey(Key('schedule-lesson-$firstLessonId')),
                findsWidgets,
              );
              expect(
                find.byKey(Key('schedule-lesson-$secondLessonId')),
                findsWidgets,
              );
            },
          );
        }
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
