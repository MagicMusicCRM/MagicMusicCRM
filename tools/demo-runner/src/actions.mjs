import { APP_PACKAGE, LOGIN_LOCATORS } from './config.mjs';
import { findElement, isDisplayed, locatorSelector } from './locators.mjs';
import { waitForOperator } from './operator.mjs';
import { poll, sleep } from './time.mjs';

function actionList(step) {
  if (Array.isArray(step.actions)) return step.actions;
  if (step.action) return [step.action];
  return [];
}

function roleFor(item, fallbackRole) {
  const role = item.role || fallbackRole;
  if (!role) throw new Error('Action or condition does not identify a role.');
  return role;
}

export function formatClockValue(spec, now = new Date()) {
  if (!spec || typeof spec !== 'object') {
    throw new Error('valueFromClock must be an object.');
  }
  const shifted = new Date(now.getTime());
  shifted.setUTCDate(shifted.getUTCDate() + Number(spec.offsetDays || 0));
  shifted.setUTCMinutes(shifted.getUTCMinutes() + Number(spec.offsetMinutes || 0));
  const formatter = new Intl.DateTimeFormat('en-GB', {
      timeZone: spec.timeZone || 'Europe/Moscow',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    });
  const parts = Object.fromEntries(
    formatter.formatToParts(shifted).map(({ type, value }) => [type, value]),
  );
  if (spec.nextWeekday != null) {
    const targetWeekday = Number(spec.nextWeekday);
    if (!Number.isInteger(targetWeekday) || targetWeekday < 1 || targetWeekday > 7) {
      throw new Error('valueFromClock.nextWeekday must be an ISO weekday from 1 to 7.');
    }
    // Work with the calendar date in the requested timezone. UTC noon avoids
    // DST/midnight rollover while ISO weekday arithmetic advances the local
    // date to the next requested weekday (the same weekday means +7 days).
    const localDate = new Date(Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      12,
    ));
    const currentWeekday = localDate.getUTCDay() || 7;
    let delta = (targetWeekday - currentWeekday + 7) % 7;
    if (delta === 0 && spec.strictFuture !== false) delta = 7;
    localDate.setUTCDate(localDate.getUTCDate() + delta);
    parts.year = String(localDate.getUTCFullYear()).padStart(4, '0');
    parts.month = String(localDate.getUTCMonth() + 1).padStart(2, '0');
    parts.day = String(localDate.getUTCDate()).padStart(2, '0');
  }
  const tokens = {
    yyyy: parts.year,
    MM: parts.month,
    dd: parts.day,
    HH: parts.hour,
    mm: parts.minute,
  };
  const format = spec.format || 'dd.MM.yyyy';
  if (!/^(?:yyyy|MM|dd|HH|mm|[. :/-])+$/.test(format)) {
    throw new Error(`Unsupported valueFromClock format: ${format}`);
  }
  return format.replace(/yyyy|MM|dd|HH|mm/g, (token) => tokens[token]);
}

function resolvedLocator(locator) {
  if (!locator?.valueFromClock) return locator;
  const clockValue = formatClockValue(locator.valueFromClock);
  const template = locator.value || '{clock}';
  if (!template.includes('{clock}')) {
    throw new Error('A clock-backed locator value must contain {clock}.');
  }
  return { ...locator, value: template.replaceAll('{clock}', clockValue) };
}

function actionValue(action) {
  if (action.valueFromClock) return formatClockValue(action.valueFromClock);
  return action.valueFromEnv ? process.env[action.valueFromEnv] : action.value;
}

async function clearQuietly(element) {
  try {
    await element.clearValue();
  } catch {
    // Best-effort cleanup is used only to prevent credentials in artifacts.
  }
}

export class ActionExecutor {
  constructor({ sessions, roles, adb, credentials, vault, logger, holdMs, waitMs }) {
    this.sessions = sessions;
    this.roles = roles;
    this.adb = adb;
    this.credentials = credentials;
    this.vault = vault;
    this.logger = logger;
    this.holdMs = holdMs;
    this.waitMs = waitMs;
  }

  async executeStepActions(step) {
    const actions = actionList(step);
    for (const [index, action] of actions.entries()) {
      const role = roleFor(action, step.role);
      this.logger.info(`[action] ${step.id} ${index + 1}/${actions.length}: ${role}.${action.type}`);
      await this.execute(action, step.role);
    }
  }

