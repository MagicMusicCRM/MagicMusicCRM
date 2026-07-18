import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';

import { AdbClient } from './adb.mjs';

const require = createRequire(import.meta.url);
const adb = new AdbClient();
adb.assertPrerequisites();

const child = spawn(
  process.execPath,
  [require.resolve('appium'), 'driver', 'doctor', 'uiautomator2'],
  {
    env: adb.appiumEnvironment(),
    stdio: 'inherit',
    windowsHide: true,
  },
);

child.once('error', (error) => {
  console.error(error.message);
  process.exitCode = 1;
});

child.once('exit', (code, signal) => {
  if (signal) {
    console.error(`Appium doctor stopped by ${signal}`);
    process.exitCode = 1;
    return;
  }
  process.exitCode = code ?? 1;
});
