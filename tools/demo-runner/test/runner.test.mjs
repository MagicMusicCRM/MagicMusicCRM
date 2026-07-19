import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import { ActionExecutor, formatClockValue } from '../src/actions.mjs';
import { parsePackageVersion, resolveAndroidEnvironment } from '../src/adb.mjs';
import { parseArgs } from '../src/cli-options.mjs';
import { EXPECTED_APP_VERSION, LOGIN_LOCATORS, ROLE_CONFIG } from '../src/config.mjs';
import { CredentialProvider } from '../src/credentials.mjs';
import { locatorSelector } from '../src/locators.mjs';
import { SecretVault, sanitizedChildEnvironment } from '../src/redaction.mjs';
import { selectSteps } from '../src/scenario.mjs';
import { StepEngine } from '../src/step-engine.mjs';

test('role mapping has exact unique AVD, serial, and system-port guards', () => {
  assert.deepEqual(
    Object.fromEntries(Object.entries(ROLE_CONFIG).map(([role, config]) => [role, config.avdName])),
    { client: 'Client', teacher: 'Teacher', admin: 'Admin', manager: 'Manager' },
  );
  assert.equal(new Set(Object.values(ROLE_CONFIG).map((item) => item.serial)).size, 4);
  assert.equal(new Set(Object.values(ROLE_CONFIG).map((item) => item.systemPort)).size, 4);
  assert.deepEqual(EXPECTED_APP_VERSION, { name: '1.2.2', code: '146' });
});

test('package dump parsing reads version and notification grant', () => {
  assert.deepEqual(parsePackageVersion(`
      versionCode=144 minSdk=24 targetSdk=36
      versionName=1.2.2
      android.permission.POST_NOTIFICATIONS: granted=true, flags=[ USER_SENSITIVE_WHEN_GRANTED ]
  `), { name: '1.2.2', code: '144', notificationsGranted: true });
});

test('Android environment falls back to the local Windows SDK', () => {
  const result = resolveAndroidEnvironment({ LOCALAPPDATA: 'C:\\Users\\demo\\AppData\\Local', ProgramFiles: 'C:\\Program Files' });
  assert.match(result.adbPath, /Android[\\/]Sdk[\\/]platform-tools[\\/]adb\.exe$/);
  assert.match(result.javaHome, /Android[\\/]Android Studio[\\/]jbr$/);
});

test('runtime credentials are redacted and excluded from Appium environment', () => {
  const vault = new SecretVault();
  vault.add('demo-password');
  assert.equal(vault.redact('password=demo-password'), 'password=<redacted>');
  const child = sanitizedChildEnvironment({
    PATH: 'safe',
    DEMO_CLIENT_LOGIN: 'client@example.test',
    DEMO_CLIENT_PASSWORD: 'demo-password',
    APPIUM_HOME: 'global-home',
  });
  assert.deepEqual(child, { PATH: 'safe' });
});

test('credential redaction survives login release until final shutdown', async () => {
  const loginKey = 'DEMO_TEST_LOGIN';
  const passwordKey = 'DEMO_TEST_PASSWORD';
  process.env[loginKey] = 'runtime-user@example.test';
  process.env[passwordKey] = 'runtime-password';
  const vault = new SecretVault();
  const provider = new CredentialProvider({
    roleConfig: { test: { credentialPrefix: 'DEMO_TEST', avdName: 'Test' } },
    vault,
  });
  try {
    const credentials = await provider.get('test');
    provider.release('test');
    assert.equal(credentials.login, '');
    assert.equal(credentials.password, '');
    assert.equal(vault.redact('runtime-user@example.test runtime-password'), '<redacted> <redacted>');
    provider.clear();
    assert.equal(vault.redact('runtime-password'), 'runtime-password');
  } finally {
    provider.clear();
    delete process.env[loginKey];
    delete process.env[passwordKey];
  }
});

test('CLI parses range, resume, and presentation hold', () => {
  const options = parseArgs(['--resume', '--from', 'a', '--to', 'b', '--hold-ms', '7500']);
  assert.equal(options.resume, true);
  assert.equal(options.from, 'a');
  assert.equal(options.to, 'b');
  assert.equal(options.holdMs, 7500);
});

test('step selection is enabled-only and inclusive', () => {
  const steps = [
    { id: 'a' },
    { id: 'disabled', enabled: false },
    { id: 'b' },
    { id: 'c' },
  ];
  assert.deepEqual(selectSteps(steps, { from: 'b', to: 'c' }).map((step) => step.id), ['b', 'c']);
});

test('locator strategies translate to WebdriverIO selectors', () => {
  assert.equal(locatorSelector({ using: 'accessibility id', value: 'Войти' }), '~Войти');
  assert.equal(
    locatorSelector({ using: 'android uiautomator', value: 'new UiSelector().text("X")' }),
    'android=new UiSelector().text("X")',
  );
});

