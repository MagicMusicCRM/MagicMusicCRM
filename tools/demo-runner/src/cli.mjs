import { pathToFileURL } from 'node:url';
import { AdbClient } from './adb.mjs';
import { ActionExecutor } from './actions.mjs';
import { LocalAppiumServer } from './appium-server.mjs';
import { CheckpointStore } from './checkpoint.mjs';
import { HELP, parseArgs } from './cli-options.mjs';
import { DEFAULTS, ROLE_CONFIG } from './demo-runner-config.mjs';
import { CredentialProvider } from './credentials.mjs';
import { SafeLogger } from './logger.mjs';
import { runPreflight } from './preflight.mjs';
import { SecretVault } from './redaction.mjs';
import { loadScenario, selectSteps } from './scenario.mjs';
import { SessionManager } from './sessions.mjs';
import { StepEngine } from './step-engine.mjs';

export async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.help) {
    process.stdout.write(HELP);
    return;
  }

  const vault = new SecretVault();
  const logger = new SafeLogger(vault);
  const adb = new AdbClient();
  const scenario = await loadScenario(options.scenarioPath);
  const steps = selectSteps(scenario.steps, options);
  await runPreflight({ adb, roles: ROLE_CONFIG, logger });

  if (options.dryRun) {
    logger.info(`[dry-run] scenario ${scenario.version}: ${steps.length} enabled step(s)`);
    for (const step of steps) logger.info(`[dry-run] ${step.id}: ${step.description || ''}`);
    return;
  }

  const credentials = new CredentialProvider({ roleConfig: ROLE_CONFIG, vault });
  const appium = new LocalAppiumServer({
    url: options.appiumUrl,
    environment: adb.appiumEnvironment(process.env),
    logger,
  });
  const sessions = new SessionManager({ appiumUrl: options.appiumUrl, roles: ROLE_CONFIG, logger });
  const checkpoint = new CheckpointStore({ filePath: DEFAULTS.checkpointPath, vault });

  try {
    await appium.start();
    await sessions.createAll();
    if (options.resume) {
      await checkpoint.loadRequired(scenario.version);
      const interrupted = checkpoint.state.inProgressStepId;
      if (interrupted && !steps.some((step) => step.id === interrupted)) {
        throw new Error(
          `Checkpoint contains interrupted step ${interrupted}, but the selected --from/--to range excludes it.`,
        );
      }
    } else await checkpoint.initialize(scenario.version);

    const executor = new ActionExecutor({
      sessions,
      roles: ROLE_CONFIG,
      adb,
      credentials,
      vault,
      logger,
      holdMs: options.holdMs,
      waitMs: DEFAULTS.waitMs,
    });
    const engine = new StepEngine({
      executor,
      checkpoint,
      sessions: sessions.sessions,
      artifactsPath: DEFAULTS.artifactsPath,
      vault,
      logger,
      holdMs: options.holdMs,
    });
    await engine.run(steps, { resume: options.resume });
    logger.info('[done] selected demo steps completed');
  } catch (error) {
    logger.error(error?.stack || error);
    throw error;
  } finally {
    try {
      await sessions.closeAll();
    } finally {
      try {
        await appium.stop();
      } finally {
        credentials.clear();
      }
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => { process.exitCode = 1; });
}
