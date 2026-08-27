import { DEFAULTS } from './demo-runner-config.mjs';

export function parseArgs(argv) {
  const options = {
    dryRun: false,
    resume: false,
    from: undefined,
    to: undefined,
    holdMs: DEFAULTS.holdMs,
    scenarioPath: DEFAULTS.scenarioPath,
    appiumUrl: DEFAULTS.appiumUrl,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) throw new Error(`${arg} requires a value.`);
      index += 1;
      return value;
    };
    switch (arg) {
      case '--dry-run': options.dryRun = true; break;
      case '--resume': options.resume = true; break;
      case '--from': options.from = next(); break;
      case '--to': options.to = next(); break;
      case '--hold-ms': options.holdMs = Number(next()); break;
      case '--scenario': options.scenarioPath = next(); break;
      case '--appium-url': options.appiumUrl = next(); break;
      case '--help': case '-h': options.help = true; break;
      default: throw new Error(`Unknown option: ${arg}`);
    }
  }
  if (!Number.isInteger(options.holdMs) || options.holdMs < 0 || options.holdMs > 120_000) {
    throw new Error('--hold-ms must be an integer between 0 and 120000.');
  }
  new URL(options.appiumUrl);
  return options;
}

export const HELP = `MagicMusicCRM four-AVD demo runner

Usage: npm run demo -- [options]

  --dry-run           Validate AVD/app mapping and print the selected plan only
  --resume            Continue from the local checkpoint using reconcile guards
  --from <step-id>     Start at this enabled step (inclusive)
  --to <step-id>       Stop at this enabled step (inclusive)
  --hold-ms <number>   Presentation pause after every step (default: 5000)
  --scenario <path>    Data-driven JSON scenario
  --appium-url <url>   Appium endpoint (default: http://127.0.0.1:4723)
  --help               Show this help
`;
