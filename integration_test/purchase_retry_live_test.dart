import 'package:dio/dio.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director'])
    testWidgets(
      '$role related payer and purchase lost response retry',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'purchase-retry');
        await h.initialize(size: const Size(1500, 1400));
        final crm = h.scope.read(magicCrmServiceProvider),
            forms = h.scope.read(clientFormsApiProvider),
            access = await h.scope.read(capabilitySnapshotProvider.future),
            branch = h.fixture['branchId'] as String;
        final source = (await forms.listSources()).first,
            pipeline = await crm.getClientPipeline(
              clientType: 'student',
              branchId: branch,
            );
        Future<String> create(String type) async =>
            (await forms.createStudent(
                  identity: MagicMutationIdentity.create(
                    'audit.fixture.student',
                  ),
                  firstName: 'AUDIT-RETRY-$type',
                  lastName: role,
                  phone: '+79996667788',
                  sourceId: source['id'],
                  branchId: branch,
                  status: pipeline.activeStages.first.key,
                  customFields: [],
                ))['id']
                as String;
        final student = await create('CHILD'),
            payer = await create('PAYER'),
            family = await crm.createFamily({
              'name': 'AUDIT-RETRY-$role',
              'branchId': branch,
            });
        await crm.addFamilyMember(
          family['id'],
          entityType: 'student',
          entityId: student,
          role: 'child',
        );
        final member = await crm.addFamilyMember(
          family['id'],
          entityType: 'student',
          entityId: payer,
          role: 'payer',
        );
        await crm.setFamilyPrimaryPayer(family['id'], member['id']);
        final payerRef = (await crm.searchClientRefs(
          q: 'AUDIT-RETRY-PAYER',
          type: 'student',
          limit: 50,
        )).singleWhere((r) => (r['ref'] as Map)['id'] == payer);
        final payerLabel = payerRef['label'] as String;
        bool lose = false;
        final attempts = <Map<String, dynamic>>[];
        Map<String, dynamic>? committed;
        final purchasePath = '/crm/students/$student/subscriptions/purchase';
        h.api.rawDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, handler) {
              if (o.method == 'POST' && o.uri.path.endsWith(purchasePath))
                attempts.add({
                  'key': o.headers['Idempotency-Key'],
                  'body': Map<String, dynamic>.from(o.data as Map),
                });
              handler.next(o);
            },
            onResponse: (r, handler) {
              if (lose && r.requestOptions.uri.path.endsWith(purchasePath)) {
                lose = false;
                committed = Map<String, dynamic>.from(r.data as Map);
                handler.reject(
                  DioException(
                    requestOptions: r.requestOptions,
                    type: DioExceptionType.connectionError,
                    error: 'AUDIT response lost after server committed',
                  ),
                );
              } else {
                handler.next(r);
              }
            },
          ),
        );
        Finder key(String k) => find.byKey(Key(k));
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            Scaffold(
              body: ClientCard(
                lead: await crm.getStudent(student),
                entityType: 'student',
                routed: true,
                initialSection: 'subscriptions',
                capabilitySnapshot: access,
              ),
            ),
          );
          await h.quiet();
          await h.tap(key('client-section-heading-subscriptions'));
          await h.tap(key('subscription-add'));
          await h.quiet();
        }

        await h.check(
          'OPEN',
          'Открыть продажу абонемента из карточки получателя',
          () async {
            await open();
            expect(find.byType(SubscriptionIssueForm), findsOneWidget);
          },
        );
        await h.check(
          'PAYER',
          'Найти и выбрать другого плательщика из той же семьи',
          () async {
            final field = find.descendant(
              of: key('subscription-payer'),
              matching: find.byType(TextField),
            );
            await h.tap(field);
            await tester.enterText(field, 'AUDIT-RETRY-PAYER');
            await h.quiet();
            await h.tap(find.text(payerLabel));
            await h.quiet();
            expect(
              tester
                  .widget<SearchablePickerField>(key('subscription-payer'))
                  .selectedId,
              payer,
            );
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Оплачено сейчас'),
              '0',
            );
          },
        );
        await h.check(
          'REASON',
          'Без причины оплаты другим человеком команда не отправляется',
          () async {
            await h.tap(key('subscription-issue-submit'));
            await h.quiet();
            expect(attempts, isEmpty);
            expect(
              find.text('Укажите причину оплаты другим плательщиком'),
              findsOneWidget,
            );
          },
        );
        await h.check(
          'LOST-RESPONSE',
          'Сервер сохраняет покупку, потерянный ответ оставляет кнопку Повторить',
          () async {
            await tester.enterText(
              key('subscription-purchase-reason'),
              'AUDIT-RELATED-PAYER-RETRY',
            );
            lose = true;
            await h.tap(key('subscription-issue-submit'));
            await h.quiet();
            expect(committed, isNotNull);
            expect(find.byType(SubscriptionIssueForm), findsOneWidget);
            expect(
              find.widgetWithText(FilledButton, 'Повторить'),
              findsOneWidget,
            );
            expect(attempts.length, 1);
            final list = (await crm.getStudentCommerceProjection(
              student,
            )).student.subscriptions;
            expect(list.length, 1);
            h.facts.add({
              'step': h.currentStep,
              'studentId': student,
              'payerId': payer,
              'familyId': family['id'],
              'subscriptionId': list.single.id,
              'committed': committed,
            });
          },
        );
        await h.check(
          'FROZEN',
          'Неопределённый результат блокирует изменение условий до повтора',
          () async {
            expect(
              tester
                  .widget<SearchablePickerField>(key('subscription-payer'))
                  .enabled,
              false,
            );
            expect(
              tester
                  .widget<TextFormField>(key('subscription-purchase-reason'))
                  .enabled,
              false,
            );
          },
        );
        await h.check(
          'RETRY',
          'Повторить покупку с тем же ключом и получить единственный абонемент',
          () async {
            await h.tap(key('subscription-issue-submit'));
            await h.waitFor(
              () => find.byType(SubscriptionIssueForm).evaluate().isEmpty,
              'Retry closes form',
            );
            await h.quiet();
            expect(attempts.length, 2);
            expect(attempts[1], attempts[0]);
            final list = (await crm.getStudentCommerceProjection(
              student,
            )).student.subscriptions;
            expect(list.length, 1);
            expect(list.single.id, (committed!['subscription'] as Map)['id']);
            h.facts.add({
              'step': h.currentStep,
              'attempts': attempts,
              'subscription': list.single.toLegacyMap(student),
            });
          },
        );
        await h.check(
          'REOPEN',
          'Повторное открытие карточки показывает одну сохранённую покупку',
          () async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await h.mount(
              Scaffold(
                body: ClientCard(
                  lead: await crm.getStudent(student),
                  entityType: 'student',
                  routed: true,
                  initialSection: 'subscriptions',
                  capabilitySnapshot: access,
                ),
              ),
            );
            await h.quiet();
            await h.tap(key('client-section-heading-subscriptions'));
            expect(
              (await crm.getStudentCommerceProjection(
                student,
              )).student.subscriptions.length,
              1,
            );
            expect(find.text('RETRY-PACKAGE'), findsWidgets);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
}
