import '../lesson_decision/lesson_decision_models.dart';

class LessonFinancialRecommendation {
  const LessonFinancialRecommendation._({
    required this.compensationRuleKey,
    required this.teacherCreditedDurationMinutes,
    required this.source,
  });

  const LessonFinancialRecommendation.automatic({
    required String? ruleKey,
    required int? teacherMinutes,
  }) : this._(
         compensationRuleKey: ruleKey,
         teacherCreditedDurationMinutes: teacherMinutes,
         source: 'automatic',
       );

  const LessonFinancialRecommendation.manual({
    required String? ruleKey,
    required int? teacherMinutes,
  }) : this._(
         compensationRuleKey: ruleKey,
         teacherCreditedDurationMinutes: teacherMinutes,
         source: 'manual',
       );

  final String? compensationRuleKey;
  final int? teacherCreditedDurationMinutes;
  final String source;
}

class LessonFinancialAutofill {
  const LessonFinancialAutofill();

  LessonFinancialRecommendation apply({
    required LessonDecisionCatalogItem settlement,
    required int durationMinutes,
    required bool compensationTouched,
    String? currentRuleKey,
    int? currentTeacherMinutes,
  }) {
    if (compensationTouched) {
      return LessonFinancialRecommendation.manual(
        ruleKey: currentRuleKey,
        teacherMinutes: currentTeacherMinutes,
      );
    }
    return restoreRecommendation(
      settlement: settlement,
      durationMinutes: durationMinutes,
    );
  }

  LessonFinancialRecommendation restoreRecommendation({
    required LessonDecisionCatalogItem settlement,
    required int durationMinutes,
  }) => LessonFinancialRecommendation.automatic(
    ruleKey: settlement.defaultTeacherCompensationRuleKey,
    teacherMinutes: switch (settlement.teacherDurationMode) {
      'zero' => 0,
      'full' => durationMinutes,
      _ => null,
    },
  );

  int? recommendedClientMinutes({
    required LessonDecisionCatalogItem settlement,
    required int durationMinutes,
  }) => switch (settlement.clientDurationMode) {
    'zero' => 0,
    'full' => durationMinutes,
    _ => null,
  };
}

String? partialDurationError(
  String? value, {
  required int lessonDurationMinutes,
}) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) return 'Укажите длительность в минутах';
  final minutes = int.tryParse(input);
  if (minutes == null || minutes < 0) {
    return 'Введите целое количество минут';
  }
  if (minutes > lessonDurationMinutes) {
    return 'Не больше $lessonDurationMinutes мин';
  }
  return null;
}

String formatLessonMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$remainder мин';
  if (remainder == 0) return '$hours ч';
  return '$hours ч $remainder мин';
}
