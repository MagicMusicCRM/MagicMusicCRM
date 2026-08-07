import {
  ConflictException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import {
  CreateSchedulePlanDto,
  SchedulePlanParticipantDto,
  SchedulePlanQuery,
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import { ScheduleService } from "../schedule.service";
import type { LessonCommandMetadata } from "./lesson-command.service";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import {
  LockedSchedulePlan,
  SchedulePlanRepository,
} from "./schedule-plan.repository";

@Injectable()
export class SchedulePlanService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly repository: SchedulePlanRepository,
    private readonly series: LessonSeriesCommandService,
    private readonly schedule: ScheduleService,
  ) {}

  list(actor: ActorContext, query: SchedulePlanQuery) {
    return this.repository.list(actor, query);
  }

  async create(
    actor: ActorContext,
    dto: CreateSchedulePlanDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const normalized = this.normalizeCreate(dto);
    const planId = this.stableId(
      `schedule.plan.create\0${actor.userId}\0${metadata.idempotencyKey}`,
    );
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "schedule.lesson.write" },
      operation: "schedule.plan.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: normalized,
      aggregateType: "schedule:plan",
      aggregateId: planId,
      expectedVersion: 0,
      requestId: metadata.requestId,
      audit: {
        action: "crm.schedule_plan_created",
        entityType: "schedule_plan",
        entityId: planId,
      },
      outbox: {
        type: "schedule.plan.changed",
        payload: { entityId: planId, state: "created" },
      },
      mutate: async (client, version) => {
        const participants = normalized.participants;
        const studentIds = normalized.kind === "individual"
          ? [normalized.studentId!]
          : participants.map((participant) => participant.studentId);
        await this.lockAndValidate(
          client,
          planId,
          normalized.kind,
          normalized.studentId,
          normalized.groupId,
          normalized.subscriptionId,
          participants,
          normalized.rows,
        );
        await this.repository.insertPlan(client, {
          id: planId,
          kind: normalized.kind,
          title: normalized.title,
          studentId: normalized.studentId,
          groupId: normalized.groupId,
          subscriptionId: normalized.subscriptionId,
          activeFrom: normalized.activeFrom,
          activeUntil: normalized.activeUntil,
          actorUserId: actor.userId,
          version,
        });
        if (normalized.kind === "group") {
          await this.repository.insertParticipants(
            client,
            planId,
            participants,
            normalized.activeFrom,
            normalized.activeUntil,
            version,
          );
        }
        const seriesIds: string[] = [];
        const lessonIds: string[] = [];
        for (const [index, row] of normalized.rows.entries()) {
          await this.series.validatePlanRow(
            client,
            row,
            normalized.activeFrom,
            normalized.activeUntil,
            studentIds,
          );
          const seriesId = this.seriesId(planId, version, index);
          await this.repository.insertSeries(client, {
            id: seriesId,
            planId,
            studentId: normalized.studentId,
            groupId: normalized.groupId,
            validFrom: normalized.activeFrom,
            validUntil: normalized.activeUntil,
            row,
            actorUserId: actor.userId,
            version,
          });
          await this.schedule.materializePlanSeries(client, seriesId);
          seriesIds.push(seriesId);
          lessonIds.push(...await this.lessonIds(client, seriesId));
        }
        return { planId, seriesIds, lessonIds };
      },
    });
    return {
      id: planId,
      seriesIds: mutation.resultRef.seriesIds as string[],
      lessonIds: mutation.resultRef.lessonIds as string[],
      version: mutation.version,
      replayed: mutation.replayed,
    };
  }

  async update(
    actor: ActorContext,
    planId: string,
    dto: UpdateSchedulePlanDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    this.assertRows(dto.rows);
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "schedule.lesson.write" },
      operation: "schedule.plan.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: dto,
      aggregateType: "schedule:plan",
      aggregateId: planId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.schedule_plan_updated",
        entityType: "schedule_plan",
        entityId: planId,
      },
      outbox: {
        type: "schedule.plan.changed",
        payload: { entityId: planId, state: "updated" },
      },
      mutate: async (client, version) => {
        const plan = await this.repository.lock(client, planId);
        this.assertEditable(plan, dto);
        const participants = plan.kind === "group"
          ? (dto.participants ?? await this.currentParticipants(
              client,
              planId,
              dto.effectiveFrom.slice(0, 10),
            ))
          : [];
        const subscriptionId = plan.kind === "individual"
          ? (dto.subscriptionId ?? plan.subscription_id)
          : null;
        const activeUntil = Object.prototype.hasOwnProperty.call(dto, "activeUntil")
          ? (dto.activeUntil?.slice(0, 10) ?? null)
          : plan.active_until;
        this.assertPeriod(dto.effectiveFrom, activeUntil);
        const effectiveDate = await client.query<{ valid: boolean }>(
          `select not exists (
             select 1 from app.branches branch
             where branch.id = any($2::uuid[])
               and $1::date < timezone(branch.timezone_name, now())::date
           ) as valid`,
          [dto.effectiveFrom.slice(0, 10), [...new Set(dto.rows.map((row) => row.branchId))]],
        );
        if (!effectiveDate.rows[0]?.valid) {
          this.fail("SCHEDULE_PLAN_EFFECTIVE_DATE_PAST", ["effectiveFrom"]);
        }
        const studentIds = plan.kind === "individual"
          ? [plan.student_id!]
          : participants.map((participant) => participant.studentId);
        await this.lockAndValidate(
          client,
          planId,
          plan.kind,
          plan.student_id,
          plan.group_id,
          subscriptionId,
          participants,
          dto.rows,
        );

        const activeSeries = (await this.repository.activeSeries(client, planId)).rows;
        const activeIds = new Set(activeSeries.map((row) => row.id));
        const requestedIds = dto.rows
          .map((row) => row.seriesId)
          .filter((id): id is string => Boolean(id));
        if (requestedIds.some((id) => !activeIds.has(id))) {
          throw new ConflictException({
            code: "SCHEDULE_PLAN_SERIES_STALE",
            message: "One of the edited rows is no longer active.",
          });
        }

        const continuations = new Map<string, string>();
        const seriesIds: string[] = [];
        for (const [index, row] of dto.rows.entries()) {
          const seriesId = this.seriesId(planId, version, index);
          await this.repository.insertSeries(client, {
            id: seriesId,
            planId,
            studentId: plan.student_id,
            groupId: plan.group_id,
            validFrom: dto.effectiveFrom.slice(0, 10),
            validUntil: activeUntil,
            row,
            actorUserId: actor.userId,
            version,
          });
          if (row.seriesId) continuations.set(row.seriesId, seriesId);
          seriesIds.push(seriesId);
        }
        for (const old of activeSeries) {
          await this.repository.retireSeries(
            client,
            old.id,
            dto.effectiveFrom.slice(0, 10),
            continuations.get(old.id) ?? null,
          );
        }
        if (plan.kind === "group") {
          await this.repository.replaceParticipants(
            client,
            planId,
            participants,
            dto.effectiveFrom.slice(0, 10),
            activeUntil,
            version,
          );
        }
        await this.repository.updatePlan(client, {
          planId,
          title: dto.title?.trim() || plan.title,
          subscriptionId,
          activeUntil,
          version,
        });
        const lessonIds: string[] = [];
        for (const [index, row] of dto.rows.entries()) {
          await this.series.validatePlanRow(
            client,
            row,
            dto.effectiveFrom.slice(0, 10),
            activeUntil,
            studentIds,
          );
          const seriesId = seriesIds[index]!;
          await this.schedule.materializePlanSeries(client, seriesId);
          lessonIds.push(...await this.lessonIds(client, seriesId));
        }
        return { planId, seriesIds, lessonIds };
      },
    });
    return {
      id: planId,
      seriesIds: mutation.resultRef.seriesIds as string[],
      lessonIds: mutation.resultRef.lessonIds as string[],
      version: mutation.version,
      replayed: mutation.replayed,
    };
  }

  private normalizeCreate(dto: CreateSchedulePlanDto) {
    const title = dto.title.trim();
    if (!title) this.fail("SCHEDULE_PLAN_TITLE_REQUIRED", ["title"]);
    const studentId = dto.kind === "individual" ? dto.studentId ?? null : null;
    const groupId = dto.kind === "group" ? dto.groupId ?? null : null;
    const subscriptionId = dto.kind === "individual"
      ? dto.subscriptionId ?? null
      : null;
    const participants = dto.kind === "group" ? dto.participants ?? [] : [];
    if (dto.kind === "individual" && (!studentId || !subscriptionId)) {
      this.fail("SCHEDULE_PLAN_INDIVIDUAL_SUBJECT_REQUIRED", ["studentId", "subscriptionId"]);
    }
    if (dto.kind === "group" && (!groupId || participants.length === 0)) {
      this.fail("SCHEDULE_PLAN_GROUP_SUBJECT_REQUIRED", ["groupId", "participants"]);
    }
    if (
      (dto.kind === "individual" && (dto.groupId || (dto.participants?.length ?? 0) > 0)) ||
      (dto.kind === "group" && (dto.studentId || dto.subscriptionId))
    ) {
      this.fail("SCHEDULE_PLAN_SUBJECT_AMBIGUOUS", ["kind"]);
    }
    this.assertParticipants(participants);
    this.assertRows(dto.rows);
    if (dto.rows.some((row) => row.seriesId)) {
      this.fail("SCHEDULE_PLAN_NEW_ROW_HAS_SERIES", ["rows"]);
    }
    const activeFrom = dto.activeFrom.slice(0, 10);
    const activeUntil = dto.activeUntil?.slice(0, 10) ?? null;
    this.assertPeriod(activeFrom, activeUntil);
    return {
      kind: dto.kind,
      title,
      studentId,
      groupId,
      subscriptionId,
      activeFrom,
      activeUntil,
      participants,
      rows: dto.rows,
    };
  }

  private assertEditable(plan: LockedSchedulePlan, dto: UpdateSchedulePlanDto) {
    if (plan.status !== "active") {
      throw new ConflictException({ code: "SCHEDULE_PLAN_ENDED" });
    }
    if (Number(plan.version) !== dto.expectedVersion) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_VERSION_STALE" });
    }
    if (dto.title !== undefined && !dto.title.trim()) {
      this.fail("SCHEDULE_PLAN_TITLE_REQUIRED", ["title"]);
    }
    const effectiveFrom = dto.effectiveFrom.slice(0, 10);
    if (effectiveFrom < plan.active_from) {
      this.fail("SCHEDULE_PLAN_EFFECTIVE_DATE_INVALID", ["effectiveFrom"]);
    }
    if (plan.kind === "individual" && (dto.participants?.length ?? 0) > 0) {
      this.fail("SCHEDULE_PLAN_PARTICIPANTS_FORBIDDEN", ["participants"]);
    }
    if (plan.kind === "group" && dto.subscriptionId) {
      this.fail("SCHEDULE_PLAN_SUBSCRIPTION_FORBIDDEN", ["subscriptionId"]);
    }
    this.assertParticipants(dto.participants ?? []);
  }

  private assertRows(rows: SchedulePlanRowDto[]) {
    const ids = rows.map((row) => row.seriesId).filter(Boolean);
    if (new Set(ids).size !== ids.length) {
      this.fail("SCHEDULE_PLAN_DUPLICATE_SERIES", ["rows"]);
    }
    const keys = rows.map((row) => [
      row.teacherId,
      row.roomId,
      row.branchId,
      row.weekday,
      row.beginTime,
      row.durationMinutes ?? 60,
    ].join(":"));
    if (new Set(keys).size !== keys.length) {
      this.fail("SCHEDULE_PLAN_DUPLICATE_ROW", ["rows"]);
    }
  }

  private assertParticipants(participants: SchedulePlanParticipantDto[]) {
    if (new Set(participants.map((item) => item.studentId)).size !== participants.length) {
      this.fail("SCHEDULE_PLAN_DUPLICATE_PARTICIPANT", ["participants"]);
    }
  }

  private assertPeriod(from: string, until: string | null) {
    if (until !== null && until < from) {
      this.fail("SCHEDULE_PLAN_PERIOD_INVALID", ["activeUntil"]);
    }
  }

  private async lockAndValidate(
    client: PoolClient,
    planId: string,
    kind: "individual" | "group",
    studentId: string | null,
    groupId: string | null,
    subscriptionId: string | null,
    participants: SchedulePlanParticipantDto[],
    rows: SchedulePlanRowDto[],
  ) {
    const subscriptionIds = kind === "individual"
      ? [subscriptionId!]
      : participants.map((participant) => participant.subscriptionId);
    const studentIds = kind === "individual"
      ? [studentId!]
      : participants.map((participant) => participant.studentId);
    const locks = [
      `plan:${planId}`,
      ...(groupId ? [`group:${groupId}`] : []),
      ...studentIds.map((id) => `student:${id}`),
      ...subscriptionIds.map((id) => `subscription:${id}`),
      ...rows.flatMap((row) => [
        `branch:${row.branchId}`,
        `room:${row.roomId}`,
        `teacher:${row.teacherId}`,
      ]),
    ].sort();
    for (const key of new Set(locks)) {
      await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [key]);
    }
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
    const assignments = kind === "individual"
      ? [{ studentId: studentId!, subscriptionId: subscriptionId! }]
      : participants;
    if (assignments.some((assignment) => {
      const subscription = owners.get(assignment.subscriptionId);
      return !subscription || subscription.status !== "active"
        || subscription.student_id !== assignment.studentId;
    })) {
      this.fail("SCHEDULE_PLAN_SUBSCRIPTION_INVALID", ["subscriptionId", "participants"]);
    }
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
    if (!resources.rows[0]?.valid) {
      this.fail("SCHEDULE_PLAN_RESOURCE_INVALID", ["rows"]);
    }
    if (kind === "group") {
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
        this.fail("SCHEDULE_PLAN_GROUP_PARTICIPANT_INVALID", ["groupId", "participants"]);
      }
    }
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

  private async lessonIds(client: PoolClient, seriesId: string) {
    const result = await client.query<{ id: string }>(
      "select id from app.lessons where series_id = $1 order by series_date, id",
      [seriesId],
    );
    return result.rows.map((row) => row.id);
  }

  private assertMetadata(metadata: LessonCommandMetadata) {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      this.fail("IDEMPOTENCY_KEY_REQUIRED", ["Idempotency-Key"]);
    }
    if (!metadata.requestId || metadata.requestId.length > 160) {
      this.fail("REQUEST_ID_REQUIRED", ["X-Request-Id"]);
    }
  }

  private seriesId(planId: string, version: number, index: number) {
    return this.stableId(`schedule.plan.series\0${planId}\0${version}\0${index}`);
  }

  private stableId(seed: string) {
    const bytes = createHash("sha256").update(seed).digest().subarray(0, 16);
    bytes[6] = (bytes[6]! & 0x0f) | 0x50;
    bytes[8] = (bytes[8]! & 0x3f) | 0x80;
    const hex = bytes.toString("hex");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  private fail(code: string, fields: string[]): never {
    throw new UnprocessableEntityException({ code, fields });
  }
}
