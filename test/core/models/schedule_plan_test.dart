import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';

void main() {
  test('plan parses recurring rules and dated exceptions exactly', () {
    final plan = SchedulePlan.fromMap({
      'id': 'plan-1',
      'kind': 'individual',
      'title': 'Фортепиано',
      'studentId': 'student-1',
      'activeFrom': '2026-09-01',
      'status': 'active',
      'version': 3,
      'rows': <dynamic>[],
      'participants': <dynamic>[],
      'ruleTimeline': [
        _ruleTimelineJson(),
        _ruleTimelineJson(
          id: 'lesson-exception',
          kind: 'dated_exception',
          status: 'expired',
          scheduledDate: '2026-09-02',
          activeUntil: '2026-09-02',
          changedFields: const ['teacherId', 'roomId'],
          sortBucket: 3,
          lessonId: 'lesson-exception',
        ),
      ],
      'exceptions': [
        _ruleTimelineJson(
          id: 'lesson-exception',
          kind: 'dated_exception',
          status: 'expired',
          scheduledDate: '2026-09-02',
          activeUntil: '2026-09-02',
          changedFields: const ['teacherId', 'roomId'],
          sortBucket: 3,
          lessonId: 'lesson-exception',
        ),
      ],
    });

    expect(
      plan.ruleTimeline.first.kind,
      ScheduleRuleTimelineKind.recurringRule,
    );
    expect(plan.ruleTimeline.first.status, ScheduleRuleTimelineStatus.active);
    expect(plan.ruleTimeline.first.lessonId, isNull);
    expect(
      plan.ruleTimeline.last.kind,
      ScheduleRuleTimelineKind.datedException,
    );
    expect(plan.ruleTimeline.last.status, ScheduleRuleTimelineStatus.expired);
    expect(plan.ruleTimeline.last.changedFields, [
      ScheduleRuleTimelineChangedField.teacherId,
      ScheduleRuleTimelineChangedField.roomId,
    ]);
    expect(plan.exceptions.single.lessonId, 'lesson-exception');
  });

  test('rule timeline rejects unknown server enum values', () {
    for (final entry in [
      _ruleTimelineJson(kind: 'current_rule'),
      _ruleTimelineJson(status: 'current'),
      _ruleTimelineJson(changedFields: const ['teacher']),
    ]) {
      expect(
        () => ScheduleRuleTimelineEntry.fromMap(entry),
        throwsFormatException,
      );
    }
  });

  test('group plan exposes only the latest dated participant slice', () {
    final plan = SchedulePlan.fromMap({
      'id': 'plan-group',
      'kind': 'group',
      'title': 'Ансамбль',
      'groupId': 'group-1',
      'activeFrom': '2026-08-01',
      'status': 'active',
      'version': 2,
      'rows': <dynamic>[],
      'participants': [
        {
          'id': 'participant-old',
          'studentId': 'student-old',
          'subscriptionId': 'subscription-old',
          'effectiveFrom': '2026-08-01',
          'effectiveUntil': '2026-08-14',
          'version': 2,
        },
        {
          'id': 'participant-current-a',
          'studentId': 'student-a',
          'subscriptionId': 'subscription-a',
          'effectiveFrom': '2026-08-15',
          'effectiveUntil': null,
          'version': 2,
        },
        {
          'id': 'participant-current-b',
          'studentId': 'student-b',
          'subscriptionId': 'subscription-b',
          'effectiveFrom': '2026-08-15',
          'effectiveUntil': null,
          'version': 2,
        },
      ],
    });

    expect(
      plan.currentParticipants.map((participant) => participant.studentId),
      ['student-a', 'student-b'],
    );
    expect(plan.currentParticipants.first.command, {
      'studentId': 'student-a',
      'subscriptionId': 'subscription-a',
    });
  });

  test('ended plan keeps staff-visible completion history', () {
    final plan = SchedulePlan.fromMap({
      'id': 'plan-ended',
      'kind': 'individual',
      'title': 'Вокал',
      'studentId': 'student-1',
      'subscriptionId': 'subscription-1',
      'activeFrom': '2026-08-01',
      'activeUntil': '2026-08-12',
      'status': 'ended',
      'version': 2,
      'endedAt': '2026-08-12T12:00:00.000Z',
      'endedBy': 'manager-1',
      'endedByName': 'Мария Управляющая',
      'endReason': 'Клиент завершил занятия',
      'rows': <dynamic>[],
      'participants': <dynamic>[],
    });

    expect(plan.isActive, isFalse);
    expect(plan.endedAt, '2026-08-12T12:00:00.000Z');
    expect(plan.endedBy, 'manager-1');
    expect(plan.endedByName, 'Мария Управляющая');
    expect(plan.endReason, 'Клиент завершил занятия');
  });

  test('tray page preserves authoritative cursors and markers', () {
    final page = SchedulePlanTrayPage.fromMap({
      'planId': 'plan-1',
      'items': [
        {
          'id': 'lesson-1',
          'scheduledAt': '2026-08-12T13:00:00.000Z',
          'localDate': '2026-08-12',
          'localTime': '16:00',
          'state': 'rescheduled',
          'settlementMarkers': [
            {
              'key': 'paid_absence',
              'label': 'Оплачиваемый пропуск',
              'colorToken': 'blue',
            },
          ],
          'relationMarker': 'source',
          'predecessorId': null,
          'successorId': 'lesson-2',
          'teacher': {'id': 'teacher-1', 'name': 'Мария Иванова'},
          'room': {'id': 'room-1', 'name': 'Класс 1'},
        },
      ],
      'hasPrevious': true,
      'hasNext': true,
      'previousCursor': 'cursor-previous',
      'nextCursor': 'cursor-next',
    });

    expect(page.previousCursor, 'cursor-previous');
    expect(page.nextCursor, 'cursor-next');
    expect(page.items.single.relationMarker, 'source');
    expect(page.items.single.successorId, 'lesson-2');
    expect(page.items.single.settlementMarkers.single, {
      'key': 'paid_absence',
      'label': 'Оплачиваемый пропуск',
      'colorToken': 'blue',
    });
    expect(page.items.single.teacherName, 'Мария Иванова');
    expect(page.items.single.roomName, 'Класс 1');
  });
}

Map<String, dynamic> _ruleTimelineJson({
  String id = 'series-1',
  String kind = 'recurring_rule',
  String status = 'active',
  String? activeUntil,
  String? scheduledDate,
  List<String> changedFields = const [],
  int sortBucket = 0,
  String? lessonId,
}) => {
  'id': id,
  'kind': kind,
  'status': status,
  'activeFrom': '2026-09-01',
  'activeUntil': activeUntil,
  'scheduledDate': scheduledDate,
  'teacherId': 'teacher-1',
  'teacherName': 'Мария Иванова',
  'roomId': 'room-1',
  'roomName': 'Класс 1',
  'branchId': 'branch-1',
  'branchName': 'Центр',
  'weekday': 4,
  'beginTime': '15:30',
  'durationMinutes': 45,
  'changedFields': changedFields,
  'sortBucket': sortBucket,
  'sortAt': scheduledDate ?? activeUntil ?? '2026-09-01',
  'lessonId': lessonId,
  'sourceSeriesId': 'series-1',
};
