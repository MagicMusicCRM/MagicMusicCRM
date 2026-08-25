import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_form_rules.dart';

void main() {
  const policy = LessonEditorDecisionPolicy();

  group('create validation', () {
    test('none funding is legal only for a zero-charge settlement', () {
      final paid = _catalogItem(
        hourShareBasisPoints: 10000,
        fixedPenaltyMinor: '0',
      );
      final free = _catalogItem(
        hourShareBasisPoints: 0,
        fixedPenaltyMinor: '0',
      );
      final paidDraft = _draft(clientChargeType: 'none');
      final freeDraft = _draft(clientChargeType: 'none');

      expect(
        policy
            .validate(
              session: _createSession(paidDraft),
              draft: paidDraft,
              references: _references(settlements: [paid]),
            )
            .message,
        'Для платного списания выберите абонемент или личный счёт',
      );
      expect(
        policy
            .validate(
              session: _createSession(freeDraft),
              draft: freeDraft,
              references: _references(settlements: [free]),
            )
            .isValid,
        isTrue,
      );
    });

    test('requires participant, schedule resources, and three decisions', () {
      final valid = _draft();
      final cases = <LessonEditorDraft>[
        valid.copyWith(client: null),
        valid.copyWith(teacherId: null),
        valid.copyWith(branchId: null),
        valid.copyWith(roomId: null),
        valid.copyWith(settlementTypeKey: null),
        valid.copyWith(compensationRuleKey: null),
        valid.copyWith(clientChargeType: 'subscription', subscriptionId: null),
      ];

      for (final draft in cases) {
        expect(
          policy
              .validate(
                session: _createSession(draft),
                draft: draft,
                references: _references(),
              )
              .message,
          'Заполните обязательные поля корректно',
        );
      }
    });

    test('requires a valid custom compensation and its reason', () {
      final rule = _catalogItem(
        key: 'teacher-percent',
        mode: 'percent',
        value: '10000',
      );
      final missingValue = _draft(compensationRuleKey: rule.key);
      final missingReason = missingValue.copyWith(
        compensationValueMinor: '12500',
      );
      final valid = missingReason.copyWith(
        plannedSettlementReason: 'Индивидуальная договорённость',
      );
      final references = _references(compensationRules: [rule]);

      expect(
        policy
            .validate(
              session: _createSession(missingValue),
              draft: missingValue,
              references: references,
            )
            .message,
        'Введите корректный процент или сумму оплаты преподавателю',
      );
      expect(
        policy
            .validate(
              session: _createSession(missingReason),
              draft: missingReason,
              references: references,
            )
            .message,
        'Укажите причину индивидуального значения оплаты преподавателю',
      );
      expect(
        policy
            .validate(
              session: _createSession(valid),
              draft: valid,
              references: references,
            )
            .isValid,
        isTrue,
      );
    });
  });

  group('funding defaults', () {
    test('selects free, subscription, and personal-account defaults', () {
      final subscriptionReferences = _references(
        subscriptions: [_subscription('subscription-a')],
      );
      final student = _draft(subscriptionId: 'stale-subscription');
      final lead = _draft(
        client: const LessonClientRef(
          type: 'lead',
          id: 'lead-a',
          label: 'Мария',
        ),
        subscriptionId: 'subscription-a',
      );
      final free = _draft(
        clientChargeType: 'personal_account',
        subscriptionId: 'subscription-a',
        settlementTypeKey: 'free',
      );

      expect(
        policy.applyFundingDefault(
          draft: student,
          references: subscriptionReferences,
        ),
        isA<LessonEditorDraft>()
            .having(
              (value) => value.clientChargeType,
              'funding',
              'subscription',
            )
            .having(
              (value) => value.subscriptionId,
              'subscription',
              'subscription-a',
            ),
      );
      expect(
        policy.applyFundingDefault(
          draft: lead,
          references: subscriptionReferences,
        ),
        isA<LessonEditorDraft>()
            .having(
              (value) => value.clientChargeType,
              'funding',
              'personal_account',
            )
            .having((value) => value.subscriptionId, 'subscription', isNull),
      );
      expect(
        policy.applyFundingDefault(
          draft: free,
          references: _references(
            settlements: [
              _catalogItem(
                key: 'free',
                hourShareBasisPoints: 0,
                fixedPenaltyMinor: '0',
              ),
            ],
          ),
        ),
        isA<LessonEditorDraft>()
            .having((value) => value.clientChargeType, 'funding', 'none')
            .having((value) => value.subscriptionId, 'subscription', isNull),
      );
    });
  });

  group('payload construction', () {
    test('serializes only the schedule fields using Moscow wall time', () {
      expect(policy.schedulePayload(_draft()), {
        'teacherId': 'teacher-a',
        'branchId': 'branch-a',
        'roomId': 'room-a',
        'scheduledAt': '2026-08-26T10:00:00.000Z',
        'durationMinutes': 60,
      });
    });

    test(
      'builds three independent create decisions and compatibility hints',
      () {
        final draft = _draft(
          settlementTypeKey: 'standard',
          compensationRuleKey: 'teacher-percent',
          compensationValueMinor: '12500',
          clientChargeType: 'subscription',
          subscriptionId: 'subscription-a',
          plannedSettlementReason: '  Индивидуальная договорённость  ',
        );
        final payload = policy.createPayload(
          session: _createSession(draft),
          draft: draft,
          references: _references(
            teachers: [_teacher('teacher-a', currentRate: 1800)],
            subscriptions: [_subscription('subscription-a')],
            compensationRules: [
              _catalogItem(
                key: 'teacher-percent',
                mode: 'percent',
                value: '10000',
              ),
            ],
          ),
        );

        expect(payload, {
          'teacherId': 'teacher-a',
          'branchId': 'branch-a',
          'roomId': 'room-a',
          'scheduledAt': '2026-08-26T10:00:00.000Z',
          'durationMinutes': 60,
          'clientRef': {'type': 'student', 'id': 'student-a'},
          'isTrial': false,
          'completionType': 'standard',
          'clientChargeType': 'subscription',
          'clientChargeValue': 1,
          'teacherCompensationType': 'hourly',
          'teacherCompensationValue': 1800,
          'financialDecision': {
            'settlementTypeKey': 'standard',
            'teacherCompensationRuleKey': 'teacher-percent',
            'teacherCompensationValueMinor': '12500',
          },
          'plannedSettlementReason': 'Индивидуальная договорённость',
          'subscriptionId': 'subscription-a',
        });
      },
    );

    test(
      'keeps optional financial value, reason, subscription, and lead note sparse',
      () {
        final standardDraft = _draft();
        final fallbackLeadDrafts = ['Лид без имени', 'Клиент без имени']
            .map(
              (label) => _draft(
                client: LessonClientRef(
                  type: 'lead',
                  id: 'lead-a',
                  label: label,
                ),
              ),
            )
            .toList();
        final namedLeadDraft = _draft(
          client: const LessonClientRef(
            type: 'lead',
            id: 'lead-a',
            label: 'Мария',
          ),
        );
        final standardPayload = policy.createPayload(
          session: _createSession(standardDraft),
          draft: standardDraft,
          references: _references(),
        );
        final fallbackLeadPayloads = fallbackLeadDrafts
            .map(
              (draft) => policy.createPayload(
                session: _createSession(draft),
                draft: draft,
                references: _references(),
              ),
            )
            .toList();
        final namedLeadPayload = policy.createPayload(
          session: _createSession(namedLeadDraft, leadNoteSource: '  Мария  '),
          draft: namedLeadDraft,
          references: _references(),
        );

        expect(standardPayload['financialDecision'], {
          'settlementTypeKey': 'standard',
          'teacherCompensationRuleKey': 'standard',
        });
        expect(standardPayload, isNot(contains('plannedSettlementReason')));
        expect(standardPayload, isNot(contains('subscriptionId')));
        expect(standardPayload, isNot(contains('notes')));
        for (final payload in fallbackLeadPayloads) {
          expect(payload, isNot(contains('notes')));
        }
        expect(namedLeadPayload['notes'], 'Занятие по лиду: Мария');
      },
    );
  });

  group('edit decisions', () {
    test('rejects a missing version and a no-op edit', () {
      final draft = _draft();
      final missingVersion = _editSession(draft, expectedVersion: null);
      final unchanged = _editSession(draft);

      expect(
        policy
            .validate(
              session: missingVersion,
              draft: draft,
              references: _references(),
            )
            .message,
        'Обновите расписание: версия занятия не получена',
      );
      expect(
        policy
            .validate(
              session: unchanged,
              draft: draft,
              references: _references(),
            )
            .message,
        'Измените параметры расписания или оплату преподавателю',
      );
      expect(
        policy.hasScheduleChanges(session: unchanged, draft: draft),
        isFalse,
      );
      expect(
        policy.hasFinancialChanges(session: unchanged, draft: draft),
        isFalse,
      );
    });

    test('reschedule wins; completed financial edits use correction', () {
      final draft = _draft();
      final planned = _editSession(draft, lifecycleState: 'planned');
      final completed = _editSession(
        draft,
        lifecycleState: 'successfully_completed',
      );
      final rescheduled = draft.copyWith(
        localStart: DateTime(2026, 8, 26, 14),
        compensationRuleKey: 'teacher-fixed',
      );
      final financialOnly = draft.copyWith(
        compensationRuleKey: 'teacher-fixed',
        compensationValueMinor: '250000',
      );

      final rescheduleRequest = policy.editRequest(
        session: completed,
        draft: rescheduled,
      );
      final correctionRequest = policy.editRequest(
        session: completed,
        draft: financialOnly,
      );
      final plannedRequest = policy.editRequest(
        session: planned,
        draft: financialOnly,
      );

      expect(rescheduleRequest.operation, LessonDecisionOperation.reschedule);
      expect(rescheduleRequest.successor, policy.schedulePayload(rescheduled));
      expect(correctionRequest.operation, LessonDecisionOperation.correction);
      expect(correctionRequest.successor, isNull);
      expect(
        plannedRequest.operation,
        LessonDecisionOperation.plannedSettlement,
      );
      expect(plannedRequest.initialSettlementTypeKey, 'standard');
      expect(plannedRequest.initialCompensationRuleKey, 'teacher-fixed');
      expect(plannedRequest.initialCompensationValueMinor, '250000');
    });

    test('maps lifecycle aliases to the financial edit operation', () {
      final draft = _draft(
        compensationRuleKey: 'teacher-fixed',
        compensationValueMinor: '250000',
      );
      const cases = {
        'successfully_completed': LessonDecisionOperation.correction,
        'completed': LessonDecisionOperation.correction,
        'done': LessonDecisionOperation.correction,
        'planned': LessonDecisionOperation.plannedSettlement,
      };

      for (final entry in cases.entries) {
        final request = policy.editRequest(
          session: _editSession(_draft(), lifecycleState: entry.key),
          draft: draft,
        );

        expect(request.operation, entry.value, reason: entry.key);
      }
    });
  });

  group('compensation and snapshot boundaries', () {
    test('keeps the percent boundary and money precision exact', () {
      expect(
        parseCompensationValueMinor(mode: 'percent', rawValue: '200'),
        '20000',
      );
      expect(
        parseCompensationValueMinor(mode: 'percent', rawValue: '200,01'),
        isNull,
      );
      expect(
        parseCompensationValueMinor(mode: 'fixed', rawValue: '12,345'),
        isNull,
      );
      expect(formatCompensationMinorInput('1250'), '12,50');
    });

    test(
      'formats client and teacher snapshot hints without changing decisions',
      () {
        final references = _references(
          teachers: [_teacher('teacher-a', currentRate: 1800)],
          subscriptions: [
            _subscription(
              'subscription-a',
              packagePrice: 6000,
              lessonsTotal: 4,
            ),
          ],
          compensationRules: [_catalogItem(key: 'standard', mode: 'standard')],
        );
        final draft = _draft(durationMinutes: 90);

        expect(
          policy.clientChargeSnapshotLabel(
            draft: draft,
            references: references,
          ),
          '2 250 ₽',
        );
        expect(
          policy.teacherCompensationSnapshotLabel(
            draft: draft,
            references: references,
          ),
          'Стандартная ставка преподавателя · 1 800 ₽/ч',
        );
      },
    );
  });
}

