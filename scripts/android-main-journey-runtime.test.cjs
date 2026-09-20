const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateMainEvidence, validatePersistedMove } = require('./android-main-journey-runtime.cjs');
test('main journey requires the current fixture and both UI scenarios', () => {
  const evidence = { fixtureLessonId: 'current', steps: ['LOGIN', 'NAVIGATION', 'MOVE', 'REOPEN'], completed: true };
  assert.doesNotThrow(() => validateMainEvidence(evidence, 'current'));
  assert.throws(() => validateMainEvidence(evidence, 'old'));
  assert.throws(() => validateMainEvidence({ ...evidence, steps: ['LOGIN'] }, 'current'));
  assert.throws(() => validateMainEvidence({ ...evidence, completed: false }, 'current'));
});
test('persisted verification uses the real camelCase API contract and preserves trial rules', () => {
  const fixture = { lessonId: 'old', rooms: ['room0', 'room1'] };
  const evidence = { scheduledAt: '2027-01-12T09:30:00.000Z' };
  const row = { id: 'new', status: 'scheduled', roomId: 'room1', scheduledAt: evidence.scheduledAt,
    durationMinutes: 45, settlementTypeKey: 'trial_lesson', teacherCompensationRuleKey: 'trial_lesson', clientChargeType: 'none' };
  assert.deepEqual(validatePersistedMove({ items: [row] }, fixture, evidence), row);
  for (const changed of [{ roomId: 'room0' }, { durationMinutes: 60 }, { id: 'old' },
    { teacherCompensationRuleKey: 'standard' }, { clientChargeType: 'subscription' }]) {
    assert.throws(() => validatePersistedMove({ items: [{ ...row, ...changed }] }, fixture, evidence));
  }
});
