const { test } = require('node:test');
const assert = require('node:assert/strict');
const { imageEnvironment } = require('./http-journey-image-runtime.cjs');
test('image runner refuses remote or non-owned databases before starting Docker', () => {
  for (const url of ['postgresql://u:p@example.com/magiccrm_http_test_' + 'a'.repeat(32),
    'postgresql://u:p@localhost/postgres', 'postgresql://u:p@localhost/production']) {
    assert.throws(() => imageEnvironment({ DATABASE_URL: url }));
  }
});
test('image runner maps only the owned local fixture and keeps synthetic keys', () => {
  const env = imageEnvironment({ DATABASE_URL: 'postgresql://u:p@127.0.0.1:54329/magiccrm_http_test_' + 'a'.repeat(32),
    JWT_ACCESS_SECRET: 'synthetic', PATH: 'host-path', TS_NODE_PROJECT: 'host-file' });
  assert.equal(new URL(env.DATABASE_URL).hostname, 'host.docker.internal');
  assert.equal(new URL(env.DATABASE_URL).port, '54329');
  assert.equal(env.PORT, '3000');
  assert.equal(env.JWT_ACCESS_SECRET, 'synthetic');
  assert.equal(env.PATH, undefined);
  assert.equal(env.TS_NODE_PROJECT, undefined);
});
