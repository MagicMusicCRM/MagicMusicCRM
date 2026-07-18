import fs from 'node:fs/promises';
import path from 'node:path';

function safeName(value) {
  return String(value).replace(/[^a-zA-Z0-9_.-]+/g, '_');
}

export async function captureFailureArtifacts({
  step,
  sessions,
  basePath,
  vault,
  logger,
  error,
}) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const directory = path.join(basePath, `${timestamp}-${safeName(step?.id || 'startup')}`);
  await fs.mkdir(directory, { recursive: true });

  await Promise.allSettled([...sessions.entries()].map(async ([role, driver]) => {
    const stem = path.join(directory, safeName(role));
    await Promise.allSettled([
      driver.saveScreenshot(`${stem}.png`),
      (async () => {
        const source = await driver.getPageSource();
        await fs.writeFile(`${stem}.xml`, vault.redact(source), { encoding: 'utf8', mode: 0o600 });
      })(),
    ]);
  }));
  await fs.writeFile(
    path.join(directory, 'error.txt'),
    `${vault.redact(error?.stack || error)}\n`,
    { encoding: 'utf8', mode: 0o600 },
  );
  logger.error(`[failure] artifacts saved under ${directory}`);
  return directory;
}
