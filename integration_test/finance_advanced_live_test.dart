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
        final h = LiveAuditHarness(tester, role, 'finance-advanced');
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
          lastName: 'FINANCE-ADVANCED-$role',
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
          await h.tap(key('client-section-heading-payments'));
          await h.quiet();
        }

        Future<void> form() async {
          await h.tap(key('open-payment-form'));
          await h.quiet();
          expect(find.byType(ClientPaymentForm), findsOneWidget);
        }

        Future<void> menu(String text) async {
          if (key('payment-status-$paymentId').evaluate().isEmpty) {
            await h.tap(key('payment-movements-expansion'));
          }
          await h.tap(key('payment-status-$paymentId'));
          await h.tap(find.text(text).last);
          await h.quiet();
        }

        Future<void> balance(int minor) async {
          expect(
            (await read()).accounts.fold<BigInt>(
              BigInt.zero,
              (sum, a) => sum + a.balanceMinor,
            ),
            BigInt.from(minor),
          );
        }

        Future<void> action(String prefix) async {
          if (key('$prefix-$paymentId').evaluate().isEmpty) {
            await h.tap(key('payment-movements-expansion'));
          }
          await h.tap(key('$prefix-$paymentId'));
          await h.quiet();
        }

        await h.check(
          'CREATE',
          'Создать оплату и подтвердить 1 000 ₽',
          () async {
            await open();
            await form();
            await fill('payment-amount', '1000');
            await h.tap(key('payment-submit'));
            await h.quiet();
            paymentId = (await read()).movements.single.id;
            await menu('Подтвердить оплату');
            await fill('payment-transition-reason', 'AUDIT-ADVANCED');
            await fill('payment-transition-identifier', 'AUDIT-ADVANCED-$role');
            await h.tap(key('payment-transition-submit'));
            await h.quiet();
            await balance(100000);
          },
        );
        await h.check(
          'CORRECT-CANCEL',
          'Отмена исправления не меняет оплату',
          () async {
            await action('correct-payment');
            await fill('payment-correction-amount', '1500');
            await h.tap(find.text('Отмена').last);
            await balance(100000);
          },
        );
        await h.check(
          'CORRECT-PREVIEW',
          'Preview исправления показывает пересчёт и требует подтверждение',
          () async {
            await action('correct-payment');
            await fill('payment-correction-amount', '1500');
            await fill('payment-correction-comment', 'AUDIT-CORRECTED');
            await fill('payment-correction-reason', 'AUDIT-AMOUNT-CORRECTION');
            await h.tap(key('payment-correction-preview'));
            await h.quiet();
            expect(
              tester
                  .widget<FilledButton>(key('payment-correction-commit'))
                  .onPressed,
              isNull,
            );
            await balance(100000);
          },
        );
        await h.check(
          'CORRECT',
          'Подтверждённое исправление пересчитывает баланс до 1 500 ₽',
          () async {
            await h.tap(key('payment-correction-confirm'));
            await h.tap(key('payment-correction-commit'));
            await h.quiet();
            await balance(150000);
            final rows = (await read()).movements
                .where(
                  (m) =>
                      m.kind == CommerceMovementKind.paymentRecord &&
                      m.status == 'paid',
                )
                .toList();
            expect(rows, hasLength(1));
            paymentId = rows.single.id;
            expect(rows.single.amountMinor, BigInt.from(150000));
          },
        );
        await h.check(
          'CORRECT-REOPEN',
          'Исправленная сумма и комментарий сохраняются после открытия',
          () async {
            await open();
            await balance(150000);
            await action('correct-payment');
            expect(
              tester
                  .widget<TextFormField>(key('payment-correction-amount'))
                  .controller!
                  .text,
              '1500',
            );
            expect(
              tester
                  .widget<TextFormField>(key('payment-correction-comment'))
                  .controller!
                  .text,
              'AUDIT-CORRECTED',
            );
            await h.tap(find.text('Отмена').last);
          },
        );
        await h.check(
          'ADJUST-CANCEL',
          'Отменить отдельную корректировку без изменения баланса',
          () async {
            await action('adjust-payment');
            await fill('adjustment-amount', '250');
            await h.tap(find.byTooltip('Закрыть форму исправления'));
            await balance(150000);
          },
        );
        String? adjustmentId;
        await h.check(
          'ADJUST',
          'Отдельная приходная корректировка добавляет 250 ₽',
          () async {
            await action('adjust-payment');
            await h.tap(key('adjustment-kind'));
            await h.tap(find.text('Корректировка').last);
            await h.tap(key('adjustment-direction'));
            await h.tap(find.text('Приход').last);
            await fill('adjustment-amount', '250');
            await fill('adjustment-reason', 'AUDIT-INCOME-CORRECTION');
            await h.tap(key('adjustment-submit'));
            await h.quiet();
            await balance(175000);
            adjustmentId = (await read()).movements
                .singleWhere((m) => m.kind == CommerceMovementKind.adjustment)
                .id;
          },
        );
        if (adjustmentId == null) {
          for (final s in [
            'ADJUST-REOPEN',
            'REVERSE-CANCEL',
            'REVERSE',
            'FINAL',
          ]) {
            h.blocked(s, s, 'Отдельная корректировка не подтверждена');
          }
          await h.finish();
          return;
        }
        Future<void> reverseAdjustment() async {
          if (key('reverse-adjustment-$adjustmentId').evaluate().isEmpty) {
            await h.tap(key('payment-movements-expansion'));
          }
          await h.tap(key('reverse-adjustment-$adjustmentId'));
          await h.quiet();
        }

        await h.check(
          'ADJUST-REOPEN',
          'Корректировка сохраняется после открытия карточки',
          () async {
            await open();
            await balance(175000);
          },
        );
        await h.check(
          'REVERSE-CANCEL',
          'Отмена сторно сохраняет корректировку',
          () async {
            await reverseAdjustment();
            await fill('adjustment-reversal-reason', 'CANCEL');
            await h.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
            await balance(175000);
          },
        );
        await h.check(
          'REVERSE',
          'Сторно требует причину и возвращает баланс к 1 500 ₽',
          () async {
            await reverseAdjustment();
            await h.tap(key('adjustment-reversal-submit'));
            expect(find.text('Укажите причину сторно'), findsOneWidget);
            await fill(
              'adjustment-reversal-reason',
              'AUDIT-REVERSE-ADJUSTMENT',
            );
            await h.tap(key('adjustment-reversal-submit'));
            await h.quiet();
            await balance(150000);
          },
        );
        await h.check(
          'FINAL',
          'После открытия сумма исправленной оплаты сохраняется, корректировка снята',
          () async {
            await open();
            await balance(150000);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}
