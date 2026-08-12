import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';

void main() {
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
