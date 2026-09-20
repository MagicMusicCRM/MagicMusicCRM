const {TestEnvironment} = require('jest-environment-node');
const {Pool} = require('pg');
const {randomBytes} = require('node:crypto');
const {adminUrl, databaseName, ownedDatabase} = require('./test-policy.cjs');

module.exports = class IsolatedEnvironment extends TestEnvironment {
  async setup() {
    await super.setup();
    this.runId = process.env.MAGICCRM_TEST_RUN_ID;
    const source = adminUrl(process.env.MAGICCRM_TEST_ADMIN_URL);
    const template = databaseName(this.runId, 'template');
    this.name = databaseName(this.runId, `suite_${randomBytes(4).toString('hex')}`);
    const pool = new Pool({connectionString: source.toString(), max: 1, connectionTimeoutMillis: 5000});
    try {
      await pool.query(`create database ${ownedDatabase(this.runId, this.name)} template ${ownedDatabase(this.runId, template)}`);
      this.created = true;
    } finally { await pool.end(); }
    source.pathname = '/' + this.name;
    for (const key of ['V4_PLATFORM_TEST_DATABASE_URL', 'DATABASE_URL', 'MIGRATION_DATABASE_URL']) this.global.process.env[key] = source.toString();
  }

  async teardown() {
    try { await super.teardown(); } finally {
      if (this.created) {
        const pool = new Pool({connectionString: adminUrl(process.env.MAGICCRM_TEST_ADMIN_URL).toString(), max: 1, connectionTimeoutMillis: 5000});
        try { await pool.query(`drop database ${ownedDatabase(this.runId, this.name)} with (force)`); }
        finally { await pool.end(); }
      }
    }
  }
};
