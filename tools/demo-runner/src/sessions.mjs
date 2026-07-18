import { remote } from 'webdriverio';
import { APP_ACTIVITY, APP_PACKAGE } from './config.mjs';

function connectionOptions(appiumUrl) {
  const url = new URL(appiumUrl);
  return {
    protocol: url.protocol.replace(':', ''),
    hostname: url.hostname,
    port: Number(url.port || 4723),
    path: url.pathname || '/',
  };
}

export class SessionManager {
  constructor({ appiumUrl, roles, logger }) {
    this.appiumUrl = appiumUrl;
    this.roles = roles;
    this.logger = logger;
    this.sessions = new Map();
  }

  async createAll() {
    const base = connectionOptions(this.appiumUrl);
    const results = await Promise.allSettled(Object.values(this.roles).map(async (config) => {
        const driver = await remote({
          ...base,
          logLevel: 'silent',
          connectionRetryTimeout: 90_000,
          connectionRetryCount: 2,
          capabilities: {
            platformName: 'Android',
            'appium:automationName': 'UiAutomator2',
            'appium:deviceName': config.avdName,
            'appium:udid': config.serial,
            'appium:appPackage': APP_PACKAGE,
            'appium:appActivity': APP_ACTIVITY,
            'appium:appWaitActivity': '*',
            'appium:noReset': true,
            'appium:fullReset': false,
            'appium:dontStopAppOnReset': true,
            'appium:newCommandTimeout': 3600,
            'appium:systemPort': config.systemPort,
            'appium:adbExecTimeout': 60_000,
            'appium:uiautomator2ServerLaunchTimeout': 60_000,
            'appium:disableWindowAnimation': false,
            'appium:printPageSourceOnFindFailure': false,
          },
        });
        this.sessions.set(config.role, driver);
        this.logger.info(`[session] ${config.role} attached to ${config.avdName}/${config.serial}`);
      }));
    const failures = results.filter((result) => result.status === 'rejected');
    if (failures.length > 0) {
      await this.closeAll();
      throw new AggregateError(
        failures.map((result) => result.reason),
        `Failed to create ${failures.length} of ${results.length} Appium sessions.`,
      );
    }
    return this.sessions;
  }

  get(role) {
    const session = this.sessions.get(role);
    if (!session) throw new Error(`No Appium session for role ${role}.`);
    return session;
  }

  async closeAll() {
    const sessions = [...this.sessions.entries()];
    this.sessions.clear();
    await Promise.allSettled(sessions.map(async ([role, driver]) => {
      try {
        await driver.deleteSession();
      } finally {
        this.logger.info(`[session] ${role} disconnected`);
      }
    }));
  }
}
