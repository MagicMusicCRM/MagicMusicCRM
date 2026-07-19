import { execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

function executableName(name) {
  return process.platform === 'win32' ? `${name}.exe` : name;
}

export function resolveAndroidEnvironment(environment = process.env) {
  const androidHome = environment.ANDROID_HOME
    || environment.ANDROID_SDK_ROOT
    || (process.platform === 'win32'
      ? path.join(environment.LOCALAPPDATA || '', 'Android', 'Sdk')
      : path.join(os.homedir(), 'Android', 'Sdk'));
  const javaHome = environment.JAVA_HOME
    || (process.platform === 'win32'
      ? path.join(environment.ProgramFiles || 'C:\\Program Files', 'Android', 'Android Studio', 'jbr')
      : undefined);
  const adbPath = path.join(androidHome, 'platform-tools', executableName('adb'));
  return { androidHome, javaHome, adbPath };
}

export class AdbClient {
  constructor({ environment = process.env } = {}) {
    const resolved = resolveAndroidEnvironment(environment);
    this.androidHome = resolved.androidHome;
    this.javaHome = resolved.javaHome;
    this.adbPath = resolved.adbPath;
  }

  assertPrerequisites() {
    if (!fs.existsSync(this.adbPath)) {
      throw new Error(`adb was not found at ${this.adbPath}. Set ANDROID_HOME.`);
    }
    if (!this.javaHome || !fs.existsSync(path.join(this.javaHome, 'bin', executableName('java')))) {
      throw new Error('Java JDK was not found. Set JAVA_HOME to the Android Studio JBR directory.');
    }
  }

  appiumEnvironment(base = process.env) {
    return {
      ...base,
      ANDROID_HOME: this.androidHome,
      ANDROID_SDK_ROOT: this.androidHome,
      JAVA_HOME: this.javaHome,
      PATH: `${path.dirname(this.adbPath)}${path.delimiter}${path.join(this.javaHome, 'bin')}${path.delimiter}${base.PATH || ''}`,
    };
  }

  async run(args, { timeoutMs = 30_000 } = {}) {
    const { stdout = '', stderr = '' } = await execFileAsync(this.adbPath, args, {
      encoding: 'utf8',
      windowsHide: true,
      timeout: timeoutMs,
      maxBuffer: 8 * 1024 * 1024,
    });
    return { stdout: stdout.trim(), stderr: stderr.trim() };
  }

  async shell(serial, args, options) {
    return this.run(['-s', serial, 'shell', ...args], options);
  }

  async onlineDevices() {
    const { stdout } = await this.run(['devices']);
    return stdout
      .split(/\r?\n/)
      .slice(1)
      .map((line) => line.trim().split(/\s+/))
      .filter((parts) => parts.length >= 2 && parts[1] === 'device')
      .map(([serial]) => serial);
  }

  async avdName(serial) {
    const { stdout } = await this.run(['-s', serial, 'emu', 'avd', 'name']);
    return stdout.split(/\r?\n/).map((value) => value.trim()).find((value) => value && value !== 'OK') || '';
  }

  async getProp(serial, name) {
    return (await this.shell(serial, ['getprop', name])).stdout;
  }

  async packageDump(serial, packageName) {
    return (await this.shell(serial, ['dumpsys', 'package', packageName])).stdout;
  }

  async currentPackage(serial) {
    const { stdout } = await this.shell(serial, ['dumpsys', 'activity', 'activities']);
    const line = stdout.split(/\r?\n/).find((item) => /mResumedActivity|topResumedActivity/.test(item));
    const match = line?.match(/\s([A-Za-z0-9_.]+)\/[A-Za-z0-9_.$]+/);
    return match?.[1] ?? null;
  }

  async home(serial) {
    await this.shell(serial, ['input', 'keyevent', 'KEYCODE_HOME']);
  }

  async expandNotifications(serial) {
    await this.shell(serial, ['cmd', 'statusbar', 'expand-notifications']);
  }

  async collapseNotifications(serial) {
    await this.shell(serial, ['cmd', 'statusbar', 'collapse']);
  }

  async keyboardShown(serial) {
    const { stdout } = await this.shell(serial, ['dumpsys', 'input_method']);
    return /\bmInputShown=true\b/.test(stdout);
  }

  async hasNotification(serial, packageName, marker) {
    const { stdout } = await this.shell(serial, ['dumpsys', 'notification', '--noredact']);
    if (!stdout.includes(packageName)) return false;
    return !marker || stdout.includes(marker);
  }
}

export function parsePackageVersion(packageDump) {
  return {
    name: packageDump.match(/\bversionName=([^\s]+)/)?.[1] ?? null,
    code: packageDump.match(/\bversionCode=(\d+)/)?.[1] ?? null,
    notificationsGranted: packageDump.match(/android\.permission\.POST_NOTIFICATIONS:\s+granted=(true|false)/)?.[1] === 'true',
  };
}
