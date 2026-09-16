'use strict';

// Read-only gate for the explicitly approved 0157 recovery. Never changes health.
function validateRecoveryBaseline(health, rows, migration, expectedCsv) {
  const ids = expectedCsv.split(',');
  if (!ids.length || ids.length > 100 || new Set(ids).size !== ids.length ||
      ids.some(id => !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/.test(id))) {
    throw Error('Invalid expected dead-letter IDs');
  }
  const expectedChecks = {database: 'ok', migrations: 'ok',
    lessonCompletionWorker: 'ok', platformOutbox: 'degraded', v4Rollout: 'ok'};
  if (health.status !== 'degraded' || health.latestMigrationId !== migration ||
      Object.keys(health.checks || {}).length !== 5 ||
      Object.entries(expectedChecks).some(([key,value]) => health.checks[key] !== value) ||
      health.platformOutbox?.pending !== 0 ||
      health.platformOutbox?.deadLetter !== ids.length ||
      health.platformOutbox?.oldestDueSeconds !== null ||
      !Array.isArray(rows) || rows.length !== ids.length) {
    throw Error('Readiness degradation does not match the approved recovery');
  }
  if (rows.some(row => !ids.includes(row.event_id) ||
      row.event_type !== 'crm.lesson_teacher_rate.changed' ||
      row.aggregate_type !== 'schedule:teacher-rate-bulk' || row.aggregate_id !== 'global' ||
      row.payload?.action !== 'bulk_set' || row.published_at !== null ||
      !row.dead_lettered_at || row.attempts !== 10 || row.claimed_at !== null ||
      row.claimed_by !== null) || new Set(rows.map(row => row.event_id)).size !== ids.length) {
    throw Error('Dead letters do not match the approved teacher-rate events');
  }
}
module.exports = {validateRecoveryBaseline};
if (require.main === module) {
  const [health, rows] = require('node:fs').readFileSync(0, 'utf8').trim().split('\n').map(JSON.parse);
  validateRecoveryBaseline(health, rows, process.argv[2], process.argv[3]);
  console.log('APPROVED_TEACHER_RATE_RECOVERY_BASELINE|PASS');
}