LessonDecisionCatalogItem _catalogItem({
  String key = 'standard',
  String? mode,
  String value = '0',
  int hourShareBasisPoints = 10000,
  String fixedPenaltyMinor = '0',
}) => LessonDecisionCatalogItem(
  key: key,
  label: key,
  order: 0,
  mode: mode,
  value: value,
  hourShareBasisPoints: hourShareBasisPoints,
  fixedPenaltyMinor: fixedPenaltyMinor,
);

LessonEditorDraft _draft({
  DateTime? localStart,
  int durationMinutes = 60,
  LessonClientRef? client = const LessonClientRef(
    type: 'student',
    id: 'student-a',
    label: 'Анна',
  ),
  String clientChargeType = 'personal_account',
  String? subscriptionId,
  String? settlementTypeKey = 'standard',
  String? compensationRuleKey = 'standard',
  String? compensationValueMinor,
  String plannedSettlementReason = '',
}) => LessonEditorDraft(
  localStart: localStart ?? DateTime(2026, 8, 26, 13),
  durationMinutes: durationMinutes,
  isTrial: false,
  completionType: 'standard',
  clientChargeType: clientChargeType,
  client: client,
  teacherId: 'teacher-a',
  branchId: 'branch-a',
  roomId: 'room-a',
  subscriptionId: subscriptionId,
  settlementTypeKey: settlementTypeKey,
  compensationRuleKey: compensationRuleKey,
  compensationValueMinor: compensationValueMinor,
  plannedSettlementReason: plannedSettlementReason,
);

