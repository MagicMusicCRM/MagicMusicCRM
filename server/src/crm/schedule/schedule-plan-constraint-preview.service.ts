import { Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { CrmPolicy } from "../crm.policy";
import type {
  CreateSchedulePlanDto,
  SchedulePlanConstraintPreviewDto,
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { groupScheduleConflicts } from "./schedule-analyzer";
import {
  type NormalizedSchedulePlanCreate,
  type PreparedSchedulePlanUpdate,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import {
  failSchedulePlan,
  schedulePlanStableId,
} from "./schedule-plan-definition.service";
import { previousScheduleDate } from "./schedule-plan-backdate";
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
  historical: SchedulePlanHistoricalProjection;
}

interface SchedulePlanHistoricalOccurrence {
  rowIndex: number;
  localDate: string;
  startAt: string;
  endAt: string;
}

interface SchedulePlanHistoricalProjection {
  confirmRequired: boolean;
  count: number;
  from: string | null;
  until: string | null;
  occurrences: SchedulePlanHistoricalOccurrence[];
  previewToken?: string;
  previewExpiresAt?: string;
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
    private readonly previewTokens: SubscriptionPreviewTokenService,
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
      const authorizedRows = await this.authorizedRows(
        client,
        actor,
        normalized.rows,
      );
      const rows = await this.previewRows(
        client,
        authorizedRows,
        normalized.activeFrom,
        normalized.activeUntil,
        studentIds,
        { includeSuggestions: true, includePast: true },
      );
      this.overlap.addCrossRowViolations(normalized.rows, rows, studentIds);
      return this.projection(
        rows,
        this.issueHistoricalProjection(
          {
            actor,
            operation: "create",
            planId: null,
            expectedVersion: 0,
            activeFrom: normalized.activeFrom,
            activeUntil: normalized.activeUntil,
            clientFingerprint: this.createClientFingerprint(normalized),
            draftFingerprint: fingerprintPayload(normalized),
          },
          rows,
        ),
      );
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
      const authorizedRows = await this.authorizedRows(
        client,
        actor,
        dto.rows,
        prepared,
      );
      const rows = await this.previewUpdateRows(
        client,
        authorizedRows,
        prepared,
      );
      this.overlap.addCrossRowViolations(dto.rows, rows, prepared.studentIds);
      return this.projection(
        rows,
        this.issueHistoricalProjection(
          {
            actor,
            operation: "update",
            planId,
            expectedVersion: dto.expectedVersion,
            activeFrom: this.updatePreviewFrom(prepared),
            activeUntil: this.updatePreviewUntil(prepared),
            clientFingerprint: this.updateClientFingerprint(prepared),
            draftFingerprint: this.updateFingerprint(planId, dto, prepared),
          },
          rows,
        ),
      );
    });
  }

  async assertCreateHistoricalConfirmation(
    client: PoolClient,
    actor: ActorContext,
    normalized: NormalizedSchedulePlanCreate,
    dto: CreateSchedulePlanDto,
  ): Promise<boolean> {
    const authorizedRows = await this.authorizedRows(
      client,
      actor,
      normalized.rows,
    );
    const rows = await this.previewRows(
      client,
      authorizedRows,
      normalized.activeFrom,
      normalized.activeUntil,
      this.createStudentIds(normalized),
      { includePast: true },
    );
    return this.assertHistoricalConfirmation(dto, rows, {
      actor,
      operation: "create",
      planId: null,
      expectedVersion: 0,
      activeFrom: normalized.activeFrom,
      activeUntil: normalized.activeUntil,
      clientFingerprint: this.createClientFingerprint(normalized),
      draftFingerprint: fingerprintPayload(normalized),
    });
  }

  async assertUpdateHistoricalConfirmation(
    client: PoolClient,
    actor: ActorContext,
    planId: string,
    dto: UpdateSchedulePlanDto,
    prepared: PreparedSchedulePlanUpdate,
  ): Promise<boolean> {
    const authorizedRows = await this.authorizedRows(
      client,
      actor,
      dto.rows,
      prepared,
    );
    const rows = await this.previewUpdateRows(client, authorizedRows, prepared);
    return this.assertHistoricalConfirmation(dto, rows, {
      actor,
      operation: "update",
      planId,
      expectedVersion: dto.expectedVersion,
      activeFrom: this.updatePreviewFrom(prepared),
      activeUntil: this.updatePreviewUntil(prepared),
      clientFingerprint: this.updateClientFingerprint(prepared),
      draftFingerprint: this.updateFingerprint(planId, dto, prepared),
    });
  }

  private createStudentIds(normalized: NormalizedSchedulePlanCreate) {
    return normalized.kind === "individual"
      ? [normalized.studentId!]
      : normalized.participants.map((participant) => participant.studentId);
  }

  private async authorizedRows(
    client: PoolClient,
    actor: ActorContext,
    rows: SchedulePlanRowDto[],
    prepared?: PreparedSchedulePlanUpdate,
  ): Promise<SchedulePlanRowDto[]> {
    return Promise.all(
      rows.map(async (row) => {
        const stored = prepared?.activeSeries.find(
          (series) => series.id === row.seriesId,
        )?.planned_financial_decision;
        const requestedDecision = this.policy.canManageTeacherCompensation(actor)
          ? row.financialDecision
          : stored
          ? {
              ...row.financialDecision,
              teacherCompensationRuleKey: stored.teacherCompensationRuleKey,
              teacherCompensationValueMinor:
                stored.teacherCompensationValueMinor,
              teacherCreditedDurationMinutes:
                stored.teacherCreditedDurationMinutes,
              teacherCompensationSource: stored.teacherCompensationSource,
            }
          : await this.settlement.applyDefaultTeacherCompensation(
              client,
              row.branchId,
              row.financialDecision,
            );
        const preservedTeacherDecision = stored &&
            sameTeacherDecision(requestedDecision, stored)
          ? {
              teacherCompensationRuleKey: stored.teacherCompensationRuleKey,
              teacherCompensationValueMinor:
                stored.teacherCompensationValueMinor,
              teacherCreditedDurationMinutes:
                stored.teacherCreditedDurationMinutes,
              teacherCompensationSource: stored.teacherCompensationSource,
            }
          : undefined;
        const financialDecision = await this.settlement.resolvePlannedDecision(
          client,
          {
            branchId: row.branchId,
            durationMinutes: row.durationMinutes ?? 60,
            decision: requestedDecision,
            actorUserId: actor.userId,
            authorization:
              this.policy.teacherCompensationMutationAuthorization(actor),
            reasonText: row.plannedSettlementReason,
            ...(preservedTeacherDecision ? { preservedTeacherDecision } : {}),
          },
        );
        return { ...row, financialDecision };
      }),
    );
  }

  private previewUpdateRows(
    client: PoolClient,
    rows: SchedulePlanRowDto[],
    prepared: PreparedSchedulePlanUpdate,
  ) {
    return this.previewRows(
      client,
      rows,
      this.updatePreviewFrom(prepared),
      this.updatePreviewUntil(prepared),
      prepared.studentIds,
      {
        excludeScheduleSeriesIds: prepared.activeSeries.map(
          (series) => series.id,
        ),
        includeSuggestions: true,
        includePast: true,
      },
    );
  }

  private async previewRows(
    client: PoolClient,
    rows: SchedulePlanRowDto[],
    activeFrom: string,
    activeUntil: string | null,
    studentIds: string[],
    options: {
      excludeScheduleSeriesIds?: string[];
      includeSuggestions?: boolean;
      includePast?: boolean;
    },
  ): Promise<SchedulePlanRowPreview[]> {
    await this.series.assertPlanExpansionBounds(
      client,
      rows,
      activeFrom,
      activeUntil,
    );
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
    historical: SchedulePlanHistoricalProjection,
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
      historical,
    };
  }

  private issueHistoricalProjection(
    input: HistoricalTokenInput,
    rows: SchedulePlanRowPreview[],
  ): SchedulePlanHistoricalProjection {
    const occurrences = this.historicalOccurrences(rows);
    if (occurrences.length === 0) return this.emptyHistoricalProjection();
    const signed = this.previewTokens.issueSchedulePlanHistory({
      ...this.historyTokenFacts(input, occurrences),
      kind: "schedule.plan.history",
    });
    return {
      confirmRequired: true,
      count: occurrences.length,
      from: occurrences[0]!.localDate,
      until: occurrences[occurrences.length - 1]!.localDate,
      occurrences,
      previewToken: signed.token,
      previewExpiresAt: signed.expiresAt,
    };
  }

  private assertHistoricalConfirmation(
    dto: CreateSchedulePlanDto | UpdateSchedulePlanDto,
    rows: SchedulePlanRowPreview[],
    input: HistoricalTokenInput,
  ): boolean {
    const occurrences = this.historicalOccurrences(rows);
    if (occurrences.length === 0) return false;
    const previewToken = dto.previewToken?.trim();
    if (dto.confirmHistorical !== true || !previewToken) {
      failSchedulePlan("SCHEDULE_PLAN_HISTORY_CONFIRMATION_REQUIRED", [
        "confirmHistorical",
        "previewToken",
      ]);
    }
    const signed = this.previewTokens.verifySchedulePlanHistory(previewToken!);
    const expected = {
      ...this.historyTokenFacts(input, occurrences),
      kind: "schedule.plan.history" as const,
    };
    const signedFacts = {
      kind: signed.kind,
      operation: signed.operation,
      actorUserId: signed.actorUserId,
      planId: signed.planId,
      expectedVersion: signed.expectedVersion,
      activeFrom: signed.activeFrom,
      activeUntil: signed.activeUntil,
      clientFingerprint: signed.clientFingerprint,
      draftFingerprint: signed.draftFingerprint,
      historyFingerprint: signed.historyFingerprint,
    };
    if (fingerprintPayload(signedFacts) !== fingerprintPayload(expected)) {
      failSchedulePlan("SCHEDULE_PLAN_HISTORY_PREVIEW_STALE", ["previewToken"]);
    }
    return true;
  }

  private historyTokenFacts(
    input: HistoricalTokenInput,
    occurrences: SchedulePlanHistoricalOccurrence[],
  ) {
    return {
      operation: input.operation,
      actorUserId: input.actor.userId,
      planId: input.planId,
      expectedVersion: input.expectedVersion,
      activeFrom: input.activeFrom,
      activeUntil: input.activeUntil,
      clientFingerprint: input.clientFingerprint,
      draftFingerprint: input.draftFingerprint,
      historyFingerprint: fingerprintPayload(occurrences),
    };
  }

  private historicalOccurrences(
    rows: SchedulePlanRowPreview[],
  ): SchedulePlanHistoricalOccurrence[] {
    return rows
      .flatMap((row) =>
        row.occurrences
          .filter((occurrence) => occurrence.historical)
          .map((occurrence) => ({
            rowIndex: row.index,
            localDate: occurrence.localDate,
            startAt: occurrence.startAt,
            endAt: occurrence.endAt,
          })),
      )
      .sort(
        (left, right) =>
          left.startAt.localeCompare(right.startAt) ||
          left.rowIndex - right.rowIndex,
      );
  }

  private emptyHistoricalProjection(): SchedulePlanHistoricalProjection {
    return {
      confirmRequired: false,
      count: 0,
      from: null,
      until: null,
      occurrences: [],
    };
  }

  private updateFingerprint(
    planId: string,
    dto: UpdateSchedulePlanDto,
    prepared: PreparedSchedulePlanUpdate,
  ) {
    return fingerprintPayload({
      planId,
      expectedVersion: dto.expectedVersion,
      title: dto.title?.trim() || prepared.plan.title,
      subscriptionId: prepared.subscriptionId,
      activeFrom: prepared.effectiveFrom,
      activeUntil: prepared.activeUntil,
      prefixUntil: prepared.prefixUntil,
      mode: prepared.mode,
      previewFrom: this.updatePreviewFrom(prepared),
      previewUntil: this.updatePreviewUntil(prepared),
      participants: prepared.participants,
      rows: dto.rows,
    });
  }

  private createClientFingerprint(normalized: NormalizedSchedulePlanCreate) {
    return fingerprintPayload({
      kind: normalized.kind,
      studentId: normalized.studentId,
      groupId: normalized.groupId,
      subscriptionId: normalized.subscriptionId,
      participants: normalized.participants,
    });
  }

  private updateClientFingerprint(prepared: PreparedSchedulePlanUpdate) {
    return fingerprintPayload({
      kind: prepared.plan.kind,
      studentId: prepared.plan.student_id,
      groupId: prepared.plan.group_id,
      subscriptionId: prepared.subscriptionId,
      participants: prepared.participants,
    });
  }

  private updatePreviewUntil(prepared: PreparedSchedulePlanUpdate) {
    if (prepared.mode === "extend_backwards") return prepared.prefixUntil;
    return prepared.mode === "move_start_forward"
      ? previousScheduleDate(prepared.effectiveFrom)
      : prepared.activeUntil;
  }

  private updatePreviewFrom(prepared: PreparedSchedulePlanUpdate) {
    return prepared.mode === "move_start_forward"
      ? prepared.plan.active_from
      : prepared.effectiveFrom;
  }
}

function sameTeacherDecision(
  left: SchedulePlanRowDto["financialDecision"],
  right: SchedulePlanRowDto["financialDecision"],
) {
  return left.teacherCompensationRuleKey ===
      right.teacherCompensationRuleKey &&
    left.teacherCompensationValueMinor ===
      right.teacherCompensationValueMinor &&
    left.teacherCreditedDurationMinutes ===
      right.teacherCreditedDurationMinutes &&
    left.teacherCompensationSource === right.teacherCompensationSource;
}

interface HistoricalTokenInput {
  actor: ActorContext;
  operation: "create" | "update";
  planId: string | null;
  expectedVersion: number;
  activeFrom: string;
  activeUntil: string | null;
  clientFingerprint: string;
  draftFingerprint: string;
}
