const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const serverRoot = path.resolve(__dirname, '..');
const defaultAdminUrl = 'postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/postgres';

function adminUrl(value = defaultAdminUrl) {
  let url;
  try { url = new URL(value); } catch { throw new Error('Invalid TEST_POSTGRES_ADMIN_URL.'); }
  if (!['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      url.pathname !== '/postgres' || url.search || url.hash || !url.username) {
    throw new Error('TEST_POSTGRES_ADMIN_URL must target loopback /postgres, without query parameters.');
  }
  return url;
}

function databasePrefix(runId) {
  if (!/^[a-f0-9]{16}$/.test(runId || '')) throw new Error('Invalid test run identity.');
  return `magiccrm_audit_fix_test_${runId}`;
}

function databaseName(runId, suffix) {
  if (!/^(template|suite_[a-f0-9]{8})$/.test(suffix)) throw new Error('Invalid test database suffix.');
  return `${databasePrefix(runId)}_${suffix}`;
}

function ownedDatabase(runId, name) {
  const prefix = databasePrefix(runId);
  if (name !== `${prefix}_template` && !new RegExp(`^${prefix}_suite_[a-f0-9]{8}$`).test(name)) {
    throw new Error('Refusing to operate on a database outside this test run.');
  }
  return `"${name}"`;
}

function sourceFiles(directory) {
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) return sourceFiles(full);
    return entry.isFile() && /\.(ts|sql|cjs|json|js)$/.test(entry.name) ? [full] : [];
  }).sort();
}

function specs() {
  return sourceFiles(path.join(serverRoot, 'src')).filter(p => p.endsWith('.spec.ts'));
}

function fingerprint() {
  const files = ['src', 'db/migrations', 'test-tools'].flatMap(dir => sourceFiles(path.join(serverRoot, dir)));
  const scripts = path.join(serverRoot, 'scripts');
  if (fs.existsSync(scripts)) files.push(...sourceFiles(scripts));
  for (const file of ['package.json', 'package-lock.json', 'jest.config.js', 'tsconfig.json']) files.push(path.join(serverRoot, file));
  const contracts = path.resolve(serverRoot, '../contracts');
  if (fs.existsSync(contracts)) files.push(...sourceFiles(contracts));
  const hash = crypto.createHash('sha256');
  for (const file of files.sort()) {
    hash.update(path.relative(serverRoot, file).replaceAll('\\', '/') + '\0');
    hash.update(fs.readFileSync(file));
    hash.update('\0');
  }
  return hash.digest('hex');
}

function parseArguments(args) {
  const options = {full: false, noDatabase: false, coverage: false, paths: [], jest: []};
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--full') options.full = true;
    else if (arg === '--no-database') options.noDatabase = true;
    else if (arg === '--coverage') options.coverage = true;
    else if (['--silent', '--verbose', '--runInBand', '--json'].includes(arg)) options.jest.push(arg);
    else if (arg === '--runTestsByPath') {
      while (args[i + 1] && !args[i + 1].startsWith('--')) options.paths.push(args[++i]);
      if (!options.paths.length) throw new Error('--runTestsByPath requires at least one test file.');
    } else throw new Error(`Unsupported test argument: ${arg}. Use --runTestsByPath, --coverage, --silent or --verbose.`);
  }
  if (options.full && (options.paths.length || options.noDatabase)) throw new Error('Full gate cannot select files or disable PostgreSQL.');
  if (options.noDatabase && !options.paths.length) throw new Error('--no-database requires an explicit --runTestsByPath selection.');
  const available = new Set(specs());
  options.paths = [...new Set(options.paths.map(p => path.resolve(serverRoot, p)))];
  for (const file of options.paths) {
    if (!available.has(file)) throw new Error('Selected test must be an existing src/**/*.spec.ts file.');
    if (options.noDatabase && /V4_PLATFORM_TEST_DATABASE_URL|from\s+['"]pg['"]/.test(fs.readFileSync(file, 'utf8'))) {
      throw new Error('PostgreSQL suite cannot run with --no-database.');
    }
  }
  return options;
}

function resultProblems(result, expectedFiles) {
  const problems = [];
  if (!result.success || result.wasInterrupted || result.numFailedTests || result.numFailedTestSuites || result.numRuntimeErrorTestSuites) problems.push('Jest failed or was interrupted');
  if (!(result.numTotalTests > 0)) problems.push('No tests executed');
  if (result.numPendingTests || result.numPendingTestSuites || result.numTodoTests) problems.push('Skipped/pending/todo tests are forbidden');
  const actual = (result.testResults || []).map(s => path.resolve(s.name)).sort();
  if (JSON.stringify(actual) !== JSON.stringify([...expectedFiles].sort())) problems.push('Executed suites do not match the requested inventory');
  return problems;
}

module.exports = {serverRoot, adminUrl, databasePrefix, databaseName, ownedDatabase, specs, fingerprint, parseArguments, resultProblems};