  async execute(action, fallbackRole) {
    const role = roleFor(action, fallbackRole);
    const driver = this.sessions.get(role);
    const timeoutMs = action.timeoutMs ?? this.waitMs;
    switch (action.type) {
      case 'tap': {
        const element = await findElement(driver, resolvedLocator(action.locator), { timeoutMs });
        await element.click();
        return;
      }
      case 'tapCoordinates':
        await driver.execute('mobile: clickGesture', {
          x: Number(action.x),
          y: Number(action.y),
        });
        return;
      case 'swipeCoordinates':
        await driver.execute('mobile: swipeGesture', {
          left: Number(action.x),
          top: Number(action.y),
          width: Number(action.width),
          height: Number(action.height),
          direction: action.direction,
          percent: Number(action.percent ?? 0.75),
        });
        return;
      case 'tapIfVisible': {
        if (action.unlessLocator
          && await isDisplayed(driver, resolvedLocator(action.unlessLocator))) return;
        const locator = resolvedLocator(action.locator);
        if (await isDisplayed(driver, locator)) {
          if (Number.isFinite(Number(action.x)) && Number.isFinite(Number(action.y))) {
            await driver.execute('mobile: clickGesture', {
              x: Number(action.x),
              y: Number(action.y),
            });
          } else {
            await (await driver.$(locatorSelector(locator))).click();
          }
        }
        return;
      }
      case 'setValue': {
        const element = await findElement(driver, resolvedLocator(action.locator), { timeoutMs });
        const value = actionValue(action);
        if (typeof value !== 'string') {
          throw new Error(`Missing value for ${action.valueFromEnv || action.locator.value}.`);
        }
        if (action.sensitive) this.vault.add(value);
        try {
          // Flutter can expose an EditText to UiAutomator before its controller
          // receives focus. Focus explicitly so setValue dispatches the same
          // change path as real typing (for example, chat send/mic switching).
          await element.click();
          if (action.clear !== false) await element.clearValue();
          if (action.inputMode === 'type') await element.addValue(value);
          else await element.setValue(value);
        } catch (error) {
          if (action.sensitive) await clearQuietly(element);
          throw error;
        }
        return;
      }
      case 'scrollUntilVisible': {
        const target = resolvedLocator(action.locator);
        if (await isDisplayed(driver, target)) return;
        const container = await findElement(
          driver,
          resolvedLocator(action.containerLocator ?? {
            using: 'android uiautomator',
            value: 'new UiSelector().className("android.widget.ScrollView")',
          }),
          { timeoutMs },
        );
        const maxSwipes = Number(action.maxSwipes ?? 12);
        for (let index = 0; index < maxSwipes; index += 1) {
          const canContinue = await driver.execute('mobile: scrollGesture', {
            elementId: container.elementId,
            direction: action.direction ?? 'down',
            percent: Number(action.percent ?? 0.88),
          });
          if (await isDisplayed(driver, target)) return;
          if (canContinue === false) break;
        }
        throw new Error(`Element did not become visible after scrolling: ${target.value}`);
      }
      case 'login':
        await this.#login(role, driver, action, timeoutMs);
        return;
      case 'manual':
        await waitForOperator(`${action.placeholderId || role}: ${action.instructions}`);
        return;
      case 'pause':
        await sleep(action.ms ?? this.holdMs);
        return;
      case 'back':
        await driver.back();
        return;
      case 'pressKey':
        await driver.pressKeyCode(Number(action.keyCode));
        return;
      case 'hideKeyboard':
        try {
          // UiAutomator2 may implement hideKeyboard as Android BACK. Calling
          // it when no IME is shown navigates out of the current Flutter
          // screen, so guard it with the native keyboard state first.
          if (await this.adb.keyboardShown(this.roles[role].serial)) {
            await driver.hideKeyboard();
          }
        } catch {
          // UiAutomator2 reports an error when the IME is already hidden.
        }
        return;
      case 'activateApp':
        await driver.activateApp(action.packageName ?? APP_PACKAGE);
        return;
      case 'restartApp':
        await driver.terminateApp(action.packageName ?? APP_PACKAGE);
        await driver.activateApp(action.packageName ?? APP_PACKAGE);
        return;
      case 'home':
        await this.adb.home(this.roles[role].serial);
        return;
      case 'expandNotifications':
        await this.adb.expandNotifications(this.roles[role].serial);
        return;
      case 'collapseNotifications':
        await this.adb.collapseNotifications(this.roles[role].serial);
        return;
      case 'pushShadeTap':
        await this.#pushShadeTap(role, driver, action, timeoutMs);
        return;
      default:
        throw new Error(`Unsupported action type: ${action.type}`);
    }
  }

