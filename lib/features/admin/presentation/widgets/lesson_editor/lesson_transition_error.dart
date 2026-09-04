import 'package:magic_music_crm/core/api/magic_api_error.dart';

const lessonTransitionErrorMessages = <String, String>{
  'LESSON_VERSION_STALE': 'Занятие уже изменилось. Я открыл актуальную версию.',
  'LESSON_ALREADY_RESCHEDULED':
      'Это занятие уже перенесено. Я открыл последнее занятие в цепочке.',
  'LESSON_RESCHEDULE_CHAIN_INVALID':
      'Цепочка переносов повреждена. Изменения не сохранены; обратитесь администратору.',
  'LESSON_TRANSITION_PREVIEW_STALE':
      'Расписание или расчёт изменились. Проверьте обновлённый предварительный расчёт.',
  'LESSON_PARTIAL_DURATION_REQUIRED':
      'Укажите часы списания клиента и начисления преподавателю.',
};

String? lessonTransitionErrorCode(Object error) {
  if (error is! MagicApiException || error.details is! Map) return null;
  return (error.details! as Map)['code']?.toString();
}

String? lessonTransitionActionableLessonId(Object error) {
  if (error is! MagicApiException || error.details is! Map) return null;
  final details = error.details! as Map;
  return (details['actionableLessonId'] ?? details['actionable_lesson_id'])
      ?.toString();
}

MagicApiException mapLessonTransitionError(MagicApiException error) {
  final code = lessonTransitionErrorCode(error);
  final effectiveCode = code == 'STALE_LESSON_VERSION'
      ? 'LESSON_VERSION_STALE'
      : code;
  final message = effectiveCode == null
      ? null
      : lessonTransitionErrorMessages[effectiveCode];
  return message == null
      ? error
      : MagicApiException(
          statusCode: error.statusCode,
          message: message,
          details: error.details,
        );
}

Object mapLessonTransitionFailure(Object error) =>
    error is MagicApiException ? mapLessonTransitionError(error) : error;
