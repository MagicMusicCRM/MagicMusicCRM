import type { PoolClient } from 'pg';
import type { DatabaseService } from '../../db/database.service';
import { buildCrmConfigurationBaseline } from '../crm-configuration-baseline';
import { LessonSettlementService } from './lesson-settlement.service';
import type { ResolvePlannedLessonSettlementInput } from './lesson-settlement.port';

const baseline = buildCrmConfigurationBaseline([]);
const service = new LessonSettlementService({} as DatabaseService);
const client = { query: jest.fn().mockResolvedValue({ rows: [{
  settlement_revision_id: 'revision-trial', compensation_revision_id: 'revision-trial',
  settlement_types: baseline.lessonSettlementTypes, compensation_rules: baseline.teacherCompensationRules,
}] }) } as unknown as PoolClient;
function input(): ResolvePlannedLessonSettlementInput {
  return {
    branchId: 'branch', durationMinutes: 60, actorUserId: 'admin', requiredClientIds: ['student'],
    authorization: { actor: { userId: 'admin', role: 'admin' } as never, capabilityKey: 'schedule.lesson.write' },
    decision: { settlementTypeKey: 'trial_lesson', teacherCompensationRuleKey: 'trial_lesson',
      teacherCompensationSource: 'automatic',
      clientDecisions: [{ clientId: 'student', chargeType: 'subscription', subscriptionId: 'paid-sub', chargeDurationMinutes: 60 }],
    },
  };
}

describe('Trial lesson policy', () => {
  it('defaults to the named zero-pay rule and removes paid client funding', async () => {
    const result = await service.resolvePlannedDecision(client, input());
    expect(result).toMatchObject({ teacherCompensationRuleKey: 'trial_lesson', teacherCompensationSource: 'automatic', teacherCreditedDurationMinutes: 60 });
    expect(result.clientDecisions?.[0]).toMatchObject({ chargeType: 'none', chargeDurationMinutes: 0 });
    expect(result.clientDecisions?.[0].subscriptionId).toBeUndefined();
    expect(baseline.teacherCompensationRules.find(rule => rule.stableKey === 'trial_lesson')).toMatchObject({ mode: 'none', value: '0' });
  });
  it('lets an admin select the standard rule without changing the base rate', async () => {
    const request = input();
    request.reasonText = 'Клиент приобрёл абонемент';
    request.decision.teacherCompensationRuleKey = 'standard';
    request.decision.teacherCompensationSource = 'manual';
    const result = await service.resolvePlannedDecision(client, request);
    expect(result).toMatchObject({ teacherCompensationRuleKey: 'standard', teacherCompensationSource: 'manual', teacherCreditedDurationMinutes: 60 });
    expect(result.clientDecisions?.[0].chargeDurationMinutes).toBe(0);
  });
  it('preserves a manual rule when an edit submits automatic or omitted fields', async () => {
    for (const automatic of [false, true]) {
      const request = input();
      request.preservedTeacherDecision = { teacherCompensationRuleKey: 'standard', teacherCompensationSource: 'manual', teacherCreditedDurationMinutes: 60 };
      if (!automatic) request.decision = { settlementTypeKey: 'trial_lesson', clientDecisions: request.decision.clientDecisions } as never;
      expect(await service.resolvePlannedDecision(client, request)).toMatchObject(request.preservedTeacherDecision);
    }
  });
  it('permits a second explicit selection after the first manual change', async () => {
    const request = input();
    request.preservedTeacherDecision = { teacherCompensationRuleKey: 'standard', teacherCompensationSource: 'manual', teacherCreditedDurationMinutes: 60 };
    request.decision.teacherCompensationRuleKey = 'trial_lesson';
    request.decision.teacherCompensationSource = 'manual';
    request.reasonText = 'Исправление ошибочного выбора';
    expect(await service.resolvePlannedDecision(client, request)).toMatchObject({ teacherCompensationRuleKey: 'trial_lesson', teacherCompensationSource: 'manual' });
  });
  it('requires a reason for a manual selection', async () => {
    const request = input();
    request.decision.teacherCompensationRuleKey = 'standard';
    request.decision.teacherCompensationSource = 'manual';
    await expect(service.resolvePlannedDecision(client, request)).rejects.toMatchObject({ response: { code: 'TEACHER_COMPENSATION_REASON_REQUIRED' } });
  });
  it('does not grant an admin arbitrary value or duration overrides', async () => {
    for (const override of [{ teacherCompensationValueMinor: '10000' }, { teacherCreditedDurationMinutes: 30 }]) {
      const request = input();
      request.reasonText = 'Недопустимое изменение';
      request.decision = { ...request.decision, teacherCompensationRuleKey: 'fixed', teacherCompensationSource: 'manual', ...override };
      await expect(service.resolvePlannedDecision(client, request)).rejects.toMatchObject({ response: { code: 'TEACHER_COMPENSATION_PERMISSION_REQUIRED' } });
    }
  });
  it('does not allow paid participant overrides inside a trial', async () => {
    const request = input();
    request.decision.clientDecisions![0].settlementTypeKey = 'lesson';
    await expect(service.resolvePlannedDecision(client, request)).rejects.toMatchObject({ response: { code: 'TRIAL_CLIENT_OVERRIDE_NOT_ALLOWED' } });
  });
});
