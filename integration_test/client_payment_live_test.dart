import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_payment_form.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director']) {
    testWidgets(
      '$role payment statuses and reversal persistence',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'client-payment');
        await h.initialize(size: const Size(1440, 1300));
        final access = await h.scope.read(capabilitySnapshotProvider.future),
            crm = h.scope.read(magicCrmServiceProvider),
            forms = h.scope.read(clientFormsApiProvider);
        final branch = h.fixture['branchId'] as String,
            source = (await forms.listSources()).first;
        final pipeline = await crm.getClientPipeline(
          clientType: 'student',
          branchId: branch,
        );
        final created = await forms.createStudent(
          identity: MagicMutationIdentity.create('audit.fixture.student'),
          firstName: 'Оплата',
          lastName: 'PAYMENT-$role',
          phone: '+79995556677',
          sourceId: source['id'] as String,
          branchId: branch,
          status: pipeline.activeStages.first.key,
          customFields: [],
        );
        final id = created['id'] as String;
        String? paymentId;
        Finder key(String value) => find.byKey(ValueKey(value));
        Future<void> fill(String value, String text) async {
          await h.tap(key(value));
          await tester.enterText(key(value), text);
          await tester.pump();
        }

        Future<CommerceStudent> read() async {
          final value = (await crm.getStudentCommerceProjection(id)).student;
          h.facts.add({
            'step': h.currentStep,
            'studentId': id,
            'movements': value.movements
                .map(
                  (m) => {
                    'id': m.id,
                    'status': m.status,
                    'amountMinor': m.amountMinor.toString(),
                  },
                )
                .toList(),
            'accounts': value.accounts
                .map(
                  (a) => {
                    'balanceMinor': a.balanceMinor.toString(),
                    'pendingMinor': a.pendingMinor.toString(),
                    'actualPaymentsMinor': a.actualPaymentsMinor.toString(),
                  },
                )
                .toList(),
          });
          return value;
        }

        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            Scaffold(
              body: ClientCard(
                key: UniqueKey(),
                lead: await crm.getStudent(id),
                entityType: 'student',
                routed: true,
                initialSection: 'payments',
                capabilitySnapshot: access,
                onClose: (_) {},
              ),
            ),
          );
          await h.quiet();
          await h.tap(key('client-section-jump-payments'));
          await h.quiet();
        }

        Future<void> form() async {
          await h.tap(key('open-payment-form'));
          await h.quiet();
          expect(find.byType(ClientPaymentForm), findsOneWidget);
        }

        Future<void> movement(String status) async {
          final rows = (await read()).movements;
          expect(rows.where((r) => r.id == paymentId).single.status, status);
        }

        Future<void> menu(String text) async {
          if (key('payment-status-$paymentId').evaluate().isEmpty) {
            await h.tap(key('payment-movements-expansion'));
          }
          await h.tap(key('payment-status-$paymentId'));
          await h.tap(find.text(text).last);
          await h.quiet();
        }

        await h.check(
          'OPEN',
          'Карточка ученика → Оплаты → реальная форма',
          () async {
            await open();
            expect((await read()).movements, isEmpty);
            await form();
          },
        );
        await h.check(
          'VALIDATION',
          'Пустая, нулевая и дробная с тремя знаками сумма не сохраняются',
          () async {
            for (final amount in ['', '0', '1.001']) {
              await fill('payment-amount', amount);
              await h.tap(key('payment-submit'));
              await h.quiet();
              expect(find.byType(ClientPaymentForm), findsOneWidget);
              expect((await read()).movements, isEmpty);
            }
          },
        );
        await h.check(
          'CANCEL',
          'Отмена заполненной оплаты не создаёт движение',
          () async {
            await fill('payment-amount', '1234,50');
            await h.tap(find.byTooltip('Закрыть форму оплаты'));
            expect((await read()).movements, isEmpty);
          },
        );
        await h.check(
          'CREATE-PENDING',
          'Создать ожидающую подтверждения оплату 1234,50 ₽',
          () async {
            await form();
            await fill('payment-amount', '1234,50');
            await h.tap(key('payment-submit'));
            await h.quiet();
            final rows = (await read()).movements;
            expect(rows.length, 1);
            paymentId = rows.single.id;
            expect(rows.single.status, 'posted_pending');
            expect(rows.single.amountMinor, BigInt.from(123450));
          },
        );
        await h.check(
          'REOPEN',
          'Повторное открытие сохраняет ожидающую оплату',
          () async {
            await open();
            await movement('posted_pending');
          },
        );
        await h.check(
          'TRANSITION-CANCEL',
          'Отмена смены статуса сохраняет ожидающую оплату',
          () async {
            await menu('Отметить как долг');
            await fill('payment-transition-reason', 'CANCEL');
            await h.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
            await movement('posted_pending');
          },
        );
        await h.check(
          'UNPAID',
          'Переход в долг требует причину и сохраняется',
          () async {
            await menu('Отметить как долг');
            await h.tap(key('payment-transition-submit'));
            expect(
              find.text('Укажите причину изменения статуса'),
              findsOneWidget,
            );
            await fill('payment-transition-reason', 'AUDIT-PAYMENT-UNPAID');
            await h.tap(key('payment-transition-submit'));
            await h.quiet();
            await movement('unpaid');
          },
        );
        await h.check(
          'PENDING',
          'Вернуть долг в ожидание подтверждения',
          () async {
            await menu('Ожидает подтверждения');
            await fill('payment-transition-reason', 'AUDIT-PAYMENT-PENDING');
            await h.tap(key('payment-transition-submit'));
            await h.quiet();
            await movement('posted_pending');
          },
        );
        await h.check(
          'PAID-VALIDATION',
          'Подтверждение оплаты требует причины и номера операции',
          () async {
            await menu('Подтвердить оплату');
            await h.tap(key('payment-transition-submit'));
            expect(
              find.text('Укажите номер операции или чека'),
              findsOneWidget,
            );
            await movement('posted_pending');
          },
        );
        await h.check(
          'PAID',
          'Подтверждение зачисляет 1234,50 ₽ на личный счёт',
          () async {
            await fill('payment-transition-reason', 'AUDIT-PAYMENT-PAID');
            await fill('payment-transition-identifier', 'AUDIT-PAYMENT-$role');
            await h.tap(key('payment-transition-submit'));
            await h.quiet();
            await movement('paid');
            expect(
              (await read()).accounts.fold<BigInt>(
                BigInt.zero,
                (sum, account) => sum + account.balanceMinor,
              ),
              BigInt.from(123450),
            );
          },
        );
        await h.check(
          'PAID-REOPEN',
          'Подтверждённая оплата и баланс сохраняются после открытия',
          () async {
            await open();
            await movement('paid');
            expect(
              (await read()).accounts.fold<BigInt>(
                BigInt.zero,
                (sum, account) => sum + account.balanceMinor,
              ),
              BigInt.from(123450),
            );
          },
        );
        Future<void> reverse() async {
          if (key('reverse-payment-$paymentId').evaluate().isEmpty) {
            await h.tap(key('payment-movements-expansion'));
          }
          await h.tap(key('reverse-payment-$paymentId'));
          await h.quiet();
        }

        await h.check(
          'DELETE-CANCEL',
          'Отмена удаления сохраняет оплату и баланс',
          () async {
            await reverse();
            await fill('payment-reversal-reason', 'CANCEL');
            await h.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
            expect(
              (await read()).accounts.fold<BigInt>(
                BigInt.zero,
                (sum, account) => sum + account.balanceMinor,
              ),
              BigInt.from(123450),
            );
          },
        );
        await h.check(
          'DELETE',
          'Удаление требует причину и возвращает баланс к нулю',
          () async {
            await reverse();
            await h.tap(key('payment-reversal-submit'));
            expect(
              find.text('Укажите причину удаления оплаты'),
              findsOneWidget,
            );
            await fill('payment-reversal-reason', 'AUDIT-PAYMENT-REVERSED');
            await h.tap(key('payment-reversal-submit'));
            await h.quiet();
            expect(
              (await read()).accounts.fold<BigInt>(
                BigInt.zero,
                (sum, account) => sum + account.balanceMinor,
              ),
              BigInt.zero,
            );
          },
        );
        await h.check(
          'FINAL',
          'После открытия баланс остаётся нулевым, история не исчезает',
          () async {
            await open();
            final value = await read();
            expect(
              value.accounts.fold<BigInt>(
                BigInt.zero,
                (sum, account) => sum + account.balanceMinor,
              ),
              BigInt.zero,
            );
            expect(value.technicalHistory, isNotEmpty);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 15)),
    );
  }
}
