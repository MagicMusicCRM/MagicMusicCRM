import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { Pool, type PoolClient, type QueryResult, type QueryResultRow } from "pg";
import { loadLessonSettlementCatalog } from "../../../crm/commerce/lesson-settlement-catalog";
import type { LessonFinancialDecision } from "../../../crm/commerce/lesson-settlement.port";
import { resolveSettlementPolicy } from "../../../crm/commerce/lesson-settlement-policy";
import type { SettlementDurationMode } from "../../../crm/crm-configuration.contracts";
import type { LessonPlannedSettlementCommandService } from "../../../crm/schedule/lesson-planned-settlement-command.service";
import type { SchedulePlanMutationService } from "../../../crm/schedule/schedule-plan-mutation.service";
import type { ActorContext, UserRole } from "../../../common/security/actor-context";
import type { DatabaseService } from "../../../db/database.service";
import { fingerprintPayload } from "../../../platform/platform-integrity.util";
import {
  createSettlementPolicyReport,
  SETTLEMENT_POLICY_CANDIDATE_REVISION,
  type SettlementPolicyClassification,
  type SettlementPolicyRepairCandidate,
  type SettlementPolicyReconciliationReport,
  settlementDecisionHash,
  verifySettlementPolicyReport,
} from "./lesson-settlement-policy-report";
import { ensureSystemSettlementPolicyRevision } from "./settlement-policy-configuration";

export interface SettlementPolicyCandidateInput {
  entityType: "lesson_plan" | "schedule_series";
  entityId: string;
  aggregateId?: string;
  expectedVersion: number;
  lifecycleState: string;
  durationMinutes: number;
  settlementTypeKey: string | null;
  settlementTypeActive: boolean;
  clientDurationMode: SettlementDurationMode | null;
  teacherDurationMode: SettlementDurationMode | null;
  defaultTeacherCompensationRuleKey: string | null;
  teacherCompensationRuleKey: string | null;
  teacherCompensationSource: "automatic" | "manual" | null;
  manualReason: string | null;
  decision: LessonFinancialDecision | null;
}

export interface SettlementPolicyClassificationResult {
  classification: SettlementPolicyClassification;
  reasonCode: string;
  proposedDecision?: LessonFinancialDecision;
}

export function classifySettlementPolicyCandidate(
  input: SettlementPolicyCandidateInput,
): SettlementPolicyClassificationResult {
  if (!isDecision(input.decision) || !input.settlementTypeKey ||
      !input.settlementTypeActive || !input.clientDurationMode ||
      !input.teacherDurationMode ||
      !input.defaultTeacherCompensationRuleKey) {
    return classified("invalid", "INVALID_LEGACY_DECISION");
  }
  if (!["scheduled", "settlement_pending"].includes(input.lifecycleState)) {
    return classified("historical_terminal", "TERMINAL_OR_INACTIVE");
  }
  if (input.teacherCompensationSource === "manual" ||
      (input.teacherCompensationSource !== "automatic" &&
        Boolean(input.manualReason?.trim()))) {
    return classified("explicit_manual", "EXPLICIT_MANUAL_DECISION");
  }
  if (input.clientDurationMode === "manual" ||
      input.teacherDurationMode === "manual") {
    return classified("ambiguous", "PARTIAL_DURATION_REQUIRES_REVIEW");
  }
  if (input.teacherDurationMode === "zero") {
    return input.teacherCompensationRuleKey === "none"
      ? classified("clean", "ZERO_SETTLEMENT_POLICY_MATCHES")
      : classified("ambiguous", "ZERO_SETTLEMENT_POLICY_MISMATCH");
  }
  if (input.teacherDurationMode !== "full") {
    return classified("ambiguous", "UNKNOWN_DURATION_POLICY");
  }
  if (input.teacherCompensationSource === "automatic") {
    return input.teacherCompensationRuleKey ===
        input.defaultTeacherCompensationRuleKey
      ? classified("clean", "AUTOMATIC_POLICY_MATCHES")
      : classified("ambiguous", "AUTOMATIC_POLICY_MISMATCH");
  }
  if (input.teacherCompensationSource !== null ||
      !["none", input.defaultTeacherCompensationRuleKey].includes(
        input.teacherCompensationRuleKey ?? "",
      )) {
    return classified("ambiguous", "UNPROVEN_LEGACY_DECISION");
  }
  const proposedDecision: LessonFinancialDecision = {
    settlementTypeKey: input.settlementTypeKey,
    teacherCompensationRuleKey: input.defaultTeacherCompensationRuleKey,
    teacherCreditedDurationMinutes: input.durationMinutes,
    teacherCompensationSource: "automatic",
  };
  return {
    classification: "repairable_automatic",
    reasonCode: input.teacherCompensationRuleKey === "none"
      ? "AUTOMATIC_FULL_RATE_OMITTED"
      : "AUTOMATIC_SOURCE_OMITTED",
    proposedDecision,
  };
}

