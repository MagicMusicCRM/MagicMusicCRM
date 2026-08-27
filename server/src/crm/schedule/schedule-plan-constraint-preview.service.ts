import { Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import type { DatabaseService } from "../../db/database.service";
import type { LessonSettlementService } from "../commerce/lesson-settlement.service";
import type { CrmPolicy } from "../crm.policy";
import type {
  SchedulePlanConstraintPreviewDto,
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import type { LessonSeriesCommandService } from "./lesson-series-command.service";
import { groupScheduleConflicts } from "./schedule-analyzer";
import type {
  NormalizedSchedulePlanCreate,
  PreparedSchedulePlanUpdate,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import { schedulePlanStableId } from "./schedule-plan-definition.service";
import {
  SchedulePlanOverlapAnalyzer,
  type SchedulePlanRowPreview,
} from "./schedule-plan-overlap-analyzer";

export interface SchedulePlanConstraintProjection {
  valid: boolean;
  conflicts: ReturnType<typeof groupScheduleConflicts>;
  rows: Array<{
    index: number;
    valid: boolean;
    occurrencesChecked: number;
    failures: SchedulePlanRowPreview["failures"];
    suggestions: SchedulePlanRowPreview["suggestions"];
  }>;
}

@Injectable()
export class SchedulePlanConstraintPreviewService {
  private readonly overlap = new SchedulePlanOverlapAnalyzer();

  constructor(
    private readonly policy: CrmPolicy,
    private readonly database: DatabaseService,
    private readonly definition: SchedulePlanDefinitionService,
    private readonly series: LessonSeriesCommandService,
    private readonly settlement: LessonSettlementService,
  ) {}

  async previewConstraints(
    actor: ActorContext,
    dto: SchedulePlanConstraintPreviewDto,
  ): Promise<SchedulePlanConstraintProjection> {
    this.policy.assertCanWriteCrm(actor);
    const normalized = this.definition.normalizeCreate(dto);
    return this.database.transaction(async (client) => {
      const studentIds = this.createStudentIds(normalized);
      await this.definition.lockAndValidate(client, {
        planId: schedulePlanStableId(`schedule.plan.preview\0${actor.userId}`),
        kind: normalized.kind,
        studentId: normalized.studentId,
        groupId: normalized.groupId,
        subscriptionId: normalized.subscriptionId,
        participants: normalized.participants,
        rows: normalized.rows,
      });
      const rows = await this.previewRows(
        client,
        normalized.rows,
        normalized.activeFrom,
        normalized.activeUntil,
        studentIds,
        { includeSuggestions: true },
      );
      this.overlap.addCrossRowViolations(normalized.rows, rows, studentIds);
      return this.projection(rows);
    });
  }

  async previewUpdateConstraints(
    actor: ActorContext,
    planId: string,
    dto: UpdateSchedulePlanDto,
  ): Promise<SchedulePlanConstraintProjection> {
    this.policy.assertCanWriteCrm(actor);
    this.definition.assertRows(dto.rows);
    return this.database.transaction(async (client) => {
      const prepared = await this.definition.prepareUpdate(client, planId, dto);
      const rows = await this.previewUpdateRows(client, dto.rows, prepared);
      this.overlap.addCrossRowViolations(dto.rows, rows, prepared.studentIds);
      return this.projection(rows);
    });
  }

  private createStudentIds(normalized: NormalizedSchedulePlanCreate) {
    return normalized.kind === "individual"
      ? [normalized.studentId!]
      : normalized.participants.map((participant) => participant.studentId);
  }

  private previewUpdateRows(
    client: PoolClient,
    rows: SchedulePlanRowDto[],
    prepared: PreparedSchedulePlanUpdate,
  ) {
    return this.previewRows(
      client,
      rows,
      prepared.effectiveFrom,
      prepared.activeUntil,
      prepared.studentIds,
      {
        excludeScheduleSeriesIds: prepared.activeSeries.map(
          (series) => series.id,
        ),
        includeSuggestions: true,
      },
    );
  }

  private async previewRows(
    client: PoolClient,
    rows: SchedulePlanRowDto[],
    activeFrom: string,
    activeUntil: string | null,
    studentIds: string[],
    options: { excludeScheduleSeriesIds?: string[]; includeSuggestions: true },
  ): Promise<SchedulePlanRowPreview[]> {
    const previews: SchedulePlanRowPreview[] = [];
    for (const [index, row] of rows.entries()) {
      await this.settlement.preparePlan(
        client,
        row.branchId,
        row.financialDecision,
      );
      previews.push({
        index,
        ...(await this.series.previewPlanRow(
          client,
          row,
          activeFrom,
          activeUntil,
          studentIds,
          options,
        )),
      });
    }
    return previews;
  }

  private projection(
    rows: SchedulePlanRowPreview[],
  ): SchedulePlanConstraintProjection {
    const conflicts = groupScheduleConflicts(
      rows.flatMap((row) =>
        row.failures.flatMap((failure) =>
          failure.violations.map((violation) => ({
            violation,
            scope: {
              rowIndex: row.index,
              studentId: failure.studentId,
              localDate: failure.occurrence.localDate,
            },
          })),
        ),
      ),
    );
    return {
      valid: rows.every((row) => row.failures.length === 0),
      conflicts,
      rows: rows.map((row) => ({
        index: row.index,
        valid: row.failures.length === 0,
        occurrencesChecked: row.occurrences.length,
        failures: row.failures,
        suggestions: row.suggestions,
      })),
    };
  }
}
