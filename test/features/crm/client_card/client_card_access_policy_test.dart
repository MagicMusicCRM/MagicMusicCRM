import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_access_policy.dart';

void main() {
  test(
    'legacy role fallbacks preserve exact finance schedule and task policy',
    () {
      final cases =
          <
            ({
              String role,
              bool finance,
              bool schedule,
              bool tasks,
              String historyLabel,
            })
          >[
            (
              role: 'teacher',
              finance: false,
              schedule: false,
              tasks: true,
              historyLabel: 'История и задачи',
            ),
            (
              role: 'admin',
              finance: true,
              schedule: true,
              tasks: false,
              historyLabel: 'История',
            ),
            (
              role: 'manager',
              finance: true,
              schedule: true,
              tasks: true,
              historyLabel: 'История и задачи',
            ),
            (
              role: 'unknown',
              finance: false,
              schedule: false,
              tasks: false,
              historyLabel: 'История',
            ),
          ];

      for (final entry in cases) {
        final access = ClientCardAccessPolicy.project(
          actorRole: entry.role,
          capabilitySnapshot: null,
          hasStudentHalf: true,
        );
        expect(access.canReadClientFinance, entry.finance, reason: entry.role);
        expect(access.canReadSchedule, entry.schedule, reason: entry.role);
        expect(access.canWriteSchedule, entry.schedule, reason: entry.role);
        expect(access.canReadTasks, entry.tasks, reason: entry.role);
        expect(
          access.sections.singleWhere((item) => item.$3 == 'history_tasks').$2,
          entry.historyLabel,
          reason: entry.role,
        );
      }
    },
  );

  test(
    'capabilities override schedule and task fallbacks but not teacher finance',
    () {
      const snapshot = CapabilitySnapshot(
        accountId: 'teacher-1',
        role: 'teacher',
        accessVersion: 1,
        capabilities: {
          'commerce.client_finance.read',
          'schedule.lesson.write',
          'workflow.task.read',
        },
        scopes: {},
      );

      final access = ClientCardAccessPolicy.project(
        actorRole: 'teacher',
        capabilitySnapshot: snapshot,
        hasStudentHalf: true,
      );

      expect(access.canReadClientFinance, isFalse);
      expect(access.canWriteSchedule, isTrue);
      expect(access.canReadSchedule, isTrue);
      expect(access.canReadTasks, isTrue);
      expect(
        access.sections.map((item) => item.$3),
        isNot(contains('payments')),
      );
      expect(
        access.sections.map((item) => item.$3),
        isNot(contains('subscriptions')),
      );
    },
  );

  test(
    'lead keeps subscriptions while student and converted hide finance sections',
    () {
      final lead = ClientCardAccessPolicy.project(
        actorRole: 'teacher',
        capabilitySnapshot: null,
        hasStudentHalf: false,
      );
      final student = ClientCardAccessPolicy.project(
        actorRole: 'teacher',
        capabilitySnapshot: null,
        hasStudentHalf: true,
      );

      expect(lead.sections.map((item) => item.$3).toList(), [
        'overview',
        'lessons',
        'subscriptions',
        'progress',
        'history_tasks',
        'contacts',
        'documents',
      ]);
      expect(student.sections.map((item) => item.$3).toList(), [
        'overview',
        'lessons',
        'progress',
        'history_tasks',
        'contacts',
        'documents',
      ]);
      expect(
        () => student.sections.add(student.sections.first),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'explicit capability snapshot keeps admin tasks fail closed when absent',
    () {
      const snapshot = CapabilitySnapshot(
        accountId: 'admin-1',
        role: 'admin',
        accessVersion: 1,
        capabilities: {'crm.client.read.basic'},
        scopes: {},
      );

      final access = ClientCardAccessPolicy.project(
        actorRole: 'admin',
        capabilitySnapshot: snapshot,
        hasStudentHalf: true,
      );

      expect(access.canReadClientFinance, isTrue);
      expect(access.canReadSchedule, isFalse);
      expect(access.canWriteSchedule, isFalse);
      expect(access.canReadTasks, isFalse);
      expect(
        access.sections.singleWhere((item) => item.$3 == 'history_tasks').$2,
        'История',
      );
    },
  );
}
