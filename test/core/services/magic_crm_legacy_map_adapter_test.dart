import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

void main() {
  group('CRM legacy map adapter', () {
    test('lead keeps legacy ids, snake_case keys, and null defaults', () {
      final result = legacyLeadForTesting({
        'id': 'lead-1',
        'firstName': 'Алина',
        'lastName': 'Соколова',
        'phone': '+79990000000',
        'email': 'alina@example.test',
        'source': 'site',
        'sourceId': 'source-1',
        'notes': 'Перезвонить',
        'assignedTo': 'profile-1',
        'customData': 'invalid',
        'createdBy': 'user-1',
        'createdAt': '2026-08-22T10:00:00Z',
        'updatedAt': '2026-08-22T11:00:00Z',
        'appealAt': null,
        'appealAtSource': null,
        'age': null,
        'ageMonths': null,
        'ageSource': null,
        'blacklisted': false,
        'blacklistReason': null,
      });

      expect(
        result.keys,
        orderedEquals([
          'id',
          'status_id',
          'status_key',
          'status',
          'status_label',
          'name',
          'first_name',
          'last_name',
          'phone',
          'email',
          'source',
          'source_id',
          'notes',
          'assigned_to',
          'custom_data',
          'hollihop_id',
          'branch_id',
          'created_by',
          'created_at',
          'updated_at',
          'appeal_at',
          'appeal_at_source',
          'age',
          'age_months',
          'age_source',
          'blacklisted',
          'blacklist_reason',
        ]),
      );
      expect(result['id'], 'lead-1');
      expect(result['status'], 'new');
      expect(result['status_id'], isNull);
      expect(result['custom_data'], isEmpty);
      expect(result['hollihop_id'], isNull);
      expect(result['branch_id'], isNull);
      expect(result['appeal_at'], isNull);
      expect(result['blacklisted'], isFalse);
    });

    test(
      'lesson keeps relationships, name parts, and nullable payment data',
      () {
        final result = legacyLessonForTesting({
          'id': 'lesson-1',
          'version': 4,
          'studentId': 'student-1',
          'groupId': 'group-1',
          'leadId': null,
          'teacherId': 'teacher-1',
          'branchId': 'branch-1',
          'roomId': 'room-1',
          'scheduledAt': '2026-08-23T15:00:00Z',
          'durationMinutes': 60,
          'status': 'scheduled',
          'isTrial': false,
          'notes': null,
          'teacherRate': 1500,
          'appliedTeacherRate': null,
          'paidAmount': null,
          'studentName': 'Алина Соколова',
          'teacherName': 'Иван Петров',
          'leadName': null,
          'branchName': 'Центр',
          'roomName': 'Класс 1',
          'groupName': 'Фортепиано',
          'groupPricePerLesson': 2200,
          'completionType': null,
          'clientChargeType': null,
          'clientChargeValue': null,
          'teacherCompensationType': null,
          'teacherCompensationValue': null,
          'settlementTypeKey': null,
          'teacherCompensationRuleKey': null,
          'teacherCompensationValueMinor': null,
          'subscriptionId': null,
          'snapshotTrial': null,
          'snapshotValidationState': null,
          'lifecycleState': null,
          'reservationState': null,
          'settlementFailureCode': null,
        });

        expect(
          result.keys,
          orderedEquals([
            'id',
            'version',
            'student_id',
            'group_id',
            'lead_id',
            'teacher_id',
            'branch_id',
            'room_id',
            'scheduled_at',
            'duration_minutes',
            'status',
            'is_trial',
            'notes',
            'teacher_rate',
            'applied_teacher_rate',
            'paid_amount',
            'student_name',
            'teacher_name',
            'lead_name',
            'branch_name',
            'room_name',
            'group_name',
            'group_price_per_lesson',
            'completion_type',
            'client_charge_type',
            'client_charge_value',
            'teacher_compensation_type',
            'teacher_compensation_value',
            'settlement_type_key',
            'teacher_compensation_rule_key',
            'teacher_compensation_value_minor',
            'subscription_id',
            'snapshot_trial',
            'snapshot_validation_state',
            'lifecycle_state',
            'reservation_state',
            'settlement_failure_code',
            'student_first_name',
            'student_last_name',
            'teacher_first_name',
            'teacher_last_name',
            'groups',
            'rooms',
            'branches',
          ]),
        );
        expect(result['paid_amount'], isNull);
        expect(result['student_first_name'], 'Алина');
        expect(result['teacher_last_name'], 'Петров');
        expect(result['groups'], {
          'id': 'group-1',
          'name': 'Фортепиано',
          'price_per_lesson': 2200,
        });
        expect(result['rooms'], {
          'id': 'room-1',
          'name': 'Класс 1',
          'branches': {'id': 'branch-1', 'name': 'Центр'},
        });
        expect(result['branches'], {'id': 'branch-1', 'name': 'Центр'});
      },
    );

    test('payment keeps student profile and description fallback', () {
      final result = legacyPaymentForTesting({
        'id': 'payment-1',
        'studentId': 'student-1',
        'amount': 3500,
        'currency': 'RUB',
        'paymentDate': '2026-08-23',
        'method': 'cash',
        'externalId': null,
        'notes': null,
        'description': 'Оплата за август',
        'createdBy': 'user-1',
        'createdAt': '2026-08-23T12:00:00Z',
        'studentName': 'Алина',
      });

      expect(
        result.keys,
        orderedEquals([
          'id',
          'student_id',
          'amount',
          'currency',
          'payment_date',
          'method',
          'type',
          'external_id',
          'notes',
          'description',
          'created_by',
          'created_at',
          'students',
        ]),
      );
      expect(result['type'], 'cash');
      expect(result['description'], 'Оплата за август');
      expect(result['external_id'], isNull);
      expect(result['students'], {
        'id': 'student-1',
        'first_name': 'Алина',
        'last_name': '',
      });
    });

    test('subscription keeps active label and original nullable values', () {
      final result = legacySubscriptionForTesting({
        'id': 'subscription-1',
        'studentId': 'student-1',
        'lessonsTotal': 8,
        'lessonsUsed': 2,
        'startsAt': '2026-08-01',
        'expiresAt': null,
        'status': 'active',
        'createdAt': '2026-08-01T10:00:00Z',
        'updatedAt': null,
        'packageName': 'Стандарт',
        'packagePrice': 16000,
        'paidAmount': null,
      });

      expect(
        result.keys,
        orderedEquals([
          'id',
          'student_id',
          'lessons_total',
          'lessons_used',
          'starts_at',
          'expires_at',
          'valid_until',
          'status',
          'type',
          'created_at',
          'updated_at',
          'package_name',
          'package_price',
          'paid_amount',
        ]),
      );
      expect(result['type'], 'Абонемент');
      expect(result['expires_at'], isNull);
      expect(result['valid_until'], isNull);
      expect(result['paid_amount'], isNull);
    });

    test(
      'student balance keeps nested student profile when source is absent',
      () {
        final result = legacyStudentBalanceForTesting({
          'studentId': 'student-1',
          'balance': -500,
          'totalPaid': 2500,
          'totalCost': 3000,
          'updatedAt': null,
          'student': null,
        });

        expect(
          result.keys,
          orderedEquals([
            'student_id',
            'balance',
            'total_paid',
            'total_cost',
            'updated_at',
            'students',
          ]),
        );
        expect(result['balance'], -500);
        expect(result['updated_at'], isNull);
        expect(result['students'], {
          'profiles': {'first_name': null, 'last_name': null, 'phone': null},
        });
      },
    );

    test('family member keeps complete snake_case shape and false default', () {
      final result = legacyFamilyMemberForTesting({
        'id': 'family-1',
        'entityType': 'student',
        'entityId': 'student-1',
        'role': 'mother',
        'isPrimaryContact': null,
        'name': null,
      });

      expect(
        result.keys,
        orderedEquals([
          'id',
          'entity_type',
          'entity_id',
          'role',
          'is_primary_contact',
          'name',
        ]),
      );
      expect(result['entity_type'], 'student');
      expect(result['entity_id'], 'student-1');
      expect(result['is_primary_contact'], isFalse);
      expect(result['name'], isNull);
    });
  });
}
