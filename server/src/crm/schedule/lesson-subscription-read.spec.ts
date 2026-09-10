import { DatabaseService } from '../../db/database.service';
import { LessonRow } from '../crm-mappers';
import { resolvePlannedSubscriptionReads } from './lesson-subscription-read';

const oldId = '10000000-0000-4000-8000-000000000001';
const newId = '10000000-0000-4000-8000-000000000002';
const row = (changes: Partial<LessonRow> = {}) => ({
  id: 'lesson', lifecycle_state: 'scheduled', financial_decision_is_plan: true,
  subscription_id: oldId,
  financial_decision: { clientDecisions: [{ clientId: 'student', subscriptionId: oldId }] },
  client_financial_baseline: [{ clientId: 'student', subscriptionId: oldId }],
  ...changes,
} as LessonRow);

describe('Lesson subscription read projection', () => {
  it('resolves a batch once and leaves the source snapshot and effective facts intact', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [{ source_id: oldId, current_id: newId }] });
    const database = { query } as unknown as DatabaseService;
    const original = row();
    const historical = row({ lifecycle_state: 'successfully_completed' });
    const correction = row({ financial_decision_is_plan: false });
    const effective = row({ client_financial_baseline: [{ clientId: 'student', subscriptionId: oldId, _effectiveFact: true }] });
    const result = await resolvePlannedSubscriptionReads(database, [original, historical, correction, effective]);
    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0][1]).toEqual([[oldId]]);
    expect(result[0]).toMatchObject({ subscription_id: newId,
      financial_decision: { clientDecisions: [{ subscriptionId: newId }] },
      client_financial_baseline: [{ subscriptionId: newId }] });
    expect(original.subscription_id).toBe(oldId);
    expect(original.financial_decision?.clientDecisions).toEqual([{ clientId: 'student', subscriptionId: oldId }]);
    expect(result[1]).toBe(historical);
    expect(result[2]).toBe(correction);
    expect(result[3]?.client_financial_baseline?.[0]?.subscriptionId).toBe(oldId);
  });

  it('does not query masked financial fields or completed history', async () => {
    const query = jest.fn();
    const masked = row({ subscription_id: null, financial_decision: null, client_financial_baseline: null });
    await resolvePlannedSubscriptionReads({ query } as unknown as DatabaseService,
      [masked, row({ lifecycle_state: 'cancelled' }), row({ lifecycle_state: 'successfully_completed' })]);
    expect(query).not.toHaveBeenCalled();
  });

  it('retains the original binding when no sole active successor exists', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const result = await resolvePlannedSubscriptionReads({ query } as unknown as DatabaseService, [row()]);
    expect(result[0]?.subscription_id).toBe(oldId);
  });
});
