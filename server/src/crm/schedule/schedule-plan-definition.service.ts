import {
  ConflictException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { assertSchedulePlanDraftScope } from "./schedule-plan-access";
import { assertActiveClientReferences } from "../clients/client-reference.service";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import type {
  CreateSchedulePlanDto,
  SchedulePlanEndPreviewDto,
  SchedulePlanParticipantDto,
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import {
  type LockedSchedulePlan,
  SchedulePlanRepository,
} from "./schedule-plan.repository";
import {
  assertUniqueSchedulePlanParticipants,
  initialSchedulePlanUpdateMode,
  prepareSchedulePlanUpdateMode,
  previousScheduleDate,
  type SchedulePlanUpdateMode,
} from "./schedule-plan-backdate";
import type {
  NormalizedSchedulePlanCreate,
  NormalizedSchedulePlanEnd,
  PreparedSchedulePlanUpdate,
  SchedulePlanValidationInput,
} from "./schedule-plan-definition.types";

export type {
  NormalizedSchedulePlanCreate,
  NormalizedSchedulePlanEnd,
  PreparedSchedulePlanUpdate,
  SchedulePlanValidationInput,
} from "./schedule-plan-definition.types";

export const failSchedulePlan = (code: string, fields: string[]): never => {
  throw new UnprocessableEntityException({ code, fields });
};

export const assertSchedulePlanMetadata = (metadata: LessonCommandMetadata) => {
  if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
    failSchedulePlan("IDEMPOTENCY_KEY_REQUIRED", ["Idempotency-Key"]);
  }
  if (!metadata.requestId || metadata.requestId.length > 160) {
    failSchedulePlan("REQUEST_ID_REQUIRED", ["X-Request-Id"]);
  }
};

export const schedulePlanStableId = (seed: string) => {
  const bytes = createHash("sha256").update(seed).digest().subarray(0, 16);
  bytes[6] = (bytes[6]! & 0x0f) | 0x50;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};

@Injectable()
export class SchedulePlanDefinitionService {
  constructor(private readonly repository: SchedulePlanRepository) {}

  normalizeCreate(dto: CreateSchedulePlanDto): NormalizedSchedulePlanCreate {
    const title = dto.title.trim();
    if (!title) failSchedulePlan("SCHEDULE_PLAN_TITLE_REQUIRED", ["title"]);
    const subject = this.createSubject(dto);
    assertUniqueSchedulePlanParticipants(subject.participants);
    this.assertRows(dto.rows);
    if (dto.rows.some((row) => row.seriesId)) {
      failSchedulePlan("SCHEDULE_PLAN_NEW_ROW_HAS_SERIES", ["rows"]);
    }
    const activeFrom = dto.activeFrom.slice(0, 10);
    const activeUntil = dto.activeUntil?.slice(0, 10) ?? null;
    this.assertPeriod(activeFrom, activeUntil);
    return {
      kind: dto.kind,
      title,
      ...subject,
      activeFrom,
      activeUntil,
      rows: dto.rows,
    };
  }

  assertRows(rows: SchedulePlanRowDto[]): void {
    const ids = rows.map((row) => row.seriesId).filter(Boolean);
    if (new Set(ids).size !== ids.length) {
      failSchedulePlan("SCHEDULE_PLAN_DUPLICATE_SERIES", ["rows"]);
    }
    const keys = rows.map((row) => this.rowIdentity(row));
    if (new Set(keys).size !== keys.length) {
      failSchedulePlan("SCHEDULE_PLAN_DUPLICATE_ROW", ["rows"]);
    }
  }

  async prepareUpdate(
    client: PoolClient,
    planId: string,
    dto: UpdateSchedulePlanDto,
    actor: ActorContext,
  ): Promise<PreparedSchedulePlanUpdate> {
    const plan = await this.repository.lock(client, planId, actor);
    const effectiveFrom = dto.effectiveFrom.slice(0, 10);
    let mode = initialSchedulePlanUpdateMode(plan, effectiveFrom);
    const participantsAtOldStart =
      plan.kind === "group"
        ? await this.currentParticipants(client, planId, plan.active_from)
        : [];
    const participants = await this.updateParticipants(
      client,
      plan,
      planId,
      effectiveFrom,
      mode,
      participantsAtOldStart,
      dto,
    );
    const subscriptionId =
      plan.kind === "individual"
        ? (dto.subscriptionId ?? plan.subscription_id)
        : null;
    const activeUntil = Object.prototype.hasOwnProperty.call(dto, "activeUntil")
      ? (dto.activeUntil?.slice(0, 10) ?? null)
      : plan.active_until;
    const studentIds =
      plan.kind === "individual"
        ? [plan.student_id!]
        : participants.map((participant) => participant.studentId);
    const validation = {
      planId,
      kind: plan.kind,
      studentId: plan.student_id,
      groupId: plan.group_id,
      subscriptionId,
      participants,
      rows: dto.rows,
    };
    await assertSchedulePlanDraftScope(client, actor, validation);
    const locked = await this.lockValidationBarriers(client, validation);
    this.assertEditable(plan, dto);
    this.assertPeriod(effectiveFrom, activeUntil);
    await this.assertLockedSemantics(client, validation, locked);
    const activeSeries = (await this.repository.activeSeries(client, planId))
      .rows;
    mode = await prepareSchedulePlanUpdateMode({
      client,
      repository: this.repository,
      planId,
      plan,
      dto,
      effectiveFrom,
      subscriptionId,
      activeUntil,
      participants,
      participantsAtOldStart,
      activeSeries,
    });
    return {
      plan,
      mode,
      participants,
      subscriptionId,
      activeUntil,
      studentIds,
      activeSeries,
      effectiveFrom,
      prefixUntil:
        mode === "extend_backwards"
          ? previousScheduleDate(plan.active_from)
          : null,
    };
  }

  async lockAndValidate(
    client: PoolClient,
    input: SchedulePlanValidationInput,
    actor: ActorContext,
  ): Promise<void> {
    await assertSchedulePlanDraftScope(client, actor, input);
    const locked = await this.lockValidationBarriers(client, input);
    await this.assertLockedSemantics(client, input, locked);
  }

  private async lockValidationBarriers(
    client: PoolClient,
    input: SchedulePlanValidationInput,
  ) {
    const subscriptionIds = this.subscriptionIds(input);
    const studentIds = this.studentIds(input);
    await this.lockResources(client, input, subscriptionIds, studentIds);
    await assertActiveClientReferences(
      client,
      studentIds.map((id) => ({ type: "student", id })),
    );
    return { subscriptionIds, studentIds };
  }

  private async assertLockedSemantics(
    client: PoolClient,
    input: SchedulePlanValidationInput,
    locked: { subscriptionIds: string[]; studentIds: string[] },
  ) {
    const { subscriptionIds, studentIds } = locked;
    await this.assertSubscriptionAssignments(client, input, subscriptionIds);
    await this.assertResources(client, input.rows, studentIds);
    if (input.kind === "group") {
      await this.assertGroupParticipants(client, input.groupId, studentIds);
    }
  }

  normalizeEnd(dto: SchedulePlanEndPreviewDto): NormalizedSchedulePlanEnd {
    const reasonText = dto.reasonText.trim();
    if (!reasonText || reasonText.length > 500 || reasonText.includes("\0")) {
      failSchedulePlan("SCHEDULE_PLAN_END_REASON_REQUIRED", ["reasonText"]);
    }
    return {
      expectedVersion: dto.expectedVersion,
      lastDate: dto.lastDate.slice(0, 10),
      reasonText,
    };
  }

  async assertEndable(
    client: PoolClient,
    plan: LockedSchedulePlan,
    input: NormalizedSchedulePlanEnd,
  ): Promise<void> {
    if (plan.status !== "active") {
      throw new ConflictException({ code: "SCHEDULE_PLAN_ENDED" });
    }
    if (Number(plan.version) !== input.expectedVersion) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_VERSION_STALE" });
    }
    const today = await this.repository.localToday(client, plan.id);
    if (input.lastDate < plan.active_from || input.lastDate < today) {
      failSchedulePlan("SCHEDULE_PLAN_END_DATE_INVALID", ["lastDate"]);
    }
  }

  planId(actorUserId: string, idempotencyKey: string): string {
    return schedulePlanStableId(
      `schedule.plan.create\0${actorUserId}\0${idempotencyKey}`,
    );
  }

  seriesId(planId: string, version: number, index: number): string {
    return schedulePlanStableId(
      `schedule.plan.series\0${planId}\0${version}\0${index}`,
    );
  }

  async lessonIds(client: PoolClient, seriesId: string): Promise<string[]> {
    const result = await client.query<{ id: string }>(
      "select id from app.lessons where series_id = $1 order by series_date, id",
      [seriesId],
    );
    return result.rows.map((row) => row.id);
  }

  private createSubject(dto: CreateSchedulePlanDto) {
    const studentId =
      dto.kind === "individual" ? (dto.studentId ?? null) : null;
    const groupId = dto.kind === "group" ? (dto.groupId ?? null) : null;
    const subscriptionId =
      dto.kind === "individual" ? (dto.subscriptionId ?? null) : null;
    const participants = dto.kind === "group" ? (dto.participants ?? []) : [];
    this.assertSubjectRequired(
      dto.kind,
      studentId,
      groupId,
      subscriptionId,
      participants,
    );
    this.assertSubjectUnambiguous(dto);
    return { studentId, groupId, subscriptionId, participants };
  }

  private assertSubjectRequired(
    kind: "individual" | "group",
    studentId: string | null,
    groupId: string | null,
    subscriptionId: string | null,
    participants: SchedulePlanParticipantDto[],
  ) {
    if (kind === "individual" && (!studentId || !subscriptionId)) {
      failSchedulePlan("SCHEDULE_PLAN_INDIVIDUAL_SUBJECT_REQUIRED", [
        "studentId",
        "subscriptionId",
      ]);
    }
    if (kind === "group" && (!groupId || participants.length === 0)) {
      failSchedulePlan("SCHEDULE_PLAN_GROUP_SUBJECT_REQUIRED", [
        "groupId",
        "participants",
      ]);
    }
  }

  private assertSubjectUnambiguous(dto: CreateSchedulePlanDto) {
    const individualHasGroup =
      dto.kind === "individual" &&
      Boolean(dto.groupId || (dto.participants?.length ?? 0) > 0);
    const groupHasIndividual =
      dto.kind === "group" && Boolean(dto.studentId || dto.subscriptionId);
    if (individualHasGroup || groupHasIndividual) {
      failSchedulePlan("SCHEDULE_PLAN_SUBJECT_AMBIGUOUS", ["kind"]);
    }
  }

  private assertEditable(plan: LockedSchedulePlan, dto: UpdateSchedulePlanDto) {
    this.assertPlanState(plan, dto.expectedVersion);
    this.assertUpdateFields(plan, dto);
    assertUniqueSchedulePlanParticipants(dto.participants ?? []);
  }

  private assertPlanState(plan: LockedSchedulePlan, expectedVersion: number) {
    if (plan.status !== "active")
      throw new ConflictException({ code: "SCHEDULE_PLAN_ENDED" });
    if (Number(plan.version) !== expectedVersion) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_VERSION_STALE" });
    }
  }

  private assertUpdateFields(
    plan: LockedSchedulePlan,
    dto: UpdateSchedulePlanDto,
  ) {
    if (dto.title !== undefined && !dto.title.trim()) {
      failSchedulePlan("SCHEDULE_PLAN_TITLE_REQUIRED", ["title"]);
    }
    if (plan.kind === "individual" && (dto.participants?.length ?? 0) > 0) {
      failSchedulePlan("SCHEDULE_PLAN_PARTICIPANTS_FORBIDDEN", [
        "participants",
      ]);
    }
    if (plan.kind === "group" && dto.subscriptionId) {
      failSchedulePlan("SCHEDULE_PLAN_SUBSCRIPTION_FORBIDDEN", [
        "subscriptionId",
      ]);
    }
  }

  private async updateParticipants(
    client: PoolClient,
    plan: LockedSchedulePlan,
    planId: string,
    effectiveFrom: string,
    mode: SchedulePlanUpdateMode,
    participantsAtOldStart: SchedulePlanParticipantDto[],
    dto: UpdateSchedulePlanDto,
  ) {
    if (plan.kind !== "group") return [];
    if (mode === "extend_backwards") {
      return dto.participants ?? participantsAtOldStart;
    }
    return (
      dto.participants ??
      this.currentParticipants(client, planId, effectiveFrom)
    );
  }

  private async currentParticipants(
    client: PoolClient,
    planId: string,
    effectiveFrom: string,
  ) {
    const result = await client.query<{
      student_id: string;
      subscription_id: string;
    }>(
      `select student_id, subscription_id
       from app.schedule_plan_participants
       where plan_id = $1 and effective_from <= $2::date
         and (effective_until is null or effective_until >= $2::date)
       order by student_id for update`,
      [planId, effectiveFrom],
    );
    return result.rows.map((row) => ({
      studentId: row.student_id,
      subscriptionId: row.subscription_id,
    }));
  }

  private subscriptionIds(input: SchedulePlanValidationInput) {
    return input.kind === "individual"
      ? [input.subscriptionId!]
      : input.participants.map((participant) => participant.subscriptionId);
  }

  private studentIds(input: SchedulePlanValidationInput) {
    return input.kind === "individual"
      ? [input.studentId!]
      : input.participants.map((participant) => participant.studentId);
  }

  private async lockResources(
    client: PoolClient,
    input: SchedulePlanValidationInput,
    subscriptionIds: string[],
    studentIds: string[],
  ) {
    const locks = [
      `plan:${input.planId}`,
      ...(input.groupId ? [`group:${input.groupId}`] : []),
      ...studentIds.map((id) => `client:student:${id}`),
      ...subscriptionIds.map((id) => `subscription:${id}`),
      ...input.rows.flatMap((row) => [
        `branch:${row.branchId}`,
        `room:${row.roomId}`,
        `teacher:${row.teacherId}`,
      ]),
    ];
    for (const key of [...new Set(locks)].sort()) {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [key],
      );
    }
  }

  private async assertSubscriptionAssignments(
    client: PoolClient,
    input: SchedulePlanValidationInput,
    subscriptionIds: string[],
  ) {
    const subscriptions = await client.query<{
      id: string;
      student_id: string;
      status: string;
    }>(
      `select id, student_id, status from app.subscriptions
       where id = any($1::uuid[]) order by id for update`,
      [subscriptionIds],
    );
    const owners = new Map(subscriptions.rows.map((row) => [row.id, row]));
    const assignments =
      input.kind === "individual"
        ? [
            {
              studentId: input.studentId!,
              subscriptionId: input.subscriptionId!,
            },
          ]
        : input.participants;
    const invalid = assignments.some((assignment) => {
      const subscription = owners.get(assignment.subscriptionId);
      return (
        !subscription ||
        subscription.status !== "active" ||
        subscription.student_id !== assignment.studentId
      );
    });
    if (invalid) {
      failSchedulePlan("SCHEDULE_PLAN_SUBSCRIPTION_INVALID", [
        "subscriptionId",
        "participants",
      ]);
    }
  }

  private async assertResources(
    client: PoolClient,
    rows: SchedulePlanRowDto[],
    studentIds: string[],
  ) {
    const resources = await client.query<{ valid: boolean }>(
      `select
        (select count(*) from app.students where id = any($4::uuid[]) and deleted_at is null)
          = cardinality($4::uuid[])
        and
        (select count(*) from app.branches where id = any($1::uuid[]) and deleted_at is null)
          = cardinality($1::uuid[])
        and (select count(*) from app.rooms where id = any($2::uuid[]) and deleted_at is null)
          = cardinality($2::uuid[])
        and (select count(*) from app.teachers where id = any($3::uuid[]) and deleted_at is null)
          = cardinality($3::uuid[]) as valid`,
      [
        [...new Set(rows.map((row) => row.branchId))],
        [...new Set(rows.map((row) => row.roomId))],
        [...new Set(rows.map((row) => row.teacherId))],
        [...new Set(studentIds)],
      ],
    );
    if (!resources.rows[0]?.valid)
      failSchedulePlan("SCHEDULE_PLAN_RESOURCE_INVALID", ["rows"]);
  }

  private async assertGroupParticipants(
    client: PoolClient,
    groupId: string | null,
    studentIds: string[],
  ) {
    const group = await client.query<{ member_count: string }>(
      `select count(distinct membership.student_id)::text as member_count
       from app.groups target
       left join app.group_students membership
         on membership.group_id = target.id and membership.left_at is null
         and membership.student_id = any($2::uuid[])
       where target.id = $1 and target.deleted_at is null`,
      [groupId, studentIds],
    );
    if (Number(group.rows[0]?.member_count ?? -1) !== studentIds.length) {
      failSchedulePlan("SCHEDULE_PLAN_GROUP_PARTICIPANT_INVALID", [
        "groupId",
        "participants",
      ]);
    }
  }

  private assertPeriod(from: string, until: string | null) {
    if (until !== null && until < from) {
      failSchedulePlan("SCHEDULE_PLAN_PERIOD_INVALID", ["activeUntil"]);
    }
  }

  private rowIdentity(row: SchedulePlanRowDto) {
    return [
      row.teacherId,
      row.roomId,
      row.branchId,
      row.weekday,
      row.beginTime,
      row.durationMinutes ?? 60,
    ].join(":");
  }
}
