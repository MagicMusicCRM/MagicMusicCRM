const fs = require('node:fs');
const readline = require('node:readline');

const fields = ['durationMs', 'serverMs', 'dbQueryMs', 'dbAcquireMs', 'dbMaxQueryMs'];
const kinds = new Set(['http.performance', 'http', 'operation', 'screenData', 'screenFrame']);

function summarize(records) {
  const groups = new Map();
  let accepted = 0;
  for (const record of records) {
    const kind = record.event ?? record.kind;
    if (!kinds.has(kind) || !Number.isFinite(record.durationMs) || record.durationMs < 0) continue;
    if (++accepted > 100000) throw new Error('Limit: 100000 measurements. Select a shorter time window.');
    const name = kind === 'http.performance' ? `${record.method} ${record.route}` : record.operation;
    const key = `${kind}: ${name}`;
    if (!groups.has(key)) groups.set(key, { scenario: key, count: 0, errors: 0, values: {} });
    const group = groups.get(key);
    group.count++;
    if (record.outcome === 'error' || record.outcome === 'aborted' || record.errorType || record.status >= 400 || record.statusCode >= 400) group.errors++;
    for (const field of fields) {
      if (Number.isFinite(record[field]) && record[field] >= 0) (group.values[field] ??= []).push(record[field]);
    }
  }
  return [...groups.values()].map(({ values, ...group }) => ({ ...group,
    timings: Object.fromEntries(Object.entries(values).map(([field, samples]) => {
      samples.sort((a, b) => a - b);
      const percentile = p => samples[Math.ceil(samples.length * p) - 1];
      return [field, { samples: samples.length, p50: percentile(0.5), p95: percentile(0.95), max: samples.at(-1) }];
    }))
  }));
}

async function* readMeasurements(paths) {
  for (const path of paths) {
    const lines = readline.createInterface({ input: fs.createReadStream(path), crlfDelay: Infinity });
    for await (const line of lines) {
      const start = line.indexOf('{');
      if (start < 0) continue;
      try { yield JSON.parse(line.slice(start)); } catch { /* Ignore ordinary application logs. */ }
    }
  }
}

async function main(paths) {
  if (!paths.length) throw new Error('Usage: node server/scripts/summarize-performance.cjs <log.jsonl> [more logs]');
  const records = [];
  for await (const record of readMeasurements(paths)) {
    if (!kinds.has(record.event ?? record.kind)) continue;
    if (records.length >= 100000) throw new Error('Limit: 100000 measurements. Select a shorter time window.');
    records.push(record);
  }
  process.stdout.write(JSON.stringify({ measurements: summarize(records) }, null, 2) + '\n');
}

module.exports = { summarize };
if (require.main === module) main(process.argv.slice(2)).catch(error => { process.stderr.write(error.message + '\n'); process.exitCode = 1; });