test('clock-backed form values are deterministic and timezone-aware', () => {
  const now = new Date('2026-07-18T21:30:00.000Z');
  assert.equal(
    formatClockValue({ offsetDays: 2, format: 'dd.MM.yyyy', timeZone: 'Europe/Moscow' }, now),
    '21.07.2026',
  );
  assert.equal(
    formatClockValue({ format: 'HH:mm', timeZone: 'Europe/Moscow' }, now),
    '00:30',
  );
  assert.equal(
    formatClockValue({ nextWeekday: 2, format: 'dd.MM.yyyy', timeZone: 'Europe/Moscow' }, now),
    '21.07.2026',
  );
  assert.equal(
    formatClockValue(
      { nextWeekday: 6, strictFuture: true, format: 'dd.MM.yyyy', timeZone: 'Europe/Moscow' },
      new Date('2026-07-18T10:00:00.000Z'),
    ),
    '25.07.2026',
  );
});

test('scrollUntilVisible uses a bounded native scroll container', async () => {
  let targetChecks = 0;
  const target = {
    async isDisplayed() { targetChecks += 1; return targetChecks >= 3; },
  };
  const container = {
    elementId: 'scroll-view-1',
    async waitForDisplayed() {},
    async isDisplayed() { return true; },
  };
  const gestures = [];
  const driver = {
    async $(selector) {
      if (selector.includes('Target')) return target;
      return container;
    },
    async execute(command, payload) {
      gestures.push([command, payload]);
      return true;
    },
  };
  const executor = new ActionExecutor({
    sessions: { get() { return driver; } },
    roles: ROLE_CONFIG,
    adb: {},
    credentials: {},
    vault: new SecretVault(),
    logger: { info() {} },
    holdMs: 0,
    waitMs: 100,
  });
  await executor.execute({
    type: 'scrollUntilVisible',
    locator: { using: 'accessibility id', value: 'Target' },
    maxSwipes: 4,
  }, 'admin');
  assert.equal(gestures.length, 2);
  assert.deepEqual(gestures[0], [
    'mobile: scrollGesture',
    { elementId: 'scroll-view-1', direction: 'down', percent: 0.88 },
  ]);
});

test('Flutter login targets native EditText controls and submits after hiding the keyboard', async () => {
  assert.equal(
    LOGIN_LOCATORS.identity.value,
    '//android.widget.EditText[@hint="user@example.com"]',
  );
  assert.equal(
    LOGIN_LOCATORS.password.value,
    '//android.widget.EditText[@password="true"]',
  );

  const calls = [];
  const element = (name, displayed = true) => ({
    async waitForDisplayed() { calls.push(`${name}.wait`); },
    async isDisplayed() { calls.push(`${name}.displayed`); return displayed; },
    async click() { calls.push(`${name}.click`); },
    async clearValue() { calls.push(`${name}.clear`); },
    async setValue() { calls.push(`${name}.set`); },
    async getLocation() { return { x: 10, y: 20 }; },
    async getSize() { return { width: 100, height: 40 }; },
  });
  const identity = element('identity');
  const password = element('password');
  const submit = element('submit');
  let submitted = false;
  submit.click = async () => {
    calls.push('submit.click');
    submitted = true;
  };
  const success = {
    async waitForDisplayed() { calls.push('success.wait'); },
    async isDisplayed() { return submitted; },
  };
  const selectors = new Map([
    [locatorSelector(LOGIN_LOCATORS.identity), identity],
    [locatorSelector(LOGIN_LOCATORS.password), password],
    [locatorSelector(LOGIN_LOCATORS.submit), submit],
    ['~Client home', success],
  ]);
  const driver = {
    async activateApp() { calls.push('activate'); },
    async hideKeyboard() { calls.push('hideKeyboard'); },
    async $(selector) {
      calls.push(`lookup:${selector}`);
      return selectors.get(selector);
    },
  };
  const credentials = {
    async get() { return { login: 'runtime-user', password: 'runtime-password' }; },
    release() { calls.push('release'); },
  };
  const executor = new ActionExecutor({
    sessions: { get() { return driver; } },
    roles: ROLE_CONFIG,
    adb: { async keyboardShown() { return true; } },
    credentials,
    vault: new SecretVault(),
    logger: { info() {} },
    holdMs: 0,
    waitMs: 100,
  });
  await executor.execute({
    type: 'login',
    successLocator: { using: 'accessibility id', value: 'Client home' },
  }, 'client');

  assert.equal(calls[0], 'activate');
  assert.equal(
    calls.filter((call) => call === 'lookup:~Войти').length,
    2,
    'submit is cached for coordinates and refreshed after the IME closes',
  );
  assert.equal(calls.indexOf('identity.click') < calls.indexOf('identity.set'), true);
  assert.equal(calls.indexOf('password.click') < calls.indexOf('password.set'), true);
  assert.equal(calls.indexOf('hideKeyboard') < calls.indexOf('submit.click'), true);
  assert.equal(calls.at(-1), 'release');
});

