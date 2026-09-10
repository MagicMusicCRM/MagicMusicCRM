const {Pool} = require('pg');
const {MigrationRunner} = require('../src/db/migration-runner');
const {runBackfill} = require('../src/platform/rollout/v4/backfill');

(async () => {
  const pool = new Pool({connectionString: process.env.MIGRATION_DATABASE_URL, max: 1});
  try {
    const applied = await new MigrationRunner(pool).up();
    const report = await runBackfill(pool, 'apply');
    if (report.summary.reviewQueue) throw new Error('Clean test bootstrap requires manual mapping.');
    console.log(`Clean template: ${applied.length} migrations applied; backfill completed.`);
  } finally { await pool.end(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
