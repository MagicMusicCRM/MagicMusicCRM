const { test } = require('node:test');
const assert = require('node:assert/strict');
const { summarize } = require('./summarize-performance.cjs');

test('computes exact nearest-rank percentiles and excludes identifiers', () => {
  const rows = Array.from({ length: 20 }, (_, i) => ({ kind: 'http', operation: 'payment', durationMs: i + 1,
    statusCode: i === 19 ? 503 : 200, requestId: 'private', body: 'private' }));
  const summary = summarize([...rows, { kind: 'http', durationMs: -1 }, { kind: 'http', durationMs: NaN }]);
  assert.deepEqual(summary, [{ scenario: 'http: payment', count: 20, errors: 1,
    timings: { durationMs: { samples: 20, p50: 10, p95: 19, max: 20 } } }]);
});
test('reports the actual sample count for optional server timings', () => {
  const result = summarize([{ kind: 'http', operation: 'api', durationMs: 5, serverMs: 3 },
    { kind: 'http', operation: 'api', durationMs: 7 }]);
  assert.equal(result[0].timings.serverMs.samples, 1);
  assert.equal(result[0].timings.durationMs.samples, 2);
});
