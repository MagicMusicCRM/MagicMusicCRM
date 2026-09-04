import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/student_lesson_timeline.dart';

void main() {
  group('StudentLessonTimelineItem', () {
    test('parses origins, coverage, redaction, and reschedule links', () {
      final generated = StudentLessonTimelineItem.fromJson(_timelineItemJson());
      final redacted = StudentLessonTimelineItem.fromJson(
        _timelineItemJson(
          id: 'lesson-redacted',
          lifecycleState: 'settlement_pending',
          originKind: 'one_off_exception',
          coveredBySubscription: false,
          settlementTypeKey: null,
        ),
      );

      expect(generated.lifecycleState, StudentLessonLifecycleState.scheduled);
      expect(generated.origin.kind, StudentLessonOriginKind.schedulePlan);
      expect(generated.origin.planId, 'plan-1');
      expect(generated.settlement.coveredBySubscription, isTrue);
      expect(generated.settlement.settlementTypeKey, 'lesson');
      expect(generated.reschedule.predecessorId, 'lesson-before');
      expect(generated.reschedule.successorId, 'lesson-after');
      expect(generated.reschedule.actionableLessonId, 'lesson-after');
      expect(generated.teacher?.name, 'Мария Иванова');
      expect(
        redacted.lifecycleState,
        StudentLessonLifecycleState.settlementPending,
      );
      expect(redacted.origin.kind, StudentLessonOriginKind.oneOffException);
      expect(redacted.settlement.coveredBySubscription, isFalse);
      expect(redacted.settlement.settlementTypeKey, isNull);
    });

    test('rejects unknown lifecycle and origin values', () {
      expect(
        () => StudentLessonTimelineItem.fromJson(
          _timelineItemJson(lifecycleState: 'completed'),
        ),
        throwsFormatException,
      );
      expect(
        () => StudentLessonTimelineItem.fromJson(
          _timelineItemJson(originKind: 'active'),
        ),
        throwsFormatException,
      );
    });
  });

  test('page parses cursors and exposes an immutable item list', () {
    final page = StudentLessonTimelinePage.fromJson({
      'items': [_timelineItemJson()],
      'previousCursor': 'cursor-before',
      'nextCursor': 'cursor-after',
      'hasPrevious': true,
      'hasNext': true,
    });

    expect(page.items.single.id, 'lesson-1');
    expect(page.previousCursor, 'cursor-before');
    expect(page.nextCursor, 'cursor-after');
    expect(() => page.items.add(page.items.single), throwsUnsupportedError);
  });
}

Map<String, dynamic> _timelineItemJson({
  String id = 'lesson-1',
  String lifecycleState = 'scheduled',
  String originKind = 'generated',
  bool coveredBySubscription = true,
  String? settlementTypeKey = 'lesson',
}) => {
  'id': id,
  'version': 7,
  'scheduledAt': '2026-09-04T12:30:00.000Z',
  'durationMinutes': 45,
  'lifecycleState': lifecycleState,
  'student': {'id': 'student-1', 'name': 'Анна Петрова'},
  'group': {'id': 'group-1', 'name': 'Ансамбль'},
  'teacher': {'id': 'teacher-1', 'name': 'Мария Иванова'},
  'room': {'id': 'room-1', 'name': 'Класс 1'},
  'branch': {'id': 'branch-1', 'name': 'Центр'},
  'origin': {'kind': originKind, 'planId': 'plan-1', 'seriesId': 'series-1'},
  'settlement': {
    'coveredBySubscription': coveredBySubscription,
    'settlementTypeKey': settlementTypeKey,
  },
  'reschedule': {
    'predecessorId': 'lesson-before',
    'successorId': 'lesson-after',
    'actionableLessonId': 'lesson-after',
  },
};
