import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_initial_mapper.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_form_rules.dart';

void main() {
  const policy = LessonEditorDecisionPolicy();

  test(
    'reference defaults keep catalog decisions and branch duration typed',
    () {
      final draft = _draft(
        durationMinutes: 60,
        clientChargeType: 'none',
        settlementTypeKey: null,
        compensationRuleKey: null,
      );
      final references = LessonEditorReferenceState(
        teachers: const [],
        clients: const [],
        branches: const [],
        rooms: const [],
        subscriptions: const [],
        catalog: LessonDecisionCatalog(
          defaultDurationMinutes: 75,
          settlementTypes: [
            _catalogItem(
              key: 'free',
              hourShareBasisPoints: 0,
              fixedPenaltyMinor: '0',
            ),
          ],
          compensationRules: [
            _catalogItem(key: 'fixed', mode: 'fixed', value: '125000'),
          ],
        ),
      );

      final configured = policy.applyReferenceDefaults(
        _createSession(draft),
        draft,
        references,
        true,
      );
      final explicit = policy.applyReferenceDefaults(
        _createSession(draft),
        draft,
        references,
        false,
      );

      expect(configured.draft.durationMinutes, 75);
      expect(explicit.draft.durationMinutes, 60);
      expect(configured.draft.settlementTypeKey, 'free');
      expect(configured.draft.compensationRuleKey, 'fixed');
      expect(configured.draft.compensationValueMinor, '125000');
      expect(configured.draft.clientChargeType, 'none');
    },
  );

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

    test(
      'explicit subscription funding restores the first active subscription',
      () {
        final references = _references(
          subscriptions: [
            _subscription('subscription-first'),
            _subscription('subscription-second'),
          ],
        );
        final personalAccount = _draft(
          clientChargeType: 'personal_account',
          subscriptionId: null,
        );

        final subscription = policy.fundingSelection(
          personalAccount,
          references,
          'subscription',
        );
        final restoredPersonalAccount = policy.fundingSelection(
          subscription,
          references,
          'personal_account',
        );

        expect(subscription.clientChargeType, 'subscription');
        expect(subscription.subscriptionId, 'subscription-first');
        expect(restoredPersonalAccount.clientChargeType, 'personal_account');
        expect(restoredPersonalAccount.subscriptionId, isNull);
      },
    );
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
    test(
      'legacy percent catalog default becomes the immutable no-op baseline',
      () {
        final mapped = const LessonEditorInitialMapper().map(
          const LessonEditorInitialInput(
            initialDate: null,
            initialRoomId: null,
            initialBranchId: null,
            initialDurationMinutes: null,
            initialIsTrial: false,
            lesson: {
              'id': 'lesson-percent',
              'version': 4,
              'student_id': 'student-a',
              'teacher_id': 'teacher-a',
              'branch_id': 'branch-a',
              'room_id': 'room-a',
              'scheduled_at': '2026-08-26T10:00:00.000Z',
              'duration_minutes': 60,
              'teacher_compensation_type': 'percent',
            },
          ),
        );
        final references = _references(
          compensationRules: [
            _catalogItem(
              key: 'teacher-percent',
              mode: 'percent',
              value: '12500',
            ),
          ],
        );

        final defaults = policy.applyReferenceDefaults(
          mapped,
          mapped.draft,
          references,
          false,
        );

        expect(defaults.draft.compensationRuleKey, 'teacher-percent');
        expect(defaults.draft.compensationValueMinor, '12500');
        expect(
          defaults.session.snapshot?.initialCompensationRuleKey,
          'teacher-percent',
        );
        expect(
          defaults.session.snapshot?.initialCompensationValueMinor,
          '12500',
        );
        expect(
          policy.hasFinancialChanges(
            session: defaults.session,
            draft: defaults.draft,
          ),
          isFalse,
        );
        expect(
          policy
              .validate(
                session: defaults.session,
                draft: defaults.draft,
                references: references,
              )
              .message,
          'Измените параметры расписания или оплату преподавателю',
        );
      },
    );

    test(
      'legacy fixed and hourly defaults become the immutable no-op baseline',
      () {
        const mapper = LessonEditorInitialMapper();
        for (final mode in const ['fixed', 'hourly']) {
          final mapped = mapper.map(
            LessonEditorInitialInput(
              initialDate: null,
              initialRoomId: null,
              initialBranchId: null,
              initialDurationMinutes: null,
              initialIsTrial: false,
              lesson: {
                'id': 'lesson-$mode',
                'version': 4,
                'student_id': 'student-a',
                'teacher_id': 'teacher-a',
                'branch_id': 'branch-a',
                'room_id': 'room-a',
                'scheduled_at': '2026-08-26T10:00:00.000Z',
                'duration_minutes': 60,
                'teacher_compensation_type': mode,
                'teacher_compensation_value': 1250,
                if (mode == 'hourly')
                  'teacher_compensation_rule_key': 'teacher-hourly',
              },
            ),
          );
          final references = _references(
            compensationRules: [
              _catalogItem(key: 'teacher-$mode', mode: mode, value: '99900'),
            ],
          );
          final defaults = policy.applyReferenceDefaults(
            mapped,
            mapped.draft,
            references,
            false,
          );
          final draft = defaults.draft;

          expect(draft.compensationRuleKey, 'teacher-$mode');
          expect(draft.compensationValueMinor, '125000');
          expect(
            defaults.session.snapshot?.initialCompensationRuleKey,
            'teacher-$mode',
          );
          expect(
            defaults.session.snapshot?.initialCompensationValueMinor,
            '125000',
          );
          expect(
            policy.hasFinancialChanges(session: defaults.session, draft: draft),
            isFalse,
            reason: mode,
          );
          expect(
            policy
                .validate(
                  session: defaults.session,
                  draft: draft,
                  references: references,
                )
                .message,
            'Измените параметры расписания или оплату преподавателю',
            reason: mode,
          );
        }
      },
    );

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

    test('typed edit reducer covers every action and ownership signal', () {
      final draft = _draft(
        subscriptionId: 'subscription-old',
        compensationRuleKey: 'teacher-fixed',
        compensationValueMinor: '100000',
        plannedSettlementReason: 'Старая причина',
      );
      final references = _references(
        subscriptions: [
          _subscription('subscription-first'),
          _subscription('subscription-second'),
        ],
        settlements: [_catalogItem(key: 'paid')],
        compensationRules: [
          _catalogItem(key: 'teacher-fixed', mode: 'fixed', value: '250000'),
        ],
      );
      final cases =
          <
            ({
              String name,
              LessonEditorEdit edit,
              Matcher draft,
              bool scheduleChanged,
              String? branchToLoad,
            })
          >[
            (
              name: 'branch',
              edit: const LessonReferenceEdit(
                LessonReferenceTarget.branch,
                'branch-b',
              ),
              draft: isA<LessonEditorDraft>()
                  .having((value) => value.branchId, 'branch', 'branch-b')
                  .having((value) => value.teacherId, 'teacher', isNull)
                  .having((value) => value.roomId, 'room', isNull)
                  .having(
                    (value) => value.settlementTypeKey,
                    'settlement',
                    isNull,
                  )
                  .having(
                    (value) => value.compensationRuleKey,
                    'compensation rule',
                    isNull,
                  )
                  .having(
                    (value) => value.compensationValueMinor,
                    'compensation value',
                    isNull,
                  )
                  .having(
                    (value) => value.plannedSettlementReason,
                    'reason',
                    isEmpty,
                  ),
              scheduleChanged: true,
              branchToLoad: 'branch-b',
            ),
            (
              name: 'room',
              edit: const LessonReferenceEdit(
                LessonReferenceTarget.room,
                'room-b',
              ),
              draft: isA<LessonEditorDraft>().having(
                (value) => value.roomId,
                'room',
                'room-b',
              ),
              scheduleChanged: true,
              branchToLoad: null,
            ),
            (
              name: 'teacher',
              edit: const LessonReferenceEdit(
                LessonReferenceTarget.teacher,
                'teacher-b',
              ),
              draft: isA<LessonEditorDraft>().having(
                (value) => value.teacherId,
                'teacher',
                'teacher-b',
              ),
              scheduleChanged: true,
              branchToLoad: null,
            ),
            (
              name: 'settlement',
              edit: const LessonReferenceEdit(
                LessonReferenceTarget.settlement,
                'paid',
              ),
              draft: isA<LessonEditorDraft>()
                  .having(
                    (value) => value.settlementTypeKey,
                    'settlement',
                    'paid',
                  )
                  .having(
                    (value) => value.clientChargeType,
                    'funding',
                    'subscription',
                  )
                  .having(
                    (value) => value.subscriptionId,
                    'subscription',
                    'subscription-first',
                  ),
              scheduleChanged: false,
              branchToLoad: null,
            ),
            (
              name: 'compensation rule',
              edit: const LessonReferenceEdit(
                LessonReferenceTarget.compensationRule,
                'teacher-fixed',
              ),
              draft: isA<LessonEditorDraft>()
                  .having(
                    (value) => value.compensationRuleKey,
                    'rule',
                    'teacher-fixed',
                  )
                  .having(
                    (value) => value.compensationValueMinor,
                    'value',
                    '250000',
                  )
                  .having(
                    (value) => value.plannedSettlementReason,
                    'reason',
                    isEmpty,
                  ),
              scheduleChanged: false,
              branchToLoad: null,
            ),
            (
              name: 'subscription',
              edit: const LessonReferenceEdit(
                LessonReferenceTarget.subscription,
                'subscription-second',
              ),
              draft: isA<LessonEditorDraft>().having(
                (value) => value.subscriptionId,
                'subscription',
                'subscription-second',
              ),
              scheduleChanged: false,
              branchToLoad: null,
            ),
            (
              name: 'completion',
              edit: const LessonTextEdit(
                LessonTextTarget.completion,
                'standard.success',
              ),
              draft: isA<LessonEditorDraft>().having(
                (value) => value.completionType,
                'completion',
                'standard.success',
              ),
              scheduleChanged: false,
              branchToLoad: null,
            ),
            (
              name: 'compensation value',
              edit: const LessonTextEdit(
                LessonTextTarget.compensationValue,
                '1250',
              ),
              draft: isA<LessonEditorDraft>().having(
                (value) => value.compensationValueMinor,
                'compensation value',
                '125000',
              ),
              scheduleChanged: false,
              branchToLoad: null,
            ),
            (
              name: 'settlement reason',
              edit: const LessonTextEdit(
                LessonTextTarget.settlementReason,
                'Новая причина',
              ),
              draft: isA<LessonEditorDraft>().having(
                (value) => value.plannedSettlementReason,
                'reason',
                'Новая причина',
              ),
              scheduleChanged: false,
              branchToLoad: null,
            ),
            (
              name: 'funding',
              edit: const LessonTextEdit(
                LessonTextTarget.funding,
                'subscription',
              ),
              draft: isA<LessonEditorDraft>()
                  .having(
                    (value) => value.clientChargeType,
                    'funding',
                    'subscription',
                  )
                  .having(
                    (value) => value.subscriptionId,
                    'subscription',
                    'subscription-first',
                  ),
              scheduleChanged: false,
              branchToLoad: null,
            ),
            (
              name: 'duration',
              edit: const LessonDurationEdit(75),
              draft: isA<LessonEditorDraft>().having(
                (value) => value.durationMinutes,
                'duration',
                75,
              ),
              scheduleChanged: true,
              branchToLoad: null,
            ),
            (
              name: 'trial',
              edit: const LessonTrialEdit(true),
              draft: isA<LessonEditorDraft>().having(
                (value) => value.isTrial,
                'trial',
                isTrue,
              ),
              scheduleChanged: false,
              branchToLoad: null,
            ),
          ];

      for (final entry in cases) {
        final result = policy.applyEdit(draft, references, entry.edit);

        expect(result.draft, entry.draft, reason: entry.name);
        expect(
          result.scheduleChanged,
          entry.scheduleChanged,
          reason: entry.name,
        );
        expect(result.branchToLoad, entry.branchToLoad, reason: entry.name);
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
