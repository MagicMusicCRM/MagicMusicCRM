import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_form_rules.dart';

void main() {
  group('compensation minor values', () {
    test('formats minor units for the compensation input', () {
      const cases = <(String?, String)>[
        ('0', '0'),
        ('12', '0,12'),
        ('100', '1'),
        ('1250', '12,50'),
        ('not-a-number', '0'),
      ];

      for (final entry in cases) {
        expect(formatCompensationMinorInput(entry.$1), entry.$2);
      }
    });

    test('parses valid percent and money inputs into minor-unit strings', () {
      const cases = <(String, String, String?)>[
        ('percent', '12,5', '1250'),
        ('percent', '200', '20000'),
        ('fixed', '12,50', '1250'),
        ('hourly', '1 000.05', '100005'),
      ];

      for (final entry in cases) {
        expect(
          parseCompensationValueMinor(mode: entry.$1, rawValue: entry.$2),
          entry.$3,
        );
      }
    });

    test('rejects invalid percent and money inputs', () {
      const cases = <(String?, String)>[
        ('percent', '-1'),
        ('percent', '200.01'),
        ('percent', 'text'),
        ('fixed', '-1'),
        ('fixed', '12.345'),
        ('hourly', 'text'),
        ('none', '10'),
        ('standard', '10'),
      ];

      for (final entry in cases) {
        expect(
          parseCompensationValueMinor(mode: entry.$1, rawValue: entry.$2),
          isNull,
        );
      }
    });
  });

  group('lesson schedule changes', () {
    test('treats equivalent snake and camel fields as unchanged', () {
      final lesson = <String, dynamic>{
        'teacher_id': 'teacher-1',
        'branch_id': 'branch-1',
        'room_id': 'room-1',
        'scheduled_at': '2026-07-19T10:00:00+03:00',
        'duration_minutes': 60,
      };
      final successor = <String, dynamic>{
        'teacherId': 'teacher-1',
        'branchId': 'branch-1',
        'roomId': 'room-1',
        'scheduledAt': '2026-07-19T07:00:00.000Z',
        'durationMinutes': 60,
      };

      expect(
        hasLessonScheduleChanges(lesson: lesson, successor: successor),
        isFalse,
      );
    });

    test('detects schedule changes after UTC-normalizing timestamps', () {
      final lesson = <String, dynamic>{
        'teacherId': 'teacher-1',
        'branchId': 'branch-1',
        'roomId': 'room-1',
        'scheduledAt': '2026-07-19T07:00:00.000Z',
        'durationMinutes': 60,
      };
      final successor = <String, dynamic>{
        'teacherId': 'teacher-1',
        'branchId': 'branch-1',
        'roomId': 'room-1',
        'scheduledAt': '2026-07-19T07:01:00.000Z',
        'durationMinutes': 60,
      };

      expect(
        hasLessonScheduleChanges(lesson: lesson, successor: successor),
        isTrue,
      );
    });

    test('detects each changed schedule resource or duration', () {
      final lesson = <String, dynamic>{
        'teacher_id': 'teacher-1',
        'branch_id': 'branch-1',
        'room_id': 'room-1',
        'scheduled_at': '2026-07-19T10:00:00+03:00',
        'duration_minutes': 60,
      };
      final successor = <String, dynamic>{
        'teacherId': 'teacher-1',
        'branchId': 'branch-1',
        'roomId': 'room-1',
        'scheduledAt': '2026-07-19T07:00:00.000Z',
        'durationMinutes': 60,
      };
      final cases = <(String, Map<String, dynamic>)>[
        ('teacher', {...successor, 'teacherId': 'teacher-2'}),
        ('branch', {...successor, 'branchId': 'branch-2'}),
        ('room', {...successor, 'roomId': 'room-2'}),
        ('duration', {...successor, 'durationMinutes': 90}),
      ];

      for (final entry in cases) {
        expect(
          hasLessonScheduleChanges(lesson: lesson, successor: entry.$2),
          isTrue,
          reason: entry.$1,
        );
      }
    });
  });
}
