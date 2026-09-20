import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import type {
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import type { LessonSeriesCommandService } from "./lesson-series-command.service";
import type { PreparedSchedulePlanRow } from "./schedule-plan-constraint-preview.service";
import type {
  PreparedSchedulePlanUpdate,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import type {
  SchedulePlanRepository,
} from "./schedule-plan.repository";
import type { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";

interface BackdateMutationReference extends Record<string, unknown> {
  planId: string;
  seriesIds: string[];
  lessonIds: string[];
}

export const extendSchedulePlanBackwards = async (input: {
  client: PoolClient;
  actor: ActorContext;
  planId: string;
  version: number;
  dto: UpdateSchedulePlanDto;
  prepared: PreparedSchedulePlanUpdate;
  repository: SchedulePlanRepository;
  series: LessonSeriesCommandService;
  materializer: ScheduleSeriesMaterializerService;
  definition: SchedulePlanDefinitionService;
  preparedRows: PreparedSchedulePlanRow[];
  insertSeries: (
    args: Omit<
      Parameters<SchedulePlanRepository["insertSeries"]>[1],
      "settlementPlan"
    >,
    preparedRow: PreparedSchedulePlanRow,
  ) => Promise<void>;
}): Promise<BackdateMutationReference> => {
  const prefixUntil = input.prepared.prefixUntil!;
  const seriesIds: string[] = [];
  for (const [index, row] of input.dto.rows.entries()) {
    await input.series.validatePlanRow(
      input.client,
      row,
      input.prepared.effectiveFrom,
      prefixUntil,
      input.prepared.studentIds,
      true,
    );
    const seriesId = input.definition.seriesId(
      input.planId,
      input.version,
      index,
    );
    await input.insertSeries(
      {
        id: seriesId,
        planId: input.planId,
        studentId: input.prepared.plan.student_id,
        groupId: input.prepared.plan.group_id,
        validFrom: input.prepared.effectiveFrom,
        validUntil: prefixUntil,
        row,
        actorUserId: input.actor.userId,
        version: input.version,
        subscriptionId: input.prepared.subscriptionId,
        supersededBy: row.seriesId!,
      },
      input.preparedRows[index]!,
    );
    seriesIds.push(seriesId);
  }
  if (input.prepared.plan.kind === "group") {
    await input.repository.insertParticipants(
      input.client,
      input.planId,
      input.prepared.participants,
      input.prepared.effectiveFrom,
      prefixUntil,
      input.version,
    );
  }
  await input.repository.extendPlanStart(input.client, {
    planId: input.planId,
    activeFrom: input.prepared.effectiveFrom,
    title: input.dto.title?.trim() || input.prepared.plan.title,
    version: input.version,
  });
  const lessonIds: string[] = [];
  for (const seriesId of seriesIds) {
    await input.materializer.materializePlanSeries(input.client, seriesId, {
      includePast: true,
    });
    lessonIds.push(
      ...(await input.definition.lessonIds(input.client, seriesId)),
    );
  }
  return { planId: input.planId, seriesIds, lessonIds };
};
