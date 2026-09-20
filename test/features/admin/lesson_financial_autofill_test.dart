import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_financial_autofill.dart';

void main() {
  const autofill = LessonFinancialAutofill();

  test('applies catalog full and zero teacher recommendations', () {
    final paid = autofill.apply(
      settlement: _settlement(
        key: 'paid_miss',
        clientDurationMode: 'full',
        teacherDurationMode: 'full',
        defaultTeacherCompensationRuleKey: 'standard',
      ),
      durationMinutes: 60,
      compensationTouched: false,
    );
    final unpaid = autofill.apply(
      settlement: _settlement(
        key: 'unpaid_miss',
        clientDurationMode: 'zero',
        teacherDurationMode: 'zero',
        defaultTeacherCompensationRuleKey: 'none',
      ),
      durationMinutes: 60,
      compensationTouched: false,
    );

    expect(paid.compensationRuleKey, 'standard');
    expect(paid.teacherCreditedDurationMinutes, 60);
    expect(paid.source, 'automatic');
    expect(unpaid.compensationRuleKey, 'none');
    expect(unpaid.teacherCreditedDurationMinutes, 0);
    expect(unpaid.source, 'automatic');
  });

  test('preserves a touched teacher decision as manual', () {
    final preserved = autofill.apply(
      settlement: _settlement(
        key: 'unpaid_miss',
        clientDurationMode: 'zero',
        teacherDurationMode: 'zero',
        defaultTeacherCompensationRuleKey: 'none',
      ),
      durationMinutes: 60,
      compensationTouched: true,
      currentRuleKey: 'fixed',
      currentTeacherMinutes: 45,
    );

    expect(preserved.compensationRuleKey, 'fixed');
    expect(preserved.teacherCreditedDurationMinutes, 45);
    expect(preserved.source, 'manual');
  });

  test('explicit restore reapplies the current catalog recommendation', () {
    final restored = autofill.restoreRecommendation(
      settlement: _settlement(
        key: 'partially_paid_miss',
        clientDurationMode: 'manual',
        teacherDurationMode: 'manual',
        defaultTeacherCompensationRuleKey: 'percent',
      ),
      durationMinutes: 60,
    );

    expect(restored.compensationRuleKey, 'percent');
    expect(restored.teacherCreditedDurationMinutes, isNull);
    expect(restored.source, 'automatic');
  });

  test(
    'client recommendation is independent for full zero and manual modes',
    () {
      expect(
        autofill.recommendedClientMinutes(
          settlement: _settlement(
            key: 'paid_miss',
            clientDurationMode: 'full',
            teacherDurationMode: 'full',
            defaultTeacherCompensationRuleKey: 'standard',
          ),
          durationMinutes: 90,
        ),
        90,
      );
      expect(
        autofill.recommendedClientMinutes(
          settlement: _settlement(
            key: 'unpaid_miss',
            clientDurationMode: 'zero',
            teacherDurationMode: 'zero',
            defaultTeacherCompensationRuleKey: 'none',
          ),
          durationMinutes: 90,
        ),
        0,
      );
      expect(
        autofill.recommendedClientMinutes(
          settlement: _settlement(
            key: 'partially_paid_miss',
            clientDurationMode: 'manual',
            teacherDurationMode: 'manual',
            defaultTeacherCompensationRuleKey: 'percent',
          ),
          durationMinutes: 90,
        ),
        isNull,
      );
    },
  );

  test(
    'partial duration validation accepts boundaries and rejects overflow',
    () {
      expect(partialDurationError('0', lessonDurationMinutes: 60), isNull);
      expect(partialDurationError('45', lessonDurationMinutes: 60), isNull);
      expect(partialDurationError('60', lessonDurationMinutes: 60), isNull);
      expect(
        partialDurationError('', lessonDurationMinutes: 60),
        'Укажите длительность в минутах',
      );
      expect(
        partialDurationError('30,5', lessonDurationMinutes: 60),
        'Введите целое количество минут',
      );
      expect(
        partialDurationError('61', lessonDurationMinutes: 60),
        'Не больше 60 мин',
      );
      expect(formatLessonMinutes(45), '45 мин');
      expect(formatLessonMinutes(90), '1 ч 30 мин');
    },
  );
}

LessonDecisionCatalogItem _settlement({
  required String key,
  required String clientDurationMode,
  required String teacherDurationMode,
  required String defaultTeacherCompensationRuleKey,
}) => LessonDecisionCatalogItem(
  key: key,
  label: key,
  order: 0,
  clientDurationMode: clientDurationMode,
  teacherDurationMode: teacherDurationMode,
  defaultTeacherCompensationRuleKey: defaultTeacherCompensationRuleKey,
);
