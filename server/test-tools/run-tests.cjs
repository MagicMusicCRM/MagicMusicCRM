const fs = require('node:fs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {randomBytes} = require('node:crypto');
const {Pool} = require('pg');
const {serverRoot, adminUrl, databasePrefix, databaseName, ownedDatabase, specs, fingerprint, parseArguments, resultProblems} = require('./test-policy.cjs');

async function main() {
  const options = parseArguments(process.argv.slice(2));
  // Never infer a test destination from application/database environment variables.
  const admin = options.noDatabase ? null : adminUrl(process.env.TEST_POSTGRES_ADMIN_URL);
  const runId = randomBytes(8).toString('hex');
  const directory = path.join(serverRoot, 'coverage/test-runs', runId);
  fs.mkdirSync(directory, {recursive: true});
  const expected = options.paths.length ? options.paths : specs();
  const before = fingerprint();
  const env = {...process.env, NODE_ENV: 'test'};
  for (const key of ['V4_PLATFORM_TEST_DATABASE_URL', 'DATABASE_URL', 'MIGRATION_DATABASE_URL', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD', 'PGOPTIONS', 'PGSERVICE', 'PGSERVICEFILE']) delete env[key];
  env.MAGICCRM_TEST_RUN_ID = runId;
  env.MAGICCRM_TEST_ADMIN_URL = admin?.toString() || '';
  const summary = {runId, mode: options.noDatabase ? 'offline-selection' : options.paths.length ? 'isolated-selection' : 'full', expectedSuites: expected.length, sourceSha256: before, passed: false};
  let child;
  let interrupted = false;
  const stop = () => { interrupted = true; child?.kill('SIGTERM'); };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  const run = async args => {
    if (interrupted) throw new Error('Test run interrupted.');
    return await new Promise((resolve, reject) => {
      child = spawn(process.execPath, args, {cwd: serverRoot, env, stdio: 'inherit', windowsHide: true});
      child.once('error', reject);
      child.once('exit', (code, signal) => { child = null; resolve(signal ? 1 : code ?? 1); });
    });
  };
  let pool;
  let templateCreated = false;
  try {
    if (admin) {
      pool = new Pool({connectionString: admin.toString(), max: 1, connectionTimeoutMillis: 5000});
      const template = databaseName(runId, 'template');
      await pool.query(`create database ${ownedDatabase(runId, template)}`);
      templateCreated = true;
      const target = new URL(admin);
      target.pathname = '/' + template;
      env.DATABASE_URL = target.toString();
      env.MIGRATION_DATABASE_URL = target.toString();
      if (await run(['-r', 'ts-node/register', path.join(__dirname, 'bootstrap.cjs')]) !== 0) throw new Error('Test template migration/bootstrap failed.');
    }
    const resultFile = path.join(directory, 'jest-results.json');
    const config = {
      ...require('../jest.config.js'), rootDir: serverRoot,
      testEnvironment: options.noDatabase ? 'node' : path.join(__dirname, 'isolated-environment.cjs'),
      ...(options.noDatabase ? {setupFilesAfterEnv: [path.join(__dirname, 'no-database.cjs')]} : {}),
      coverageDirectory: path.join(directory, 'coverage'),
    };
    const configFile = path.join(directory, 'jest-config.json');
    fs.writeFileSync(configFile, JSON.stringify(config, null, 2));
    console.log(`Test scope: ${summary.mode}; ${expected.length} suites; evidence: ${directory}`);
    const args = ['--max-old-space-size=8192', '--experimental-vm-modules', require.resolve('jest/bin/jest'), '--config', configFile, '--runInBand', '--json', '--outputFile', resultFile, ...options.jest];
    if (options.coverage) args.push('--coverage');
    if (options.paths.length) args.push('--runTestsByPath', ...options.paths);
    const code = await run(args);
    if (!fs.existsSync(resultFile)) throw new Error('Jest did not produce a result; no PASS evidence.');
    const result = JSON.parse(fs.readFileSync(resultFile, 'utf8'));
    const problems = resultProblems(result, expected);
    if (code !== 0 || interrupted) problems.push('Test process failed or was interrupted');
    if (fingerprint() !== before) problems.push('Source files changed during the run');
    const suites = result.testResults.map(suite => ({
      path: path.relative(serverRoot, suite.name).replaceAll('\\', '/'),
      cases: suite.assertionResults.length,
      elapsedMs: suite.endTime - suite.startTime,
    }));
    fs.writeFileSync(path.join(directory, 'suite-results.json'), JSON.stringify(suites, null, 2) + '\n');
    Object.assign(summary, {tests: result.numTotalTests, passedTests: result.numPassedTests, skippedTests: result.numPendingTests, largestSuites: [...suites].sort((a, b) => b.cases - a.cases).slice(0, 5), problems});
    if (problems.length) throw new Error(problems.join('; '));
    summary.passed = true;
  } finally {
    try {
      if (templateCreated) {
        // Recover clones left by failed setup/teardown or an interrupted Jest process.
        const prefix = databasePrefix(runId) + '_';
        const remaining = await pool.query('select datname from pg_database where left(datname, length($1)) = $1', [prefix]);
        for (const {datname} of remaining.rows) await pool.query(`drop database ${ownedDatabase(runId, datname)} with (force)`);
      }
      summary.cleanup = 'complete';
    } catch (error) {
      summary.passed = false;
      summary.cleanup = 'failed';
      throw error;
    } finally {
      await pool?.end();
      process.removeListener('SIGINT', stop);
      process.removeListener('SIGTERM', stop);
      fs.writeFileSync(path.join(directory, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
    }
  }
  console.log(`PASS (${summary.mode}): ${summary.passedTests} tests; zero skips; temporary database cleanup complete.`);
}

main().catch(error => { console.error(`Test gate failed: ${error.message}`); process.exitCode = 1; });
