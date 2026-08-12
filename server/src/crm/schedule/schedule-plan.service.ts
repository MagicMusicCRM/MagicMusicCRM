import {
  ConflictException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { CrmPolicy } from "../crm.policy";
import {
  CreateSchedulePlanDto,
  SchedulePlanEndCommandDto,
  SchedulePlanEndPreviewDto,
  SchedulePlanConstraintPreviewDto,
  SchedulePlanParticipantDto,
  SchedulePlanQuery,
  SchedulePlanRowDto,
  SchedulePlanTrayQuery,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import { ScheduleService } from "../schedule.service";
import type { LessonCommandMetadata } from "./lesson-command.service";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import {
  LockedSchedulePlan,
  SchedulePlanEndImpact,
  SchedulePlanRepository,
  SchedulePlanTrayCursor,
} from "./schedule-plan.repository";

@Injectable()
export class SchedulePlanService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly repository: SchedulePlanRepository,
    private readonly series: LessonSeriesCommandService,
    private readonly schedule: ScheduleService,
    private readonly database: DatabaseService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly lifecycle: LessonLifecycleRepository,
    private readonly reservations: SubscriptionReservationService,
    private readonly settlement: LessonSettlementService,
  ) {}

  list(actor: ActorContext, query: SchedulePlanQuery) {
    return this.repository.list(actor, query);
  }

  async previewConstraints(
    actor: ActorContext,
    dto: SchedulePlanConstraintPreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const normalized = this.normalizeCreate(dto);
    return this.database.transaction(async (client) => {
      const studentIds =
        normalized.kind === "individual"
          ? [normalized.studentId!]
          : normalized.participants.map((participant) => participant.studentId);
      await this.lockAndValidate(
        client,
        this.stableId(`schedule.plan.preview\0${actor.userId}`),
        normalized.kind,
        normalized.studentId,
        normalized.groupId,
        normalized.subscriptionId,
        normalized.participants,
        normalized.rows,
      );
      const rows = [];
      for (const [index, row] of normalized.rows.entries()) {
        await this.settlement.preparePlan(
          client,
          row.branchId,
          row.financialDecision,
        );
        rows.push({
          index,
          ...(await this.series.previewPlanRow(
            client,
            row,
            normalized.activeFrom,
            normalized.activeUntil,
            studentIds,
          )),
        });
      }
      this.addCrossRowViolations(normalized.rows, rows, studentIds);
      return {
        valid: rows.every((row) => row.failures.length === 0),
        rows: rows.map((row) => ({
          index: row.index,
          valid: row.failures.length === 0,
          occurrencesChecked: row.occurrences.length,
          failures: row.failures,
        })),
      };
    });
  }

  async previewUpdateConstraints(
    actor: ActorContext,
    planId: string,
    dto: UpdateSchedulePlanDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertRows(dto.rows);
    return this.database.transaction(async (client) => {
      const prepared = await this.prepareUpdate(client, planId, dto);
      const excludeScheduleSeriesIds = prepared.activeSeries.map(
        (series) => series.id,
      );
      const rows = [];
      for (const [index, row] of dto.rows.entries()) {
        await this.settlement.preparePlan(
          client,
          row.branchId,
          row.financialDecision,
        );
        rows.push({
          index,
          ...(await this.series.previewPlanRow(
            client,
            row,
            prepared.effectiveFrom,
            prepared.activeUntil,
            prepared.studentIds,
            { excludeScheduleSeriesIds },
          )),
        });
      }
      this.addCrossRowViolations(dto.rows, rows, prepared.studentIds);
      return {
        valid: rows.every((row) => row.failures.length === 0),
        rows: rows.map((row) => ({
          index: row.index,
          valid: row.failures.length === 0,
          occurrencesChecked: row.occurrences.length,
          failures: row.failures,
        })),
      };
    });
  }

  async previewEnd(
    actor: ActorContext,
    planId: string,
    dto: SchedulePlanEndPreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const normalized = this.normalizeEnd(dto);
    return this.database.transaction(async (client) => {
      const plan = await this.repository.lock(client, planId);
      await this.assertEndable(client, plan, normalized);
      const impact = await this.repository.endImpact(
        client,
        planId,
        normalized.lastDate,
      );
      const impactFingerprint = this.endFingerprint(plan, normalized, impact);
      const signed = this.previewTokens.issueSchedulePlanEnd({
        kind: "schedule.plan.end",
        actorUserId: actor.userId,
        planId,
        expectedVersion: normalized.expectedVersion,
        lastDate: normalized.lastDate,
        impactFingerprint,
      });
      return {
        plan: {
          id: plan.id,
          title: plan.title,
          version: Number(plan.version),
          lastDate: normalized.lastDate,
        },
        impact: this.endImpactProjection(impact),
        canConfirm: true,
        confirmRequired: true,
        previewToken: signed.token,
        previewExpiresAt: signed.expiresAt,
      };
    });
  }

  async end(
    actor: ActorContext,
    planId: string,
    dto: SchedulePlanEndCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    if (dto.confirm !== true) {
      this.fail("SCHEDULE_PLAN_END_CONFIRMATION_REQUIRED", ["confirm"]);
    }
    const normalized = this.normalizeEnd(dto);
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "schedule.lesson.write" },
      operation: "schedule.plan.end",
      idempotencyKey: metadata.idempotencyKey,
      payload: dto,
      aggregateType: "schedule:plan",
      aggregateId: planId,
      expectedVersion: normalized.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.schedule_plan_ended",
        entityType: "schedule_plan",
        entityId: planId,
        reason: "schedule.plan.end",
        reasonText: normalized.reasonText,
      },
      outbox: {
        type: "schedule.plan.changed",
        payload: { entityId: planId, state: "ended" },
      },
      mutate: async (client, version) => {
        const signed = this.previewTokens.verifySchedulePlanEnd(
          dto.previewToken,
        );
        const plan = await this.repository.lock(client, planId);
        await this.assertEndable(client, plan, normalized);
        const currentSeries = await this.repository.currentSeriesIds(
          client,
          planId,
        );
        await this.schedule.lockSchedulePlanSeries(
          client,
          currentSeries.rows.map((series) => series.id),
        );
        const impact = await this.repository.endImpact(
          client,
          planId,
          normalized.lastDate,
          true,
        );
        const impactFingerprint = this.endFingerprint(plan, normalized, impact);
        if (
          signed.actorUserId !== actor.userId ||
          signed.planId !== planId ||
          signed.expectedVersion !== normalized.expectedVersion ||
          signed.lastDate !== normalized.lastDate ||
          signed.impactFingerprint !== impactFingerprint
        ) {
          this.fail("SCHEDULE_PLAN_END_PREVIEW_STALE", ["previewToken"]);
        }
        const finished = await this.repository.finish(client, {
          planId,
          expectedVersion: normalized.expectedVersion,
          version,
          lastDate: normalized.lastDate,
          actorUserId: actor.userId,
          reasonText: normalized.reasonText,
        });
        if (!finished.rows[0]) {
          throw new ConflictException({ code: "SCHEDULE_PLAN_VERSION_STALE" });
        }
        for (const lesson of impact.lessons) {
          const updated = await this.repository.cancelLesson(
            client,
            lesson.id,
            lesson.version,
          );
          if (
            !updated.rows[0] ||
            Number(updated.rows[0].version) !== lesson.version + 1
          ) {
            throw new ConflictException({
              code: "STALE_LESSON_VERSION",
              lessonId: lesson.id,
            });
          }
          await this.lifecycle.appendTransition(client, {
            lessonId: lesson.id,
            fromState: lesson.lifecycleState,
            toState: "cancelled",
            reasonCode: "schedule.plan.end",
            reasonText: normalized.reasonText,
            actorUserId: actor.userId,
            financialDecision: {
              settlementTypeKey: "schedule.plan.end",
              clientChargeType: "none",
              teacherCompensationRuleKey: "none",
            },
          });
        }
        const releasedReservations = await this.reservations.releaseForLessons(
          client,
          impact.lessons.map((lesson) => lesson.id),
        );
        return {
          planId,
          endedLessons: impact.lessons.length,
          releasedReservations,
          preservedTerminalLessons: impact.terminalLessonCount,
        };
      },
    });
    return {
      id: planId,
      status: "ended" as const,
      version: mutation.version,
      endedLessons: mutation.resultRef.endedLessons as number,
      releasedReservations: mutation.resultRef.releasedReservations as number,
      preservedTerminalLessons: mutation.resultRef
        .preservedTerminalLessons as number,
      replayed: mutation.replayed,
    };
  }

  async tray(
    actor: ActorContext,
    planId: string,
    query: SchedulePlanTrayQuery,
  ) {
    if (query.direction && !query.cursor) {
      this.fail("SCHEDULE_PLAN_TRAY_CURSOR_REQUIRED", ["cursor"]);
    }
    const limit = Math.max(1, Math.min(query.limit ?? 40, 40));
    if (query.cursor) {
      const cursor = this.decodeTrayCursor(query.cursor);
      const direction = query.direction ?? "next";
      const rows = await this.repository.trayPage(
        actor,
        planId,
        direction,
        cursor,
        limit,
      );
      const hasMore = rows.length > limit;
      const page = rows.slice(0, limit);
      if (direction === "previous") page.reverse();
      return this.trayProjection(
        planId,
        page,
        direction === "previous" ? hasMore : page.length > 0,
        direction === "next" ? hasMore : page.length > 0,
      );
    }
    const anchor: SchedulePlanTrayCursor = {
      scheduledAt: new Date().toISOString(),
      id: "00000000-0000-0000-0000-000000000000",
    };
    const previousLimit = Math.floor(limit / 2);
    const nextLimit = limit - previousLimit;
    const [previousRows, nextRows] = await Promise.all([
      previousLimit > 0
        ? this.repository.trayPage(
            actor,
            planId,
            "previous",
            anchor,
            previousLimit,
          )
        : Promise.resolve([]),
      this.repository.trayPage(actor, planId, "next", anchor, nextLimit, true),
    ]);
    const hasPrevious = previousRows.length > previousLimit;
    const hasNext = nextRows.length > nextLimit;
    const page = [
      ...previousRows.slice(0, previousLimit).reverse(),
      ...nextRows.slice(0, nextLimit),
    ];
    return this.trayProjection(planId, page, hasPrevious, hasNext);
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
        const studentIds =
          normalized.kind === "individual"
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
          const settlementPlan = await this.settlement.preparePlan(
            client,
            row.branchId,
            row.financialDecision,
          );
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
            settlementPlan,
          });
          await this.schedule.materializePlanSeries(client, seriesId);
          seriesIds.push(seriesId);
          lessonIds.push(...(await this.lessonIds(client, seriesId)));
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
        const {
          plan,
          participants,
          subscriptionId,
          activeUntil,
          studentIds,
          activeSeries,
          effectiveFrom,
        } = await this.prepareUpdate(client, planId, dto);

        await this.schedule.lockSchedulePlanSeries(
          client,
          activeSeries.map((series) => series.id),
        );

        const continuations = new Map<string, string>();
        const seriesIds: string[] = [];
        for (const [index, row] of dto.rows.entries()) {
          const seriesId = this.seriesId(planId, version, index);
          const settlementPlan = await this.settlement.preparePlan(
            client,
            row.branchId,
            row.financialDecision,
          );
          await this.repository.insertSeries(client, {
            id: seriesId,
            planId,
            studentId: plan.student_id,
            groupId: plan.group_id,
            validFrom: effectiveFrom,
            validUntil: activeUntil,
            row,
            actorUserId: actor.userId,
            version,
            settlementPlan,
          });
          if (row.seriesId) continuations.set(row.seriesId, seriesId);
          seriesIds.push(seriesId);
        }
        for (const old of activeSeries) {
          await this.repository.retireSeries(
            client,
            old.id,
            effectiveFrom,
            continuations.get(old.id) ?? null,
          );
        }
        if (plan.kind === "group") {
          await this.repository.replaceParticipants(
            client,
            planId,
            participants,
            effectiveFrom,
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
            effectiveFrom,
            activeUntil,
            studentIds,
          );
          const seriesId = seriesIds[index]!;
          await this.schedule.materializePlanSeries(client, seriesId);
          lessonIds.push(...(await this.lessonIds(client, seriesId)));
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

  private async prepareUpdate(
    client: PoolClient,
    planId: string,
    dto: UpdateSchedulePlanDto,
  ) {
    const plan = await this.repository.lock(client, planId);
    this.assertEditable(plan, dto);
    const effectiveFrom = dto.effectiveFrom.slice(0, 10);
    const participants =
      plan.kind === "group"
        ? (dto.participants ??
          (await this.currentParticipants(client, planId, effectiveFrom)))
        : [];
    const subscriptionId =
      plan.kind === "individual"
        ? (dto.subscriptionId ?? plan.subscription_id)
        : null;
    const activeUntil = Object.prototype.hasOwnProperty.call(dto, "activeUntil")
      ? (dto.activeUntil?.slice(0, 10) ?? null)
      : plan.active_until;
    this.assertPeriod(effectiveFrom, activeUntil);
    const effectiveDate = await client.query<{ valid: boolean }>(
      `select not exists (
         select 1 from app.branches branch
         where branch.id = any($2::uuid[])
           and $1::date < timezone(branch.timezone_name, now())::date
       ) as valid`,
      [effectiveFrom, [...new Set(dto.rows.map((row) => row.branchId))]],
    );
    if (!effectiveDate.rows[0]?.valid) {
      this.fail("SCHEDULE_PLAN_EFFECTIVE_DATE_PAST", ["effectiveFrom"]);
    }
    const studentIds =
      plan.kind === "individual"
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
    const activeSeries = (await this.repository.activeSeries(client, planId))
      .rows;
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
    return {
      plan,
      participants,
      subscriptionId,
      activeUntil,
      studentIds,
      activeSeries,
      effectiveFrom,
    };
  }

  private normalizeCreate(dto: CreateSchedulePlanDto) {
    const title = dto.title.trim();
    if (!title) this.fail("SCHEDULE_PLAN_TITLE_REQUIRED", ["title"]);
    const studentId =
      dto.kind === "individual" ? (dto.studentId ?? null) : null;
    const groupId = dto.kind === "group" ? (dto.groupId ?? null) : null;
    const subscriptionId =
      dto.kind === "individual" ? (dto.subscriptionId ?? null) : null;
    const participants = dto.kind === "group" ? (dto.participants ?? []) : [];
    if (dto.kind === "individual" && (!studentId || !subscriptionId)) {
      this.fail("SCHEDULE_PLAN_INDIVIDUAL_SUBJECT_REQUIRED", [
        "studentId",
        "subscriptionId",
      ]);
    }
    if (dto.kind === "group" && (!groupId || participants.length === 0)) {
      this.fail("SCHEDULE_PLAN_GROUP_SUBJECT_REQUIRED", [
        "groupId",
        "participants",
      ]);
    }
    if (
      (dto.kind === "individual" &&
        (dto.groupId || (dto.participants?.length ?? 0) > 0)) ||
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
    const keys = rows.map((row) =>
      [
        row.teacherId,
        row.roomId,
        row.branchId,
        row.weekday,
        row.beginTime,
        row.durationMinutes ?? 60,
      ].join(":"),
    );
    if (new Set(keys).size !== keys.length) {
      this.fail("SCHEDULE_PLAN_DUPLICATE_ROW", ["rows"]);
    }
  }

  private addCrossRowViolations(
    rows: SchedulePlanRowDto[],
    previews: Array<{
      index: number;
      occurrences: Array<{ startAt: string; endAt: string }>;
      failures: Array<Record<string, unknown>>;
    }>,
    studentIds: string[],
  ) {
    for (let leftIndex = 0; leftIndex < rows.length; leftIndex += 1) {
      for (
        let rightIndex = leftIndex + 1;
        rightIndex < rows.length;
        rightIndex += 1
      ) {
        const left = rows[leftIndex]!;
        const right = rows[rightIndex]!;
        for (const leftOccurrence of previews[leftIndex]!.occurrences) {
          const rightOccurrence = previews[rightIndex]!.occurrences.find(
            (candidate) =>
              Date.parse(leftOccurrence.startAt) <
                Date.parse(candidate.endAt) &&
              Date.parse(candidate.startAt) < Date.parse(leftOccurrence.endAt),
          );
          if (!rightOccurrence) continue;
          for (const [source, target, occurrence] of [
            [leftIndex, rightIndex, leftOccurrence],
            [rightIndex, leftIndex, rightOccurrence],
          ] as const) {
            for (const studentId of studentIds) {
              const shared = [
                ...(left.teacherId === right.teacherId
                  ? [
                      {
                        code: "TEACHER_OVERLAP",
                        type: "teacher",
                        id: left.teacherId,
                      },
                    ]
                  : []),
                ...(left.roomId === right.roomId
                  ? [{ code: "ROOM_OVERLAP", type: "room", id: left.roomId }]
                  : []),
                { code: "CLIENT_OVERLAP", type: "client", id: studentId },
              ];
              previews[source]!.failures.push({
                occurrence,
                studentId,
                violations: shared.map((violation) => ({
                  code: violation.code,
                  resource: { type: violation.type, id: violation.id },
                  conflictingLessonIds: [],
                  conflictingRowIndexes: [target],
                  ruleIds: ["schedule_plan.rows"],
                })),
              });
            }
          }
          break;
        }
      }
    }
  }

  private assertParticipants(participants: SchedulePlanParticipantDto[]) {
    if (
      new Set(participants.map((item) => item.studentId)).size !==
      participants.length
    ) {
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
    const subscriptionIds =
      kind === "individual"
        ? [subscriptionId!]
        : participants.map((participant) => participant.subscriptionId);
    const studentIds =
      kind === "individual"
        ? [studentId!]
        : participants.map((participant) => participant.studentId);
    const locks = [
      `plan:${planId}`,
      ...(groupId ? [`group:${groupId}`] : []),
      ...studentIds.map((id) => `client:student:${id}`),
      ...subscriptionIds.map((id) => `subscription:${id}`),
      ...rows.flatMap((row) => [
        `branch:${row.branchId}`,
        `room:${row.roomId}`,
        `teacher:${row.teacherId}`,
      ]),
    ].sort();
    for (const key of new Set(locks)) {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [key],
      );
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
    const assignments =
      kind === "individual"
        ? [{ studentId: studentId!, subscriptionId: subscriptionId! }]
        : participants;
    if (
      assignments.some((assignment) => {
        const subscription = owners.get(assignment.subscriptionId);
        return (
          !subscription ||
          subscription.status !== "active" ||
          subscription.student_id !== assignment.studentId
        );
      })
    ) {
      this.fail("SCHEDULE_PLAN_SUBSCRIPTION_INVALID", [
        "subscriptionId",
        "participants",
      ]);
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
        this.fail("SCHEDULE_PLAN_GROUP_PARTICIPANT_INVALID", [
          "groupId",
          "participants",
        ]);
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

  private normalizeEnd(dto: SchedulePlanEndPreviewDto) {
    const reasonText = dto.reasonText.trim();
    if (!reasonText || reasonText.length > 500 || reasonText.includes("\0")) {
      this.fail("SCHEDULE_PLAN_END_REASON_REQUIRED", ["reasonText"]);
    }
    return {
      expectedVersion: dto.expectedVersion,
      lastDate: dto.lastDate.slice(0, 10),
      reasonText,
    };
  }

  private async assertEndable(
    client: PoolClient,
    plan: LockedSchedulePlan,
    input: { expectedVersion: number; lastDate: string },
  ) {
    if (plan.status !== "active") {
      throw new ConflictException({ code: "SCHEDULE_PLAN_ENDED" });
    }
    if (Number(plan.version) !== input.expectedVersion) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_VERSION_STALE" });
    }
    const today = await this.repository.localToday(client, plan.id);
    if (input.lastDate < plan.active_from || input.lastDate < today) {
      this.fail("SCHEDULE_PLAN_END_DATE_INVALID", ["lastDate"]);
    }
  }

  private endFingerprint(
    plan: LockedSchedulePlan,
    input: { expectedVersion: number; lastDate: string; reasonText: string },
    impact: SchedulePlanEndImpact,
  ) {
    return fingerprintPayload({
      planId: plan.id,
      expectedVersion: input.expectedVersion,
      lastDate: input.lastDate,
      reasonText: input.reasonText,
      series: impact.series,
      lessons: impact.lessons,
      reservations: impact.reservations,
      terminalLessonCount: impact.terminalLessonCount,
    });
  }

  private endImpactProjection(impact: SchedulePlanEndImpact) {
    return {
      activeSeries: impact.series.length,
      futureUnsettledLessons: impact.lessons.length,
      activeReservations: impact.reservations.length,
      reservedUnits: this.sumUnits(
        impact.reservations.map((reservation) => reservation.units),
      ),
      preservedTerminalLessons: impact.terminalLessonCount,
    };
  }

  private sumUnits(values: string[]) {
    const total = values.reduce((sum, value) => {
      const [whole, fraction = ""] = value.split(".");
      return (
        sum + BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0").slice(0, 2))
      );
    }, 0n);
    return `${total / 100n}.${String(total % 100n).padStart(2, "0")}`;
  }

  private trayProjection(
    planId: string,
    rows: Awaited<ReturnType<SchedulePlanRepository["trayPage"]>>,
    hasPrevious: boolean,
    hasNext: boolean,
  ) {
    const items = rows.map((row) => ({
      id: row.id,
      scheduledAt: new Date(row.scheduled_at).toISOString(),
      localDate: row.local_date,
      localTime: row.local_time,
      state: row.lifecycle_state,
      settlementMarkers: row.markers,
      relationMarker: row.successor_id
        ? "source"
        : row.predecessor_id
          ? "successor"
          : "none",
      predecessorId: row.predecessor_id,
      successorId: row.successor_id,
      teacher: row.teacher_id
        ? { id: row.teacher_id, name: row.teacher_name }
        : null,
      room: row.room_id ? { id: row.room_id, name: row.room_name } : null,
    }));
    return {
      planId,
      items,
      hasPrevious,
      hasNext,
      previousCursor:
        hasPrevious && items[0]
          ? this.encodeTrayCursor(items[0].scheduledAt, items[0].id)
          : null,
      nextCursor:
        hasNext && items.at(-1)
          ? this.encodeTrayCursor(items.at(-1)!.scheduledAt, items.at(-1)!.id)
          : null,
    };
  }

  private encodeTrayCursor(scheduledAt: string, id: string) {
    return Buffer.from(JSON.stringify({ scheduledAt, id }), "utf8").toString(
      "base64url",
    );
  }

  private decodeTrayCursor(cursor: string): SchedulePlanTrayCursor {
    try {
      const value = JSON.parse(
        Buffer.from(cursor, "base64url").toString("utf8"),
      ) as Record<string, unknown>;
      if (
        Object.keys(value).length !== 2 ||
        typeof value.scheduledAt !== "string" ||
        !Number.isFinite(new Date(value.scheduledAt).getTime()) ||
        typeof value.id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
          value.id,
        )
      ) {
        throw new Error("invalid");
      }
      return { scheduledAt: value.scheduledAt, id: value.id };
    } catch {
      this.fail("SCHEDULE_PLAN_TRAY_CURSOR_INVALID", ["cursor"]);
    }
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
    return this.stableId(
      `schedule.plan.series\0${planId}\0${version}\0${index}`,
    );
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
