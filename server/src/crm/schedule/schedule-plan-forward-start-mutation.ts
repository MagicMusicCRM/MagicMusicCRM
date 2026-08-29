import type { PoolClient } from "pg";
import type {
  PreparedSchedulePlanUpdate,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import type { SchedulePlanRepository } from "./schedule-plan.repository";

interface ForwardStartMutationReference extends Record<string, unknown> {
  planId: string;
  seriesIds: string[];
  lessonIds: string[];
}

export const moveSchedulePlanStartForward = async (input: {
  client: PoolClient;
  planId: string;
  version: number;
  prepared: PreparedSchedulePlanUpdate;
  repository: SchedulePlanRepository;
  definition: SchedulePlanDefinitionService;
}): Promise<ForwardStartMutationReference> => {
  const seriesIds = input.prepared.activeSeries.map((series) => series.id);
  if (
    input.prepared.plan.kind === "individual" &&
    input.prepared.plan.subscription_id
  ) {
    await input.repository.freezeActiveSeriesSubscription(
      input.client,
      seriesIds,
      input.prepared.plan.subscription_id,
    );
  }
  await input.repository.deleteScheduledLessonsInRange(
    input.client,
    input.planId,
    input.prepared.plan.active_from,
    input.prepared.effectiveFrom,
  );
  await input.repository.moveSeriesStart(
    input.client,
    seriesIds,
    input.prepared.effectiveFrom,
    input.version,
  );
  if (input.prepared.plan.kind === "group") {
    await input.repository.moveParticipantStart(
      input.client,
      input.planId,
      input.prepared.effectiveFrom,
      input.version,
    );
  }
  await input.repository.updatePlan(input.client, {
    planId: input.planId,
    title: input.prepared.plan.title,
    subscriptionId: input.prepared.subscriptionId,
    activeFrom: input.prepared.effectiveFrom,
    activeUntil: input.prepared.activeUntil,
    version: input.version,
  });
  const lessonIds: string[] = [];
  for (const seriesId of seriesIds) {
    lessonIds.push(
      ...(await input.definition.lessonIds(input.client, seriesId)),
    );
  }
  return { planId: input.planId, seriesIds, lessonIds };
};
