const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {resultProblems, serverRoot} = require('./test-policy.cjs');

test('real Jest skips/focus exit zero but fail the gate; offline pg calls are blocked', () => {
  fs.mkdirSync(path.join(serverRoot, 'coverage'), {recursive: true});
  const directory = fs.mkdtempSync(path.join(serverRoot, 'coverage/harness-'));
  for (const fixture of ['skipped', 'focused', 'offline']) {
    const source = path.join(__dirname, 'fixtures', `${fixture}.fixture.cjs`);
    const resultPath = path.join(directory, `${fixture}.json`);
    const config = {
      rootDir: __dirname, testEnvironment: 'node', transform: {},
      testMatch: ['**/*.fixture.cjs'],
      setupFilesAfterEnv: fixture === 'offline' ? [path.join(__dirname, 'no-database.cjs')] : [],
    };
    const result = spawnSync(process.execPath, [require.resolve('jest/bin/jest'), '--config', JSON.stringify(config), '--runInBand', '--json', '--outputFile', resultPath, '--runTestsByPath', source], {cwd: serverRoot, encoding: 'utf8', windowsHide: true});
    assert.equal(result.status, 0, result.stderr);
    const reported = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
    const problems = resultProblems(reported, [source]);
    if (fixture === 'offline') assert.deepEqual(problems, []);
    else assert.ok(problems.includes('Skipped/pending/todo tests are forbidden'));
  }
});