function classified(
  classification: SettlementPolicyClassification,
  reasonCode: string,
): SettlementPolicyClassificationResult {
  return { classification, reasonCode };
}

function isDecision(value: unknown): value is LessonFinancialDecision {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const decision = value as Record<string, unknown>;
  return typeof decision.settlementTypeKey === "string" &&
    typeof decision.teacherCompensationRuleKey === "string" &&
    (decision.teacherCompensationSource === undefined ||
      decision.teacherCompensationSource === "automatic" ||
      decision.teacherCompensationSource === "manual");
}

export interface SettlementPolicyApplyCommand {
  proposedDecision: LessonFinancialDecision;
  idempotencyKey: string;
  configurationRevisionId: string;
}

export interface SettlementPolicyApplyDependencies {
  candidateRevision: string;
  ensureConfiguration: () => Promise<{
    revisionId: string;
    created: boolean;
  }>;
  loadCandidate: (
    entityType: "lesson_plan" | "schedule_series",
    entityId: string,
  ) => Promise<SettlementPolicyCandidateInput | null>;
  repair: (
    current: SettlementPolicyCandidateInput,
    command: SettlementPolicyApplyCommand,
  ) => Promise<void>;
  repairScheduleGroup?: (
    items: SettlementPolicyScheduleGroupItem[],
  ) => Promise<void>;
}

export interface SettlementPolicyScheduleGroupItem {
  current: SettlementPolicyCandidateInput;
  candidate: SettlementPolicyReconciliationReport["candidates"][number];
  command: SettlementPolicyApplyCommand;
}

export async function applySettlementPolicyCandidates(
  report: SettlementPolicyReconciliationReport,
  dependencies: SettlementPolicyApplyDependencies,
): Promise<{
  mutations: number;
  configurationRevisionId: string | null;
  issues: Array<{ entityType: string; entityId: string; code: string }>;
}> {
  if (!verifySettlementPolicyReport(report) || report.mode !== "dry-run") {
    throw new Error("RECONCILIATION_REPORT_INVALID");
  }
  if (report.candidateRevision !== dependencies.candidateRevision) {
    throw new Error("RECONCILIATION_CANDIDATE_REVISION_MISMATCH");
  }
  if (report.counts.ambiguous > 0 || report.counts.invalid > 0 ||
      report.issues.length > 0) {
    throw new Error("RECONCILIATION_REPORT_BLOCKED");
  }
  let configurationRevisionId: string | null = null;
  let mutations = 0;
  const issues: Array<{ entityType: string; entityId: string; code: string }> = [];
  const pending: Array<{
    current: SettlementPolicyCandidateInput;
    candidate: SettlementPolicyReconciliationReport["candidates"][number];
  }> = [];
  for (const candidate of report.candidates) {
    if (candidate.classification !== "repairable_automatic") continue;
    const current = await dependencies.loadCandidate(
      candidate.entityType,
      candidate.entityId,
    );
    if (!current) {
      issues.push(staleIssue(candidate));
      continue;
    }
    const classification = classifySettlementPolicyCandidate(current);
    if (classification.classification === "clean") {
      if (current.decision && matchesProposedAutomaticResult(
        current.decision,
        candidate.proposedDecision,
      )) continue;
      issues.push(staleIssue(candidate));
      continue;
    }
    if (current.expectedVersion !== candidate.expectedVersion ||
        !current.decision ||
        settlementDecisionHash(current.decision) !==
          candidate.currentDecisionHash ||
        classification.classification !== "repairable_automatic") {
      issues.push(staleIssue(candidate));
      continue;
    }
    if (current.entityType === "schedule_series" && !current.aggregateId) {
      issues.push(staleIssue(candidate));
      continue;
    }
    pending.push({ current, candidate });
  }
  if (issues.length > 0) {
    return { mutations, configurationRevisionId, issues };
  }
  if (pending.length > 0) {
    configurationRevisionId =
      (await dependencies.ensureConfiguration()).revisionId;
  }
  const items = pending.map(({ current, candidate }) => ({
    current,
    candidate,
    command: {
      proposedDecision: candidate.proposedDecision,
      idempotencyKey: [
        "v8:settlement-policy",
        candidate.entityType,
        candidate.entityId,
        candidate.currentDecisionHash,
      ].join(":"),
      configurationRevisionId: configurationRevisionId!,
    },
  }));
  const scheduleGroups = new Map<string, SettlementPolicyScheduleGroupItem[]>();
  for (const item of items.filter(({ current }) =>
    current.entityType === "schedule_series")) {
    const group = scheduleGroups.get(item.current.aggregateId!) ?? [];
    group.push(item);
    scheduleGroups.set(item.current.aggregateId!, group);
  }
  for (const group of scheduleGroups.values()) {
    try {
      if (dependencies.repairScheduleGroup) {
        await dependencies.repairScheduleGroup(group);
      } else {
        for (const item of group) {
          await dependencies.repair(item.current, item.command);
        }
      }
      mutations += group.length;
    } catch (error) {
      if (!isReconciliationStale(error)) throw error;
      issues.push(...group.map(({ candidate }) => staleIssue(candidate)));
      return { mutations, configurationRevisionId, issues };
    }
  }
  for (const item of items.filter(({ current }) =>
    current.entityType === "lesson_plan")) {
    await dependencies.repair(item.current, item.command);
    mutations += 1;
  }
  return { mutations, configurationRevisionId, issues };
}

