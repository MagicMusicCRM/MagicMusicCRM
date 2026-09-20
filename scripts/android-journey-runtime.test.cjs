const { test } = require('node:test');
const assert = require('node:assert/strict');
const { androidConfig } = require('./android-journey-runtime.cjs');

test('only an explicit emulator and loopback synthetic fixture are accepted', () => {
  const fixture = JSON.stringify({ baseUrl: 'http://127.0.0.1:32145/api' });
  assert.equal(androidConfig('emulator-5556', fixture).port, '32145');
  for (const serial of ['device-id', 'emulator-5556 & echo bad', '']) {
    assert.throws(() => androidConfig(serial, fixture));
  }
  for (const baseUrl of ['https://api.magicmusiccrm.ru/api', 'http://10.0.2.2:3000/api']) {
    assert.throws(() => androidConfig('emulator-5556', JSON.stringify({ baseUrl })));
  }
});
