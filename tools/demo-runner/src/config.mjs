import path from 'node:path';
import { fileURLToPath } from 'node:url';

const moduleDir = path.dirname(fileURLToPath(import.meta.url));

export const RUNNER_ROOT = path.resolve(moduleDir, '..');
export const APP_PACKAGE = 'magic.crm';
export const APP_ACTIVITY = 'com.magicmusiccrm.magic_music_crm.MainActivity';

export const EXPECTED_APP_VERSION = Object.freeze({
  name: process.env.DEMO_EXPECTED_VERSION_NAME ?? '1.2.2',
  code: process.env.DEMO_EXPECTED_VERSION_CODE ?? '146',
});

export const ROLE_CONFIG = Object.freeze({
  client: Object.freeze({
    role: 'client',
    avdName: 'Client',
    serial: 'emulator-5554',
    systemPort: 8211,
    credentialPrefix: 'DEMO_CLIENT',
  }),
  teacher: Object.freeze({
    role: 'teacher',
    avdName: 'Teacher',
    serial: 'emulator-5558',
    systemPort: 8212,
    credentialPrefix: 'DEMO_TEACHER',
  }),
  admin: Object.freeze({
    role: 'admin',
    avdName: 'Admin',
    serial: 'emulator-5556',
    systemPort: 8213,
    credentialPrefix: 'DEMO_ADMIN',
  }),
  manager: Object.freeze({
    role: 'manager',
    avdName: 'Manager',
    serial: 'emulator-5560',
    systemPort: 8214,
    credentialPrefix: 'DEMO_MANAGER',
  }),
});

export const DEFAULTS = Object.freeze({
  appiumUrl: 'http://127.0.0.1:4723',
  scenarioPath: path.join(RUNNER_ROOT, 'scenarios', 'skeleton.json'),
  checkpointPath: path.join(RUNNER_ROOT, '.state', 'checkpoint.json'),
  artifactsPath: path.join(RUNNER_ROOT, '.artifacts'),
  holdMs: 5000,
  waitMs: 20_000,
});

export const LOGIN_LOCATORS = Object.freeze({
  // Flutter exposes the field labels as separate semantic Views, so locating
  // by their text selects a non-editable node. Match the login-only hint and
  // password attribute so an authenticated screen's search box is never
  // mistaken for the identity field while the shell is still settling.
  identity: Object.freeze({
    using: 'xpath',
    value: '//android.widget.EditText[@hint="user@example.com"]',
  }),
  password: Object.freeze({
    using: 'xpath',
    value: '//android.widget.EditText[@password="true"]',
  }),
  submit: Object.freeze({ using: 'accessibility id', value: 'Войти' }),
});
