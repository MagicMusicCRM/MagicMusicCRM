import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

void main() {
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
