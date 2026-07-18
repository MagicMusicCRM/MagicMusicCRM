import fs from 'node:fs/promises';
import path from 'node:path';

export class CheckpointStore {
  constructor({ filePath, vault }) {
    this.filePath = filePath;
    this.vault = vault;
    this.state = null;
  }

  async loadRequired(scenarioVersion) {
    let raw;
    try {
      raw = await fs.readFile(this.filePath, 'utf8');
    } catch (error) {
      if (error.code === 'ENOENT') throw new Error(`Resume requested, but checkpoint does not exist: ${this.filePath}`);
      throw error;
    }
    const state = JSON.parse(raw);
    if (state.scenarioVersion !== scenarioVersion) {
      throw new Error(`Checkpoint scenario ${state.scenarioVersion} does not match ${scenarioVersion}.`);
    }
    this.state = state;
    return state;
  }

  async initialize(scenarioVersion) {
    this.state = {
      schemaVersion: 1,
      scenarioVersion,
      runId: `${Date.now()}-${Math.random().toString(16).slice(2, 10)}`,
      startedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      completedStepIds: [],
      inProgressStepId: null,
      context: {},
    };
    await this.#save();
    return this.state;
  }

  async markStarted(step) {
    this.state.inProgressStepId = step.id;
    this.state.updatedAt = new Date().toISOString();
    await this.#save();
  }

  async markCompleted(step) {
    if (!this.state.completedStepIds.includes(step.id)) {
      this.state.completedStepIds.push(step.id);
    }
    this.state.inProgressStepId = null;
    this.state.updatedAt = new Date().toISOString();
    if (step.checkpointData) {
      this.state.context[step.id] = step.checkpointData;
    }
    await this.#save();
  }

  async #save() {
    this.vault.assertSafe(this.state, 'checkpoint');
    const directory = path.dirname(this.filePath);
    await fs.mkdir(directory, { recursive: true });
    const temporary = `${this.filePath}.${process.pid}.tmp`;
    await fs.writeFile(temporary, `${JSON.stringify(this.state, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
    await fs.rename(temporary, this.filePath);
  }
}