function matchesProposedAutomaticResult(
  live: LessonFinancialDecision,
  proposed: LessonFinancialDecision,
): boolean {
  return live.settlementTypeKey === proposed.settlementTypeKey &&
    live.teacherCompensationRuleKey ===
      proposed.teacherCompensationRuleKey &&
    live.teacherCreditedDurationMinutes ===
      proposed.teacherCreditedDurationMinutes &&
    live.teacherCompensationValueMinor ===
      proposed.teacherCompensationValueMinor &&
    live.teacherCompensationSource === "automatic";
}

function staleIssue(candidate: {
  entityType: string;
  entityId: string;
}) {
  return {
    entityType: candidate.entityType,
    entityId: candidate.entityId,
    code: "RECONCILIATION_STALE_CANDIDATE",
  };
}

function isReconciliationStale(error: unknown): boolean {
  return error instanceof Error &&
    error.message === "RECONCILIATION_STALE_CANDIDATE";
}

type Queryable = Pick<PoolClient, "query"> | Pick<DatabaseService, "query">;

interface RawCandidateRow extends QueryResultRow {
  entity_type: "lesson_plan" | "schedule_series";
  entity_id: string;
  aggregate_id: string;
  expected_version: number | string;
  lifecycle_state: string;
  duration_minutes: number | string;
  decision: unknown;
  manual_reason: string | null;
  settlement_revision_id: string;
  compensation_revision_id: string;
}

interface ReconciliationInvariantSnapshot {
  futureLessonCount: number;
  activeReservationUnits: string;
  effectiveTeacherFactCount: number;
  schedulePlanVersions: Map<string, number>;
}

interface ReconciliationRuntime {
  database: DatabaseService;
  actor: ActorContext;
  lessonCommands: Pick<
    LessonPlannedSettlementCommandService,
    "previewSettlementPlan" | "updateSettlementPlan"
  >;
  scheduleCommands: Pick<SchedulePlanMutationService, "update">;
}

export async function scanSettlementPolicyCandidates(
  queryable: Queryable,
): Promise<{
  candidates: SettlementPolicyRepairCandidate[];
  inputs: SettlementPolicyCandidateInput[];
}> {
  const result = await runQuery<RawCandidateRow>(queryable, `
    select 'lesson_plan'::text as entity_type, lesson.id as entity_id,
      lesson.id as aggregate_id,
      lesson.version as expected_version, lesson.lifecycle_state,
      lesson.duration_minutes, settlement.decision,
      settlement.reason_text as manual_reason,
      settlement.settlement_revision_id,
      settlement.compensation_revision_id
    from app.lesson_settlement_plans settlement
    join app.lessons lesson on lesson.id = settlement.lesson_id
    left join app.schedule_series lesson_series
      on lesson_series.id = lesson.series_id
    where lesson.deleted_at is null
      and (
        lesson.series_id is null
        or lesson.original_scheduled_at is not null
        or lesson.teacher_id is distinct from lesson_series.teacher_id
        or lesson.room_id is distinct from lesson_series.room_id
        or lesson.branch_id is distinct from lesson_series.branch_id
        or lesson.duration_minutes is distinct from lesson_series.duration_minutes
        or settlement.decision is distinct from
          lesson_series.planned_financial_decision
      )

    union all

    select 'schedule_series'::text, series.id, plan.id, plan.version,
      case when plan.status = 'active' and series.deleted_at is null
        and series.superseded_by is null then 'scheduled' else 'inactive' end,
      series.duration_minutes, series.planned_financial_decision,
      null::text, series.settlement_revision_id,
      series.compensation_revision_id
    from app.schedule_series series
    join app.schedule_plans plan on plan.id = series.plan_id
    order by entity_type, entity_id
  `);
  const cache = new Map<string, Awaited<ReturnType<
    typeof loadLessonSettlementCatalog
  >>>();
  const inputs: SettlementPolicyCandidateInput[] = [];
  const candidates: SettlementPolicyRepairCandidate[] = [];
  for (const row of result.rows) {
    const revisionKey = [
      row.settlement_revision_id,
      row.compensation_revision_id,
    ].join(":");
    let catalog = cache.get(revisionKey);
    if (!catalog) {
      try {
        catalog = await loadLessonSettlementCatalog(
          queryable as PoolClient,
          "",
          {
            settlementRevisionId: row.settlement_revision_id,
            compensationRevisionId: row.compensation_revision_id,
          },
        );
        cache.set(revisionKey, catalog);
      } catch {
        catalog = undefined;
      }
    }
    const input = candidateInputFromRow(row, catalog);
    const classification = classifySettlementPolicyCandidate(input);
    const currentDecisionHash = fingerprintPayload(row.decision);
    inputs.push(input);
    candidates.push({
      entityType: row.entity_type,
      entityId: row.entity_id,
      expectedVersion: Number(row.expected_version),
      currentDecisionHash,
      proposedDecision: classification.proposedDecision ?? {
        settlementTypeKey: safeStableKey(input.settlementTypeKey),
        teacherCompensationRuleKey: safeStableKey(
          input.teacherCompensationRuleKey,
        ),
      },
      classification: classification.classification,
      reasonCode: classification.reasonCode,
    });
  }
  return { candidates, inputs };
}

