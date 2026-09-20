import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['admin', 'manager', 'director'])
    testWidgets('$role existing student link and delivered invitation', (
      tester,
    ) async {
      final h = LiveAuditHarness(tester, role, 'client-link-invite');
      await h.initialize(size: const Size(1600, 1400));
      final crm = h.scope.read(magicCrmServiceProvider),
          forms = h.scope.read(clientFormsApiProvider),
          access = await h.scope.read(capabilitySnapshotProvider.future),
          branch = h.fixture['branchId'] as String;
      final source = (await forms.listSources()).first['id'] as String,
          lp = await crm.getClientPipeline(
            clientType: 'lead',
            branchId: branch,
          ),
          sp = await crm.getClientPipeline(
            clientType: 'student',
            branchId: branch,
          );
      final lead = await forms.createLead(
        identity: MagicMutationIdentity.create('audit.fixture.lead'),
        firstName: 'AUDIT-LINK-LEAD-$role',
        lastName: 'Тест',
        phone: '+79991112211',
        sourceId: source,
        branchId: branch,
        status: lp.activeStages.first.key,
        customFields: [],
      );
      final student = await forms.createStudent(
        identity: MagicMutationIdentity.create('audit.fixture.student'),
        firstName: 'AUDIT-LINK-STUDENT-$role',
        lastName: 'Тест',
        phone: '+79991113311',
        sourceId: source,
        branchId: branch,
        status: sp.activeStages.first.key,
        customFields: [],
      );
      final lid = lead['id'] as String,
          sid = student['id'] as String,
          account = (h.fixture['accounts'] as List).cast<Map>().singleWhere(
            (a) => a['role'] == 'client',
          ),
          email = account['email'] as String;
      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> open(String type, String id) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          Scaffold(
            body: ClientCard(
              lead: {'id': id},
              entityType: type,
              routed: true,
              initialSection: 'overview',
              capabilitySnapshot: access,
            ),
          ),
        );
        await h.quiet();
      }

      Future<void> search(String value) async {
        await h.tap(find.text('Прикрепить к ученику'));
        final field = find.descendant(
          of: find.byType(SearchableSelect),
          matching: find.byType(TextField),
        );
        await h.tap(field);
        await tester.enterText(field, value);
        await tester.pump(const Duration(milliseconds: 600));
        await h.quiet();
      }

      await h.check('OPEN', 'Открыть лида без связанного ученика', () async {
        await open('lead', lid);
        expect(find.text('Прикрепить к ученику'), findsOneWidget);
        expect((await crm.getStudent(sid))['lead_id'], isNull);
      });
      await h.check(
        'SEARCH-CANCEL',
        'Найти существующего ученика и закрыть поиск без изменения связи',
        () async {
          await search('AUDIT-LINK-STUDENT-$role');
          expect(find.text('AUDIT-LINK-STUDENT-$role Тест'), findsOneWidget);
          await h.tap(find.byTooltip('Закрыть').last);
          expect((await crm.getStudent(sid))['lead_id'], isNull);
        },
      );
      await h.check(
        'LINK',
        'Прикрепить существующего ученика через результат серверного поиска',
        () async {
          await search('AUDIT-LINK-STUDENT-$role');
          await h.tap(find.text('AUDIT-LINK-STUDENT-$role Тест'));
          await h.quiet();
          expect((await crm.getStudent(sid))['lead_id'], lid);
          expect(find.text('Прикрепить к ученику'), findsNothing);
          h.facts.add({
            'step': h.currentStep,
            'student': await crm.getStudent(sid),
            'card': await crm.getLeadCard(lid),
          });
        },
      );
      await h.check(
        'REOPEN',
        'Повторно открыть объединённую карточку и проверить сохранённую связь',
        () async {
          await open('lead', lid);
          expect(find.text('Прикрепить к ученику'), findsNothing);
          expect((await crm.getStudent(sid))['lead_id'], lid);
        },
      );
      await h.check(
        'INVITE-EMPTY',
        'Без email приглашение не отправляется и показано объяснение',
        () async {
          await open('student', sid);
          await h.tap(key('client-section-jump-contacts'));
          final n = h.requests
              .where(
                (r) =>
                    r['method'] == 'POST' &&
                    r['path'].toString().contains('/invite'),
              )
              .length;
          await h.tap(key('client-send-invite'));
          await h.quiet();
          expect(
            find.text('Укажите электронную почту в карточке клиента'),
            findsWidgets,
          );
          expect(
            h.requests
                .where(
                  (r) =>
                      r['method'] == 'POST' &&
                      r['path'].toString().contains('/invite'),
                )
                .length,
            n,
          );
        },
      );
      await h.check(
        'EMAIL',
        'Заполнить email подтверждённого аккаунта и сохранить перед приглашением',
        () async {
          await h.tap(key('client-section-jump-overview'));
          final field = find.widgetWithText(TextFormField, 'Электронная почта');
          await h.tap(field);
          await tester.enterText(field, email);
          await tester.pump(const Duration(seconds: 2));
          await h.quiet();
          expect((await crm.getStudent(sid))['email'], email);
        },
      );
      await h.check(
        'INVITE',
        'Кнопка приглашения отправляет команду и связывает подтверждённый аккаунт',
        () async {
          await h.tap(key('client-section-jump-contacts'));
          await h.tap(key('client-send-invite'));
          await h.quiet();
          expect(find.text('Приглашение отправлено'), findsWidgets);
          final linked = await crm.getClientLinkedUsers('student', sid);
          expect(linked.length, 1);
          h.facts.add({'step': h.currentStep, 'linked': linked});
        },
      );
      await h.check(
        'INVITE-REOPEN',
        'Привязанный аккаунт виден после повторного открытия карточки',
        () async {
          await open('student', sid);
          await h.tap(key('client-section-jump-contacts'));
          expect((await crm.getClientLinkedUsers('student', sid)).length, 1);
          expect(find.byKey(const Key('client-app-access')), findsOneWidget);
        },
      );
      h.facts.add({'leadId': lid, 'studentId': sid, 'email': email});
      await h.finish();
    });
}