test('resume reconciles an interrupted mutation instead of repeating it', async () => {
  const calls = [];
  const checkpoint = {
    state: { completedStepIds: [], inProgressStepId: 'mutate' },
    async markCompleted(step) {
      calls.push(`complete:${step.id}`);
      this.state.completedStepIds.push(step.id);
      this.state.inProgressStepId = null;
    },
    async markStarted(step) { calls.push(`start:${step.id}`); },
  };
  const executor = {
    async check() { calls.push('reconcile'); return true; },
    async executeStepActions() { calls.push('execute'); },
  };
  const engine = new StepEngine({
    executor,
    checkpoint,
    sessions: new Map(),
    artifactsPath: '.',
    vault: new SecretVault(),
    logger: { info() {}, error() {} },
    holdMs: 0,
  });
  await engine.run([{ id: 'mutate', role: 'admin', mutating: true, reconcile: [{ type: 'visible' }] }], { resume: true });
  assert.deepEqual(calls, ['reconcile', 'complete:mutate']);
});

test('a mutating step without reconciliation is rejected before execution', async () => {
  const checkpoint = {
    state: { completedStepIds: [], inProgressStepId: null },
    async markCompleted() {},
    async markStarted() { throw new Error('must not start'); },
  };
  const engine = new StepEngine({
    executor: { async check() { return false; }, async executeStepActions() {} },
    checkpoint,
    sessions: new Map(),
    artifactsPath: '.',
    vault: new SecretVault(),
    logger: { info() {}, error() {} },
    holdMs: 0,
  });
  await assert.rejects(
    engine.run([{ id: 'unsafe', role: 'admin', mutating: true }]),
    /must define reconcile/,
  );
});

test('full demo scenario covers the confirmed business path and five-second holds', async () => {
  const scenario = JSON.parse(await fs.readFile(new URL('../scenarios/full-demo.json', import.meta.url), 'utf8'));
  const enabled = scenario.steps.filter((step) => step.enabled !== false);
  const ids = new Set(enabled.map((step) => step.id));
  for (const required of [
    'client.create-lead-from-chat',
    'admin.schedule-trial',
    'teacher.assign-homework',
    'client-send-feedback-and-intent',
    'admin.issue-subscription-from-lead',
    'admin-create-tuesday-series',
    'manager-verify-one-hour-charge',
  ]) {
    assert.equal(ids.has(required), true, `missing ${required}`);
  }
  assert.equal(scenario.presentationHoldMs, 5000);
  assert.equal(enabled.length, 44);
  assert.equal(enabled.every((step) => step.holdMs === 5000), true);
  assert.equal(enabled.filter((step) => step.mutating).every((step) => step.reconcile?.length > 0), true);
  const manual = enabled.flatMap((step) => [...(step.actions || []), ...(step.action ? [step.action] : [])])
    .filter((action) => action.type === 'manual');
  assert.equal(manual.length, 1);
  assert.equal(manual.every((action) => action.placeholder === true && action.placeholderId), true);
  assert.equal(manual[0].placeholderId, 'RESET_DEMO_FIXTURE');
  const manualStepIds = enabled
    .filter((step) => [...(step.actions || []), ...(step.action ? [step.action] : [])]
      .some((action) => action.type === 'manual'))
    .map((step) => step.id);
  assert.deepEqual(manualStepIds, ['fixture.reset-magic1']);
  assert.equal(enabled.length - manualStepIds.length, 43);
  const manualConfirmStepIds = enabled
    .filter((step) => (step.reconcile || []).some((condition) => condition.type === 'manualConfirm'))
    .map((step) => step.id);
  assert.deepEqual(manualConfirmStepIds, ['fixture.reset-magic1']);
  for (const automated of [
    'client.create-lead-from-chat',
    'admin.add-lead-comment',
    'manager.create-feedback-task',
    'admin.schedule-trial',
    'admin.issue-subscription-from-lead',
    'admin-create-tuesday-series',
    'admin-complete-first-regular-lesson',
    'manager-verify-one-hour-charge',
  ]) {
    const step = enabled.find((item) => item.id === automated);
    const actions = [...(step.actions || []), ...(step.action ? [step.action] : [])];
    assert.equal(actions.some((action) => action.type === 'manual'), false, `${automated} regressed to manual`);
  }
  for (const forbidden of [
    'admin.convert-lead-to-student',
    'admin-record-payment',
    'admin-assign-subscription',
    'admin.open-task-push',
    'admin.background-for-task-push',
  ]) {
    assert.equal(ids.has(forbidden), false, `forbidden obsolete step ${forbidden}`);
  }
  const feedbackIndex = enabled.findIndex((step) => step.id === 'admin-record-feedback-and-complete-task');
  const issueIndex = enabled.findIndex((step) => step.id === 'admin.issue-subscription-from-lead');
  assert.equal(feedbackIndex >= 0 && issueIndex > feedbackIndex, true, 'lead must survive through feedback');
  const issue = enabled[issueIndex];
  assert.equal(
    issue.actions.some((action) => action.locator?.value?.includes('Демо — Фортепиано, 8 часов')),
    true,
  );
  assert.equal(issue.reconcile[0].type, 'visible');
  assert.equal(
    enabled.some((step) => step.action?.type === 'pushShadeTap' && /задач/i.test(step.action.marker || '')),
    false,
    'task PUSH is not a confirmed backend contract',
  );
});