function candidateInputFromRow(
  row: RawCandidateRow,
  catalog: Awaited<ReturnType<typeof loadLessonSettlementCatalog>> | undefined,
): SettlementPolicyCandidateInput {
  const decision = isDecision(row.decision)
    ? row.decision as LessonFinancialDecision
    : null;
  const settlementTypeKey = decision?.settlementTypeKey ?? null;
  const settlementType = catalog?.settlement_types.find(
    (item) => item.stableKey === settlementTypeKey,
  );
  let policy: ReturnType<typeof resolveSettlementPolicy> | null = null;
  if (catalog && settlementType?.active) {
    try {
      policy = resolveSettlementPolicy(catalog, settlementTypeKey!);
    } catch {
      policy = null;
    }
  }
  return {
    entityType: row.entity_type,
    entityId: row.entity_id,
    aggregateId: row.aggregate_id,
    expectedVersion: Number(row.expected_version),
    lifecycleState: row.lifecycle_state,
    durationMinutes: Number(row.duration_minutes),
    settlementTypeKey,
    settlementTypeActive: settlementType?.active === true,
    clientDurationMode: policy?.clientDurationMode ?? null,
    teacherDurationMode: policy?.teacherDurationMode ?? null,
    defaultTeacherCompensationRuleKey:
      policy?.teacherCompensationRuleKey ?? null,
    teacherCompensationRuleKey:
      decision?.teacherCompensationRuleKey ?? null,
    teacherCompensationSource:
      decision?.teacherCompensationSource === "automatic" ||
      decision?.teacherCompensationSource === "manual"
        ? decision.teacherCompensationSource
        : null,
    manualReason: row.manual_reason,
    decision,
  };
}

function safeStableKey(value: string | null): string {
  return value && /^[A-Za-z0-9._:-]{1,120}$/.test(value)
    ? value
    : "invalid";
}

async function readInvariants(
  queryable: Queryable,
): Promise<ReconciliationInvariantSnapshot> {
  const aggregate = await runQuery<{
    future_lesson_count: number | string;
    active_reservation_units: string;
    effective_teacher_fact_count: number | string;
  }>(queryable, `
    select
      (select count(*) from app.lessons lesson
       where lesson.deleted_at is null
         and lesson.lifecycle_state in ('scheduled', 'settlement_pending')
         and lesson.scheduled_at >= now()) as future_lesson_count,
      (select coalesce(sum(reservation.units), 0)::text
       from app.lesson_reservations reservation
       where reservation.state = 'reserved') as active_reservation_units,
      (select count(*) from app.lesson_teacher_compensation_facts_effective)
        as effective_teacher_fact_count
  `);
  const versions = await runQuery<{ id: string; version: number | string }>(
    queryable,
    "select id, version from app.schedule_plans order by id",
  );
  const row = aggregate.rows[0]!;
  return {
    futureLessonCount: Number(row.future_lesson_count),
    activeReservationUnits: row.active_reservation_units,
    effectiveTeacherFactCount: Number(row.effective_teacher_fact_count),
    schedulePlanVersions: new Map(
      versions.rows.map((item) => [item.id, Number(item.version)]),
    ),
  };
}

