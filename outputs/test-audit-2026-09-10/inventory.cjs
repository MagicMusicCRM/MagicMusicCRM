const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '../..');
const files = (...dirs) => cp.execFileSync('rg', ['--files', ...dirs], {cwd: root, encoding: 'utf8'})
  .trim().split(/\r?\n/).map(p => p.replaceAll('\\', '/'));
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const release = JSON.parse(read('dist/release218/backend-results.json'));
const previous = new Map(release.testResults.map(s => [
  'server/' + s.name.replaceAll('\\', '/').split('/server/').pop(), s,
]));
const paths = files('test', 'integration_test', 'server/src')
  .filter(p => p.endsWith('_test.dart') || p.endsWith('.spec.ts')).sort();
const rows = paths.map(p => {
  const s = read(p);
  const old = previous.get(p);
  return {
    path: p,
    layer: p.startsWith('test/') ? 'flutter' : p.startsWith('integration_test/') ? 'device' : 'server',
    lines: s.split('\n').length,
    declarations_approx: (s.match(/\b(?:testWidgets|test|it)(?:\.(?:each|skip|only|todo))?\s*\(/g) || []).length,
    release218_cases: old ? old.assertionResults.length : '',
    release218_suite_ms: old ? old.endTime - old.startTime : '',
    reads_files_marker: /readAsStringSync|readFileSync|readAsString\(|readFile\(/.test(s),
    database_marker: /V4_PLATFORM_TEST_DATABASE_URL|new Pool\(|PGlite/.test(s),
    pglite_marker: /PGlite/.test(s),
    skip_marker: /describe\.skip|\b(?:it|test)\.(?:skip|todo)|\bskip\s*:/.test(s),
    sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(root, p))).digest('hex'),
  };
});
const headers = Object.keys(rows[0]);
const csv = value => '"' + String(value).replaceAll('"', '""') + '"';
fs.writeFileSync(path.join(__dirname, 'inventory.csv'), '\ufeff' + [headers, ...rows.map(r => headers.map(h => r[h]))]
  .map(r => r.map(csv).join(',')).join('\n') + '\n');
const comparePaths = files('test', 'integration_test', 'lib', 'server/src', 'server/db/migrations');
const missing = [], different = [];
for (const p of comparePaths) {
  const snapshot = path.join(root, 'dist/release218/source-selected', p);
  if (!fs.existsSync(snapshot)) missing.push(p);
  else if (!fs.readFileSync(path.join(root, p)).equals(fs.readFileSync(snapshot))) different.push(p);
}
const summary = {
  measuredAt: new Date().toISOString(),
  sourceComparison: {compared: comparePaths.length, missing, different},
  releaseEvidence: {tests: release.numTotalTests, passed: release.numPassedTests, pending: release.numPendingTests, failed: release.numFailedTests},
  layers: ['flutter', 'device', 'server'].map(layer => {
    const a = rows.filter(r => r.layer === layer);
    return {layer, files: a.length, declarationsApprox: a.reduce((n, r) => n + r.declarations_approx, 0),
      fileReadingMarkers: a.filter(r => r.reads_files_marker).length,
      pgliteMarkers: a.filter(r => r.pglite_marker).length,
      skipMarkers: a.filter(r => r.skip_marker).length};
  }),
  limitations: 'Markers are search heuristics, not semantic classifications. Case counts and timings are release218 evidence, not fresh full runs. File reading also includes legitimate fixtures and migrations.',
};
fs.writeFileSync(path.join(__dirname, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
console.log(JSON.stringify(summary, null, 2));
