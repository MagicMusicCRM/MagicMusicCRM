const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateRecoveryBaseline: check} = require('../teacher-rate-recovery-baseline.cjs');
const id = '10000000-0000-4000-8000-000000000001';
function fixture() { return {
  health: {status:'degraded', latestMigrationId:'0156_trial_lesson_catalog', checks:{
    database:'ok',migrations:'ok',lessonCompletionWorker:'ok',platformOutbox:'degraded',v4Rollout:'ok'},
    platformOutbox:{pending:0,deadLetter:1,oldestDueSeconds:null}},
  rows:[{event_id:id,event_type:'crm.lesson_teacher_rate.changed',aggregate_type:'schedule:teacher-rate-bulk',
    aggregate_id:'global',payload:{action:'bulk_set'},published_at:null,dead_lettered_at:'2026-09-16',
    attempts:10,claimed_at:null,claimed_by:null}],
}; }
test('accepts only pinned teacher-rate delivery failure with all other checks healthy',()=>{
  const {health,rows}=fixture(); check(health,rows,'0156_trial_lesson_catalog',id);
});
for (const [label,change] of Object.entries({
  database:f=>f.health.checks.database='error', rollout:f=>f.health.checks.v4Rollout='blocked',
  worker:f=>f.health.checks.lessonCompletionWorker='degraded', pending:f=>f.health.platformOutbox.pending=1,
  count:f=>f.health.platformOutbox.deadLetter=2, type:f=>f.rows[0].event_type='unknown.changed',
  identity:f=>f.rows[0].event_id='20000000-0000-4000-8000-000000000001',
  delivered:f=>f.rows[0].published_at='2026-09-16', claimed:f=>f.rows[0].claimed_by='worker',
  payload:f=>f.rows[0].payload.action='unknown', schema:f=>f.health.latestMigrationId='0155',
  extraCheck:f=>f.health.checks.extra='error',
})) test(`rejects changed ${label}`,()=>{const f=fixture();change(f);
  assert.throws(()=>check(f.health,f.rows,'0156_trial_lesson_catalog',id));});
test('rejects empty or duplicate approval IDs',()=>{const f=fixture();
  for(const ids of ['',`${id},${id}`]) assert.throws(()=>check(f.health,f.rows,'0156_trial_lesson_catalog',ids));});