function reportInvariants(
  before: ReconciliationInvariantSnapshot,
  after: ReconciliationInvariantSnapshot,
): SettlementPolicyReconciliationReport["invariants"] {
  const planIds = new Set([
    ...before.schedulePlanVersions.keys(),
    ...after.schedulePlanVersions.keys(),
  ]);
  const changes = [...planIds].flatMap((planId) => {
    const previous = before.schedulePlanVersions.get(planId);
    const current = after.schedulePlanVersions.get(planId);
    return previous !== undefined && current !== undefined &&
        previous !== current
      ? [{ planId, before: previous, after: current }]
      : [];
  }).sort((left, right) => left.planId.localeCompare(right.planId));
  return {
    futureLessonCountBefore: before.futureLessonCount,
    futureLessonCountAfter: after.futureLessonCount,
    activeReservationUnitsBefore: before.activeReservationUnits,
    activeReservationUnitsAfter: after.activeReservationUnits,
    effectiveTeacherFactCountBefore: before.effectiveTeacherFactCount,
    effectiveTeacherFactCountAfter: after.effectiveTeacherFactCount,
    schedulePlanVersionChanges: changes,
  };
}

async function runDryRun(pool: Pool): Promise<SettlementPolicyReconciliationReport> {
  const client = await pool.connect();
  try {
    await client.query("begin isolation level repeatable read read only");
    const before = await readInvariants(client);
    const scan = await scanSettlementPolicyCandidates(client);
    const report = createSettlementPolicyReport({
      mode: "dry-run",
      generatedAt: new Date().toISOString(),
      candidateRevision: SETTLEMENT_POLICY_CANDIDATE_REVISION,
      candidates: scan.candidates,
      issues: [],
      invariants: reportInvariants(before, before),
    });
    await client.query("rollback");
    return report;
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function runApply(
  runtime: ReconciliationRuntime,
  dryRun: SettlementPolicyReconciliationReport,
): Promise<{ report: SettlementPolicyReconciliationReport; mutations: number }> {
  const before = await readInvariants(runtime.database);
  const result = await applySettlementPolicyCandidates(dryRun, {
    candidateRevision: SETTLEMENT_POLICY_CANDIDATE_REVISION,
    ensureConfiguration: () => runtime.database.transaction((client) =>
      ensureSystemSettlementPolicyRevision(
        client,
        runtime.actor.userId,
      )),
    loadCandidate: async (entityType, entityId) => {
      const row = await loadRawCandidate(runtime.database, entityType, entityId);
      if (!row) return null;
      const catalog = await loadLessonSettlementCatalog(
        runtime.database as unknown as PoolClient,
        "",
        {
          settlementRevisionId: row.settlement_revision_id,
          compensationRevisionId: row.compensation_revision_id,
        },
      ).catch(() => undefined);
      return candidateInputFromRow(row, catalog);
    },
    repair: async (current, command) => {
      const decision = mergeAutomaticTeacherDecision(
        current.decision!,
        command.proposedDecision,
      );
      if (current.entityType === "lesson_plan") {
        await repairLessonPlan(runtime, current, decision, command.idempotencyKey);
      } else {
        throw new Error("SCHEDULE_GROUP_REPAIR_REQUIRED");
      }
    },
    repairScheduleGroup: (items) => repairScheduleSeriesGroup(runtime, items),
  });
  const after = await readInvariants(runtime.database);
  assertApplyInvariants(before, after);
  return {
    mutations: result.mutations,
    report: createSettlementPolicyReport({
      mode: "apply",
      generatedAt: new Date().toISOString(),
      candidateRevision: SETTLEMENT_POLICY_CANDIDATE_REVISION,
      candidates: dryRun.candidates,
      issues: [...dryRun.issues, ...result.issues],
      invariants: reportInvariants(before, after),
      systemSettlementPolicyRevisionId: result.configurationRevisionId,
    }),
  };
}

function mergeAutomaticTeacherDecision(
  current: LessonFinancialDecision,
  proposed: LessonFinancialDecision,
): LessonFinancialDecision {
  const {
    teacherRateSnapshot: _rate,
    teacherCompensationRuleKey: _rule,
    teacherCompensationValueMinor: _value,
    teacherCreditedDurationMinutes: _duration,
    teacherCompensationSource: _source,
    ...preserved
  } = current;
  return { ...preserved, ...proposed };
}

async function loadRawCandidate(
  queryable: Queryable,
  entityType: "lesson_plan" | "schedule_series",
  entityId: string,
): Promise<RawCandidateRow | null> {
  if (entityType === "lesson_plan") {
    const result = await runQuery<RawCandidateRow>(queryable, `
      select 'lesson_plan'::text as entity_type, lesson.id as entity_id,
        lesson.id as aggregate_id,
        lesson.version as expected_version, lesson.lifecycle_state,
        lesson.duration_minutes, settlement.decision,
        settlement.reason_text as manual_reason,
        settlement.settlement_revision_id,
        settlement.compensation_revision_id
      from app.lesson_settlement_plans settlement
      join app.lessons lesson on lesson.id = settlement.lesson_id
      where lesson.id = $1 and lesson.deleted_at is null
    `, [entityId]);
    return result.rows[0] ?? null;
  }
  const result = await runQuery<RawCandidateRow>(queryable, `
    with recursive lineage as (
      select series.*, 0 as depth, array[series.id] as path
      from app.schedule_series series where series.id = $1
      union all
      select successor.*, lineage.depth + 1,
        lineage.path || successor.id
      from lineage
      join app.schedule_series successor
        on successor.id = lineage.superseded_by
      where lineage.depth < 100 and not successor.id = any(lineage.path)
    )
    select 'schedule_series'::text as entity_type, $1::uuid as entity_id,
      plan.id as aggregate_id, plan.version as expected_version,
      case when plan.status = 'active' and series.deleted_at is null
        and series.superseded_by is null then 'scheduled' else 'inactive' end
        as lifecycle_state,
      series.duration_minutes, series.planned_financial_decision as decision,
      null::text as manual_reason, series.settlement_revision_id,
      series.compensation_revision_id
    from lineage series
    join app.schedule_plans plan on plan.id = series.plan_id
    order by series.depth desc limit 1
  `, [entityId]);
  return result.rows[0] ?? null;
}

async function repairLessonPlan(
  runtime: ReconciliationRuntime,
  current: SettlementPolicyCandidateInput,
  decision: LessonFinancialDecision,
  idempotencyKey: string,
): Promise<void> {
  if (!decision.clientDecisions?.length) {
    const clients = await runQuery<{ client_id: string }>(runtime.database, `
      select client_id from app.lesson_snapshots
      where lesson_id = $1 and client_type in ('student', 'lead')
      union
      select participant.student_id as client_id
      from app.lesson_snapshot_participants participant
      where participant.lesson_id = $1 and not exists (
        select 1 from app.lesson_participant_exclusions exclusion
        where exclusion.lesson_id = participant.lesson_id
          and exclusion.student_id = participant.student_id
      )
    `, [current.entityId]);
    decision = withLegacyClientDecisions(
      decision, clients.rows.map((row) => row.client_id),
    );
  }
  const reasonText = "Автоматическое восстановление политики расчёта";
  const preview = await runtime.lessonCommands.previewSettlementPlan(
    runtime.actor,
    current.entityId,
    {
      expectedVersion: current.expectedVersion,
      financialDecision: decision,
      reasonText,
    },
  );
  await runtime.lessonCommands.updateSettlementPlan(
    runtime.actor,
    current.entityId,
    {
      expectedVersion: current.expectedVersion,
      financialDecision: decision,
      reasonText,
      previewToken: preview.previewToken,
      confirm: true,
    },
    { idempotencyKey, requestId: requestId(idempotencyKey) },
  );
}

interface SchedulePlanRepairRow extends QueryResultRow {
  plan_id: string;
  plan_version: number | string;
  title: string;
  active_from: string;
  active_until: string | null;
  subscription_id: string | null;
  student_id: string | null;
  kind: "individual" | "group";
  series_id: string;
  teacher_id: string;
  room_id: string;
  branch_id: string;
  weekday: number;
  begin_time: string;
  duration_minutes: number;
  notes: string | null;
  decision: LessonFinancialDecision;
  local_today: string;
}

export function verifyScheduleGroupSnapshot(
  items: SettlementPolicyScheduleGroupItem[],
  snapshot: {
    planId: string;
    planVersion: number;
    rows: Array<{ seriesId: string; decision: LessonFinancialDecision }>;
  },
): void {
  const live = new Map(snapshot.rows.map((row) => [row.seriesId, row]));
  const valid = items.length > 0 && items.every(({ current, candidate }) => {
    const row = live.get(candidate.entityId);
    return current.aggregateId === snapshot.planId &&
      candidate.expectedVersion === snapshot.planVersion &&
      row !== undefined &&
      settlementDecisionHash(row.decision) === candidate.currentDecisionHash;
  });
  if (!valid) throw new Error("RECONCILIATION_STALE_CANDIDATE");
}

async function repairScheduleSeriesGroup(
  runtime: ReconciliationRuntime,
  items: SettlementPolicyScheduleGroupItem[],
): Promise<void> {
  const planId = items[0]?.current.aggregateId;
  if (!planId || items.some((item) => item.current.aggregateId !== planId)) {
    throw new Error("RECONCILIATION_STALE_CANDIDATE");
  }
  const rows = await runQuery<SchedulePlanRepairRow>(runtime.database, `
    select plan.id as plan_id, plan.version as plan_version, plan.title,
      plan.active_from::text, plan.active_until::text, plan.subscription_id,
      plan.student_id,
      plan.kind, series.id as series_id, series.teacher_id, series.room_id,
      series.branch_id, series.weekday,
      to_char(series.begin_time, 'HH24:MI') as begin_time,
      series.duration_minutes, series.notes,
      series.planned_financial_decision as decision,
      greatest(plan.active_from,
        max(timezone(coalesce(branch.timezone_name, series.timezone_name,
          'Europe/Moscow'), now())::date) over ())::text as local_today
    from app.schedule_plans plan
    join app.schedule_series series on series.plan_id = plan.id
      and series.deleted_at is null and series.superseded_by is null
    left join app.branches branch on branch.id = series.branch_id
    where plan.id = $1 and plan.status = 'active'
    order by series.id
  `, [planId]);
  if (rows.rows.length === 0) throw new Error("RECONCILIATION_STALE_CANDIDATE");
  const plan = rows.rows[0]!;
  verifyScheduleGroupSnapshot(items, {
    planId: plan.plan_id,
    planVersion: Number(plan.plan_version),
    rows: rows.rows.map((row) => ({
      seriesId: row.series_id,
      decision: row.decision,
    })),
  });
  const proposed = new Map(items.map((item) => [
    item.candidate.entityId,
    mergeAutomaticTeacherDecision(
      rows.rows.find((row) => row.series_id === item.candidate.entityId)!
        .decision,
      item.command.proposedDecision,
    ),
  ]));
  const participants = plan.kind === "group"
    ? await activePlanParticipants(runtime.database, plan.plan_id,
        plan.local_today)
    : undefined;
  for (const [seriesId, decision] of proposed) {
    proposed.set(seriesId, withLegacyClientDecisions(
      decision,
      participants?.map((participant) => participant.studentId) ??
        (plan.student_id ? [plan.student_id] : []),
    ));
  }
  const idempotencyKey = scheduleGroupIdempotencyKey(planId, items);
  try {
    await runtime.scheduleCommands.update(
      runtime.actor,
      plan.plan_id,
      {
        expectedVersion: items[0]!.candidate.expectedVersion,
        effectiveFrom: plan.local_today,
        title: plan.title,
        activeUntil: plan.active_until,
        ...(plan.subscription_id ? { subscriptionId: plan.subscription_id } : {}),
        ...(participants ? { participants } : {}),
        rows: rows.rows.map((row) => ({
          seriesId: row.series_id,
          teacherId: row.teacher_id,
          roomId: row.room_id,
          branchId: row.branch_id,
          weekday: row.weekday,
          beginTime: row.begin_time,
          durationMinutes: row.duration_minutes,
          ...(row.notes ? { notes: row.notes } : {}),
          financialDecision: proposed.get(row.series_id) ?? row.decision,
          ...(proposed.has(row.series_id)
            ? { plannedSettlementReason:
                "Автоматическое восстановление политики расчёта" }
            : {}),
        })),
      },
      { idempotencyKey, requestId: requestId(idempotencyKey) },
    );
  } catch (error) {
    if (scheduleCommandWasStale(error)) {
      throw new Error("RECONCILIATION_STALE_CANDIDATE");
    }
    throw error;
  }
}

export function withLegacyClientDecisions(
  decision: LessonFinancialDecision,
  clientIds: string[],
): LessonFinancialDecision {
  if (decision.clientDecisions?.length) return decision;
  return {
    ...decision,
    clientDecisions: [...new Set(clientIds)].sort().map((clientId) => ({
      clientId,
    })),
  };
}

function scheduleGroupIdempotencyKey(
  planId: string,
  items: SettlementPolicyScheduleGroupItem[],
): string {
  return `v8:settlement-policy:schedule_series:${planId}:${fingerprintPayload(
    items.map(({ candidate }) => ({
      entityId: candidate.entityId,
      decisionHash: candidate.currentDecisionHash,
    })).sort((left, right) => left.entityId.localeCompare(right.entityId)),
  )}`;
}

function scheduleCommandWasStale(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const response = "getResponse" in error &&
      typeof error.getResponse === "function"
    ? error.getResponse()
    : error;
  const code = response && typeof response === "object" && "code" in response
    ? response.code
    : undefined;
  return code === "STALE_VERSION" ||
    code === "STALE_AGGREGATE_VERSION" ||
    code === "LESSON_VERSION_DIVERGED";
}

async function activePlanParticipants(
  queryable: Queryable,
  planId: string,
  effectiveFrom: string,
): Promise<Array<{ studentId: string; subscriptionId: string }>> {
  const result = await runQuery<{
    student_id: string;
    subscription_id: string;
  }>(queryable, `
    select distinct on (student_id) student_id, subscription_id
    from app.schedule_plan_participants
    where plan_id = $1 and effective_from <= $2::date
      and (effective_until is null or effective_until >= $2::date)
    order by student_id, effective_from desc, id desc
  `, [planId, effectiveFrom]);
  return result.rows.map((row) => ({
    studentId: row.student_id,
    subscriptionId: row.subscription_id,
  }));
}

function requestId(idempotencyKey: string): string {
  return `v8-reconcile:${fingerprintPayload(idempotencyKey).slice(0, 32)}`;
}

function assertApplyInvariants(
  before: ReconciliationInvariantSnapshot,
  after: ReconciliationInvariantSnapshot,
): void {
  if (before.futureLessonCount !== after.futureLessonCount ||
      before.activeReservationUnits !== after.activeReservationUnits ||
      before.effectiveTeacherFactCount !== after.effectiveTeacherFactCount) {
    throw new Error("RECONCILIATION_INVARIANT_CHANGED");
  }
}

function runQuery<T extends QueryResultRow>(
  queryable: Queryable,
  text: string,
  params: unknown[] = [],
): Promise<QueryResult<T>> {
  return (queryable.query as (
    query: string,
    values?: unknown[],
  ) => Promise<QueryResult<T>>)(text, params);
}

async function loadActor(
  database: DatabaseService,
  actorUserId: string,
): Promise<ActorContext> {
  const result = await database.query<{
    id: string;
    role: UserRole;
  }>(
    `select id, role::text as role from app.users
     where id = $1 and deleted_at is null and is_app_account = true`,
    [actorUserId],
  );
  const actor = result.rows[0];
  if (!actor || !["director", "system_admin"].includes(actor.role)) {
    throw new Error("MIGRATION_ACTOR_NOT_AUTHORIZED");
  }
  return { userId: actor.id, role: actor.role };
}

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  const value = index >= 0 ? process.argv[index + 1] : undefined;
  return value && !value.startsWith("--") ? value : undefined;
}

async function writeReport(
  outputPath: string,
  report: SettlementPolicyReconciliationReport,
): Promise<void> {
  const absolute = resolve(outputPath);
  await mkdir(dirname(absolute), { recursive: true });
  await writeFile(absolute, `${JSON.stringify(report, null, 2)}\n`, {
    encoding: "utf8",
    flag: "wx",
  });
}

async function main(): Promise<void> {
  const output = argument("--output");
  if (!output) throw new Error("--output is required");
  const connectionString =
    process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required");
  }
  if (!process.argv.includes("--apply")) {
    const pool = new Pool({ connectionString, max: 1 });
    try {
      const report = await runDryRun(pool);
      await writeReport(output, report);
      process.stdout.write(`${JSON.stringify({
        output: resolve(output),
        counts: report.counts,
      })}\n`);
      if (report.counts.ambiguous > 0 || report.counts.invalid > 0) {
        process.exitCode = 2;
      }
    } finally {
      await pool.end();
    }
    return;
  }

  const input = argument("--input");
  if (!input) throw new Error("--input is required for apply");
  const dryRun = JSON.parse(
    await readFile(resolve(input), "utf8"),
  ) as SettlementPolicyReconciliationReport;
  process.env.DATABASE_URL ??= connectionString;
  const [{ NestFactory }, { AppModule }, { DatabaseService: Database },
    { LessonPlannedSettlementCommandService: LessonCommands },
    { SchedulePlanMutationService: ScheduleCommands }] = await Promise.all([
    import("@nestjs/core"),
    import("../../../app.module"),
    import("../../../db/database.service"),
    import("../../../crm/schedule/lesson-planned-settlement-command.service"),
    import("../../../crm/schedule/schedule-plan-mutation.service"),
  ]);
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: false,
  });
  try {
    const database = app.get(Database, { strict: false });
    const actorUserId = argument("--actor-user-id") ??
      process.env.MIGRATION_ACTOR_USER_ID;
    if (!actorUserId) throw new Error("MIGRATION_ACTOR_USER_ID is required");
    const actor = await loadActor(database, actorUserId);
    const applied = await runApply({
      database,
      actor,
      lessonCommands: app.get(LessonCommands, { strict: false }),
      scheduleCommands: app.get(ScheduleCommands, { strict: false }),
    }, dryRun);
    await writeReport(output, applied.report);
    process.stdout.write(`${JSON.stringify({
      output: resolve(output),
      mutationsApplied: applied.mutations,
      issues: applied.report.issues.length,
    })}\n`);
    if (applied.report.issues.length > 0) process.exitCode = 2;
  } finally {
    await app.close();
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exitCode = message === "RECONCILIATION_REPORT_BLOCKED" ? 2 : 1;
  });
}
