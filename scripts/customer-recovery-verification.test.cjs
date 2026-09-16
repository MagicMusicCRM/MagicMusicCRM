const { test } = require('node:test');
const assert = require('node:assert/strict');
const { automaticTrialDraft } = require('./customer-recovery-verification.cjs');
test('recovery request excludes server-owned teacher rate snapshots and resolved overrides', () => {
  const stored = { settlementTypeKey: 'trial_lesson', teacherCompensationRuleKey: 'standard',
    teacherCompensationSource: 'manual', teacherCreditedDurationMinutes: 45,
    teacherCompensationValueMinor: '70000', teacherRateSnapshot: { rateMinor: '70000' },
    clientDecisions: [{ clientId: 'synthetic', chargeType: 'none', chargeDurationMinutes: 0 }] };
  assert.deepEqual(automaticTrialDraft(stored), {
    settlementTypeKey: 'trial_lesson', teacherCompensationRuleKey: 'trial_lesson',
    teacherCompensationSource: 'automatic', clientDecisions: stored.clientDecisions,
  });
  assert.equal(stored.teacherCompensationSource, 'manual');
  assert.deepEqual(stored.teacherRateSnapshot, { rateMinor: '70000' });
});
