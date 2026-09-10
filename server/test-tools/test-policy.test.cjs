const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {adminUrl, databaseName, ownedDatabase, parseArguments, resultProblems, serverRoot} = require('./test-policy.cjs');

test('database destination rejects application DBs, remote hosts and URL host overrides', () => {
  assert.equal(adminUrl().hostname, '127.0.0.1');
  for (const value of [
    'postgresql://user:password@db.example.com/postgres',
    'postgresql://user:password@127.0.0.1/magiccrm',
    'postgresql://user:password@127.0.0.1/postgres?host=db.example.com',
    'postgresql://user:password@127.0.0.1/postgres#fragment',
    'http://user:password@127.0.0.1/postgres',
  ]) assert.throws(() => adminUrl(value), /must target loopback/);
  assert.throws(() => adminUrl('not a URL'), /Invalid TEST_POSTGRES_ADMIN_URL/);
});

test('cleanup only accepts database names belonging to this run', () => {
  const run = '0123456789abcdef';
  assert.equal(ownedDatabase(run, databaseName(run, 'template')), '"magiccrm_audit_fix_test_0123456789abcdef_template"');
  assert.doesNotThrow(() => ownedDatabase(run, databaseName(run, 'suite_aabbccdd')));
  for (const name of ['magiccrm', databaseName('1111111111111111', 'template'), 'magiccrm_audit_fix_test_0123456789abcdef_template;drop database postgres']) {
    assert.throws(() => ownedDatabase(run, name), /outside this test run/);
  }
  assert.throws(() => databaseName('bad', 'template'), /Invalid test run/);
});

test('full gate refuses selection, offline mode and Jest configuration overrides', () => {
  assert.throws(() => parseArguments(['--full', '--no-database']), /Full gate/);
  assert.throws(() => parseArguments(['--full', '--runTestsByPath', 'src/auth/session.service.spec.ts']), /Full gate/);
  for (const flag of ['--config', '--env', '--testNamePattern', '--passWithNoTests', '--shard', '--watch', '--listTests']) {
    assert.throws(() => parseArguments([flag]), /Unsupported test argument/);
  }
});

test('offline mode is explicit, bounded and rejects known PostgreSQL suites', () => {
  assert.throws(() => parseArguments(['--no-database']), /explicit/);
  assert.throws(() => parseArguments(['--no-database', '--runTestsByPath', 'src/access-control/actor-matrix-postgres.integration.spec.ts']), /PostgreSQL suite/);
  assert.throws(() => parseArguments(['--runTestsByPath', '../package.json']), /existing/);
  const selected = parseArguments(['--no-database', '--runTestsByPath', 'src/crm/crm.policy.spec.ts']);
  assert.equal(selected.paths.length, 1);
});

const file = path.join(serverRoot, 'src/auth/session.service.spec.ts');
const passed = {success: true, numTotalTests: 1, numPassedTests: 1, testResults: [{name: file}]};

test('a green exit with skipped or todo cases cannot become gate PASS', () => {
  for (const field of ['numPendingTests', 'numPendingTestSuites', 'numTodoTests']) {
    assert.ok(resultProblems({...passed, [field]: 1}, [file]).includes('Skipped/pending/todo tests are forbidden'));
  }
});

test('a passing partial inventory cannot impersonate a full run', () => {
  assert.deepEqual(resultProblems(passed, [file]), []);
  assert.ok(resultProblems(passed, [file, 'another.spec.ts']).some(p => p.includes('inventory')));
  assert.ok(resultProblems({...passed, numTotalTests: 0}, [file]).includes('No tests executed'));
  assert.ok(resultProblems({...passed, wasInterrupted: true}, [file]).some(p => p.includes('interrupted')));
});