LessonEditorSession _createSession(
  LessonEditorDraft draft, {
  String? leadNoteSource,
}) => LessonEditorSession(
  draft: draft,
  snapshot: null,
  seededClient: draft.client,
  leadNoteSource: leadNoteSource,
);

LessonEditorSession _editSession(
  LessonEditorDraft draft, {
  int? expectedVersion = 4,
  String lifecycleState = 'planned',
}) => LessonEditorSession(
  draft: draft,
  snapshot: LessonEditorSnapshot(
    lessonId: 'lesson-a',
    expectedVersion: expectedVersion,
    rawLesson: {
      'id': 'lesson-a',
      'version': expectedVersion,
      'lifecycle_state': lifecycleState,
    },
    clientLocked: true,
    initialSchedulePayload: const {
      'teacherId': 'teacher-a',
      'branchId': 'branch-a',
      'roomId': 'room-a',
      'scheduledAt': '2026-08-26T10:00:00.000Z',
      'durationMinutes': 60,
    },
    initialCompensationRuleKey: 'standard',
    initialCompensationValueMinor: null,
  ),
  seededClient: draft.client,
);

LessonEditorReferenceState _references({
  List<LessonEditorReferenceItem> teachers = const [],
  List<LessonEditorReferenceItem> subscriptions = const [],
  List<LessonDecisionCatalogItem>? settlements,
  List<LessonDecisionCatalogItem>? compensationRules,
}) => LessonEditorReferenceState(
  teachers: teachers,
  clients: const [],
  branches: const [],
  rooms: const [],
  subscriptions: subscriptions,
  catalog: LessonDecisionCatalog(
    settlementTypes: settlements ?? [_catalogItem()],
    compensationRules: compensationRules ?? [_catalogItem()],
  ),
);

LessonEditorReferenceItem _teacher(String id, {required num currentRate}) =>
    LessonEditorReferenceItem(
      id: id,
      label: id,
      raw: {'id': id, 'current_rate': currentRate},
    );

LessonEditorReferenceItem _subscription(
  String id, {
  num packagePrice = 6000,
  num lessonsTotal = 4,
}) => LessonEditorReferenceItem(
  id: id,
  label: id,
  raw: {'id': id, 'package_price': packagePrice, 'lessons_total': lessonsTotal},
);
