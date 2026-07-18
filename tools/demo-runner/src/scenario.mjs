import fs from 'node:fs/promises';
import path from 'node:path';

export async function loadScenario(filePath) {
  const absolute = path.resolve(filePath);
  const scenario = JSON.parse(await fs.readFile(absolute, 'utf8'));
  if (!scenario.version || !Array.isArray(scenario.steps)) {
    throw new Error(`Invalid scenario file: ${absolute}`);
  }
  const ids = scenario.steps.map((step) => step.id);
  if (ids.some((id) => typeof id !== 'string' || id.length === 0) || new Set(ids).size !== ids.length) {
    throw new Error('Every scenario step must have a unique non-empty id.');
  }
  return { ...scenario, filePath: absolute };
}

export function selectSteps(steps, { from, to } = {}) {
  const enabled = steps.filter((step) => step.enabled !== false);
  const fromIndex = from ? enabled.findIndex((step) => step.id === from) : 0;
  const toIndex = to ? enabled.findIndex((step) => step.id === to) : enabled.length - 1;
  if (from && fromIndex < 0) throw new Error(`Unknown --from step: ${from}`);
  if (to && toIndex < 0) throw new Error(`Unknown --to step: ${to}`);
  if (fromIndex > toIndex && enabled.length > 0) throw new Error('--from occurs after --to.');
  return enabled.slice(fromIndex, toIndex + 1);
}