  async check(condition, fallbackRole, { wait = false } = {}) {
    const role = roleFor(condition, fallbackRole);
    const driver = this.sessions.get(role);
    const serial = this.roles[role].serial;
    const timeoutMs = condition.timeoutMs ?? this.waitMs;

    const predicate = async () => {
      switch (condition.type) {
        case 'visible':
          return isDisplayed(driver, resolvedLocator(condition.locator));
        case 'hidden':
          return !await isDisplayed(driver, resolvedLocator(condition.locator));
        case 'currentPackage':
          return await this.adb.currentPackage(serial) === (condition.value ?? APP_PACKAGE);
        case 'notificationExists':
          return this.adb.hasNotification(serial, condition.packageName ?? APP_PACKAGE, condition.marker);
        case 'manualConfirm':
          return waitForOperator(condition.instructions || `Confirm ${fallbackRole || role} state`, { confirmation: true });
        case 'text': {
          const locator = resolvedLocator(condition.locator);
          if (!await isDisplayed(driver, locator)) return false;
          const element = await driver.$(locatorSelector(locator));
          const text = await element.getText();
          const actual = text || await element.getAttribute('content-desc') || '';
          return condition.contains ? actual.includes(condition.value) : actual === condition.value;
        }
        default:
          throw new Error(`Unsupported condition type: ${condition.type}`);
      }
    };

    if (!wait) return predicate();
    await poll(predicate, {
      timeoutMs,
      intervalMs: condition.intervalMs ?? 250,
      description: `${condition.type} for ${role}`,
    });
    return true;
  }

  async #login(role, driver, action, timeoutMs) {
    await driver.activateApp(APP_PACKAGE);
    const successLocator = action.successLocator;
    if (successLocator) {
      try {
        await poll(() => isDisplayed(driver, successLocator), {
          timeoutMs: 6_000,
          intervalMs: 250,
          description: `authenticated shell for ${role}`,
        });
        this.logger.info(`[login] ${role} already has the expected authenticated screen`);
        return;
      } catch {
        // The authenticated shell did not appear; continue with real login.
      }
    }

    const identityLocator = action.identityLocator ?? LOGIN_LOCATORS.identity;
    const passwordLocator = action.passwordLocator ?? LOGIN_LOCATORS.password;
    const submitLocator = action.submitLocator ?? LOGIN_LOCATORS.submit;
    const identity = await findElement(driver, identityLocator, { timeoutMs });
    const password = await findElement(driver, passwordLocator, { timeoutMs });
    const submit = await findElement(driver, submitLocator, { timeoutMs });
    const submitLocation = await submit.getLocation();
    const submitSize = await submit.getSize();
    const credentials = await this.credentials.get(role);
    try {
      await identity.click();
      await identity.clearValue();
      await identity.setValue(credentials.login);
      await password.click();
      await password.clearValue();
      await password.setValue(credentials.password);
      // UiAutomator2 can resolve a Flutter EditText without focusing it. An
      // explicit tap above makes the framework controller receive the text;
      // hide the IME so it cannot intercept the submit tap on small screens.
      try {
        if (await this.adb.keyboardShown(this.roles[role].serial)) {
          await driver.hideKeyboard();
        }
      } catch {
        // Some Android images report no soft keyboard even though it already
        // collapsed after the password action.
      }
      await sleep(300);
      try {
        await (await findElement(driver, submitLocator, { timeoutMs: 3_000 })).click();
      } catch {
        // Flutter can rebuild the semantic node when the IME closes. Tap the
        // cached physical center instead of reusing a stale element id.
        await driver.execute('mobile: clickGesture', {
          x: Math.round(submitLocation.x + submitSize.width / 2),
          y: Math.round(submitLocation.y + submitSize.height / 2),
        });
      }
      if (successLocator) {
        await findElement(driver, successLocator, { timeoutMs: action.loginTimeoutMs ?? 45_000 });
      } else {
        await findElement(driver, identityLocator, { timeoutMs: action.loginTimeoutMs ?? 45_000, reverse: true });
      }
      this.logger.info(`[login] ${role} authenticated; login action copies cleared`);
    } catch (error) {
      await Promise.allSettled([clearQuietly(identity), clearQuietly(password)]);
      throw error;
    } finally {
      this.credentials.release(role);
    }
  }

  async #pushShadeTap(role, driver, action, timeoutMs) {
    const serial = this.roles[role].serial;
    if (!action.marker) {
      throw new Error('pushShadeTap requires a unique notification marker.');
    }
    await this.adb.home(serial);
    await poll(async () => await this.adb.currentPackage(serial) !== APP_PACKAGE, {
      timeoutMs: 5_000,
      description: `${role} app to enter background`,
    });
    await poll(
      () => this.adb.hasNotification(serial, action.packageName ?? APP_PACKAGE, action.marker),
      {
        timeoutMs: action.notificationTimeoutMs ?? timeoutMs,
        intervalMs: 500,
        description: `${role} push notification`,
      },
    );
    await this.adb.expandNotifications(serial);
    const notification = await findElement(driver, action.locator, { timeoutMs });
    await sleep(action.shadeHoldMs ?? this.holdMs);
    await notification.click();
    await poll(async () => await this.adb.currentPackage(serial) === (action.expectedPackage ?? APP_PACKAGE), {
      timeoutMs,
      description: `${role} app to open from notification`,
    });
    if (action.expectedLocator) {
      await findElement(driver, action.expectedLocator, { timeoutMs });
    }
  }
}
