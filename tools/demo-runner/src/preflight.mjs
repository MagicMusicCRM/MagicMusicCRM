import { APP_PACKAGE, EXPECTED_APP_VERSION } from './demo-runner-config.mjs';
import { parsePackageVersion } from './adb.mjs';

export async function runPreflight({ adb, roles, logger, expectedVersion = EXPECTED_APP_VERSION }) {
  adb.assertPrerequisites();
  const online = new Set(await adb.onlineDevices());
  const results = [];

  for (const config of Object.values(roles)) {
    if (!online.has(config.serial)) {
      throw new Error(`${config.avdName}: expected ${config.serial}, but it is not online.`);
    }
    const [avdName, bootCompleted, packageDump] = await Promise.all([
      adb.avdName(config.serial),
      adb.getProp(config.serial, 'sys.boot_completed'),
      adb.packageDump(config.serial, APP_PACKAGE),
    ]);
    if (avdName !== config.avdName) {
      throw new Error(`${config.serial}: expected AVD ${config.avdName}, got ${avdName || '<unknown>'}.`);
    }
    if (bootCompleted !== '1') {
      throw new Error(`${config.avdName}: Android boot has not completed.`);
    }
    const version = parsePackageVersion(packageDump);
    if (version.name !== expectedVersion.name || version.code !== expectedVersion.code) {
      throw new Error(
        `${config.avdName}: expected ${expectedVersion.name}+${expectedVersion.code}, got ${version.name}+${version.code}.`,
      );
    }
    if (!version.notificationsGranted) {
      throw new Error(`${config.avdName}: POST_NOTIFICATIONS is not granted.`);
    }
    results.push({
      role: config.role,
      avdName,
      serial: config.serial,
      version: `${version.name}+${version.code}`,
      systemPort: config.systemPort,
    });
  }

  const avdNames = new Set(results.map((item) => item.avdName));
  const serials = new Set(results.map((item) => item.serial));
  const ports = new Set(results.map((item) => item.systemPort));
  if (avdNames.size !== results.length || serials.size !== results.length || ports.size !== results.length) {
    throw new Error('Role mapping contains duplicate AVD names, serials, or Appium system ports.');
  }

  for (const item of results) {
    logger.info(`[preflight] ${item.role}: ${item.avdName}/${item.serial}, app ${item.version}, port ${item.systemPort}`);
  }
  return results;
}
