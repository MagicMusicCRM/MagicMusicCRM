import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

void main() {
  test('retired partial miss is unavailable even from an older server', () {
    for (final operation in LessonDecisionOperation.values) {
      final catalog = LessonDecisionCatalog.fromJson({
        'settlementTypes': [
          for (final key in [
            'partially_paid_miss',
            'partially_paid_lesson',
            'paid_miss',
          ])
            {
              'stableKey': key,
              'label': key,
              'order': 0,
              'active': true,
              'allowedContexts': ['cancel', 'reschedule', 'settle'],
            },
        ],
      }, operation);
      expect(catalog.settlementTypes.map((item) => item.key), [
        'partially_paid_lesson',
        'paid_miss',
      ]);
    }
  });
  test(
    'cancel draft starts as unpaid miss with zero client and teacher time',
    () {
      final draft = LessonDecisionDraft.forCancel(
        catalog: const LessonDecisionCatalog(
          settlementTypes: [
            LessonDecisionCatalogItem(
              key: 'unpaid_miss',
              label: 'Неоплачиваемый пропуск',
              order: 0,
              clientDurationMode: 'zero',
              teacherDurationMode: 'zero',
              defaultTeacherCompensationRuleKey: 'none',
            ),
          ],
          compensationRules: [
            LessonDecisionCatalogItem(
              key: 'none',
              label: 'Не оплачивать',
              order: 0,
              mode: 'none',
            ),
          ],
        ),
        lesson: const {'durationMinutes': 60, 'studentId': 'student-1'},
        clients: const [
          LessonDecisionParticipant(id: 'student-1', name: 'Анна'),
        ],
        existingClientDecisions: const [
          {
            'clientId': 'student-1',
            'chargeType': 'subscription',
            'payerStudentId': 'payer-1',
            'subscriptionId': 'subscription-1',
          },
        ],
      );

      expect(draft.settlementTypeKey, 'unpaid_miss');
      expect(draft.teacherCompensationRuleKey, 'none');
      expect(draft.clientDecisions.single.chargeDurationMinutes, 0);
      expect(draft.clientDecisions.single.chargeType, 'none');
      expect(draft.clientDecisions.single.preferredChargeType, 'subscription');
      expect(draft.clientDecisions.single.payerStudentId, 'payer-1');
      expect(draft.clientDecisions.single.subscriptionId, 'subscription-1');
      expect(draft.teacherCreditedDurationMinutes, 0);
    },
  );

  test('cancel draft retains personal-account funding for a paid switch', () {
    final draft = LessonDecisionDraft.forCancel(
      catalog: const LessonDecisionCatalog(
        settlementTypes: [
          LessonDecisionCatalogItem(
            key: 'unpaid_miss',
            label: 'Неоплачиваемый пропуск',
            order: 0,
            clientDurationMode: 'zero',
            teacherDurationMode: 'zero',
            defaultTeacherCompensationRuleKey: 'none',
          ),
        ],
        compensationRules: [],
      ),
      lesson: const {'durationMinutes': 60, 'studentId': 'student-1'},
      clients: const [LessonDecisionParticipant(id: 'student-1', name: 'Анна')],
      existingClientDecisions: const [
        {
          'clientId': 'student-1',
          'chargeType': 'personal_account',
          'payerStudentId': 'payer-1',
          'basePriceMinor': '100000',
        },
      ],
    );

    final client = draft.clientDecisions.single;
    expect(client.chargeType, 'none');
    expect(client.preferredChargeType, 'personal_account');
    expect(client.payerStudentId, 'payer-1');
    expect(client.retainedFunding, {'basePriceMinor': '100000'});
  });

  test(
    'normalizes editor pricing into the existing commercial HTTP contract',
    () {
      final draft = normalizeLessonClientDecision({
        'clientId': 'student-a',
        'payerStudentId': 'payer-b',
        'chargeType': 'personal_account',
        'subscriptionId': 'old-sub',
        'basePriceMinor': '100000',
        'discount': {'type': 'percent', 'percent': 12.5, 'reason': 'Акция'},
        'surcharge': {'amountMinor': '5000', 'reason': 'Материалы'},
      });
      expect((draft['discount'] as Map)['percentBasisPoints'], 1250);
      expect(lessonClientDecisionsPayload([draft]), [
        {
          'clientId': 'student-a',
          'payerStudentId': 'payer-b',
          'chargeType': 'personal_account',
          'basePriceMinor': '100000',
          'discount': {'type': 'percent', 'percent': 12.5, 'reason': 'Акция'},
          'surcharge': {'amountMinor': '5000', 'reason': 'Материалы'},
        },
      ]);
      expect(
        lessonClientDecisionsPayload([
          {
            'clientId': 'lead-a',
            'payerStudentId': 'lead-a',
            'chargeType': 'none',
            'subscriptionId': 'old-sub',
            'discount': {'type': 'none'},
            'surcharge': {'type': 'none'},
          },
        ]),
        [
          {'clientId': 'lead-a', 'chargeType': 'none'},
        ],
      );
    },
  );
  test('pins operation API and catalog contracts', () {
    expect(LessonDecisionOperation.reschedule.apiKey, 'reschedule');
    expect(LessonDecisionOperation.cancel.apiKey, 'cancel');
    expect(LessonDecisionOperation.settle.catalogContext, 'settle');
    expect(
      LessonDecisionOperation.plannedSettlement.apiKey,
      'planned-settlement',
    );
    expect(LessonDecisionOperation.plannedSettlement.catalogContext, 'settle');
    expect(LessonDecisionOperation.correction.apiKey, 'settlement-correction');
    expect(LessonDecisionOperation.correction.catalogContext, 'settle');
  });

  test('filters and orders the server catalog by operation context', () {
    final catalog = LessonDecisionCatalog.fromJson({
      'settlementTypes': [
        {
          'stableKey': 'late',
          'label': 'Поздно',
          'order': 20,
          'allowedContexts': ['cancel'],
        },
        {
          'stableKey': 'free',
          'label': 'Бесплатно',
          'order': 10,
          'allowedContexts': ['settle'],
        },
      ],
      'teacherCompensationRules': [
        {
          'stableKey': 'standard',
          'label': 'Стандарт',
          'order': 1,
          'mode': 'standard',
        },
      ],
    }, LessonDecisionOperation.plannedSettlement);

    expect(catalog.settlementTypes.map((item) => item.key), ['free']);
    expect(catalog.compensationRules.single.key, 'standard');
  });
}
