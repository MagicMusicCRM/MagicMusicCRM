import { captureFailureArtifacts } from './artifacts.mjs';
import { sleep } from './time.mjs';

async function allConditions(executor, conditions, fallbackRole, { wait = false } = {}) {
  for (const condition of conditions || []) {
    if (!await executor.check(condition, fallbackRole, { wait })) return false;
  }
  return true;
}

export class StepEngine {
  constructor({ executor, checkpoint, sessions, artifactsPath, vault, logger, holdMs }) {
    this.executor = executor;
    this.checkpoint = checkpoint;
    this.sessions = sessions;
    this.artifactsPath = artifactsPath;
    this.vault = vault;
    this.logger = logger;
    this.holdMs = holdMs;
  }

  async run(steps, { resume = false } = {}) {
    for (const step of steps) {
      if (this.checkpoint.state.completedStepIds.includes(step.id)) {
        this.logger.info(`[skip] ${step.id} already completed`);
        continue;
      }

      if (resume && this.checkpoint.state.inProgressStepId === step.id) {
        if (step.resumeActions?.length) {
          await this.executor.executeStepActions({ ...step, action: undefined, actions: step.resumeActions });
        }
        if (step.reconcile?.length && await allConditions(this.executor, step.reconcile, step.role)) {
          this.logger.info(`[reconcile] ${step.id} was completed before interruption`);
          await this.checkpoint.markCompleted(step);
          continue;
        }
        if (step.mutating && step.idempotent !== true) {
          throw new Error(
            `Step ${step.id} may have mutated business state. Reconcile it manually or mark it idempotent before resume.`,
          );
        }
      }

      if (step.mutating && !step.reconcile?.length) {
        throw new Error(`Mutating step ${step.id} must define reconcile conditions.`);
      }

      await this.checkpoint.markStarted(step);
      this.logger.info(`[step] ${step.id}: ${step.description || ''}`);
      try {
        await this.executor.executeStepActions(step);
        await allConditions(this.executor, step.wait, step.role, { wait: true });
        const assertionsPass = await allConditions(this.executor, step.assert, step.role);
        if (!assertionsPass) throw new Error(`Postcondition failed for step ${step.id}.`);
        const presentationHold = step.holdMs ?? this.holdMs;
        if (presentationHold > 0) {
          this.logger.info(`[hold] ${step.id}: ${presentationHold} ms`);
          await sleep(presentationHold);
        }
        await this.checkpoint.markCompleted(step);
      } catch (error) {
        await captureFailureArtifacts({
          step,
          sessions: this.sessions,
          basePath: this.artifactsPath,
          vault: this.vault,
          logger: this.logger,
          error,
        });
        throw error;
      }
    }
  }
}
