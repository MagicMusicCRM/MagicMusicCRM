import { ConflictException, Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CrmPolicy } from "../crm.policy";
import { acquireLessonSettlementCoordinationGate, acquireLessonSettlementLocks } from "../commerce/lesson-settlement-locks";
import { SchedulePlanArchiveCommandDto } from "../dto/schedule-plan-archive.dto";
import { assertSchedulePlanMetadata } from "./schedule-plan-definition.service";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { SchedulePlanRepository } from "./schedule-plan.repository";

@Injectable()
export class SchedulePlanArchiveService {
  constructor(private readonly database: DatabaseService, private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy, private readonly plans: SchedulePlanRepository) {}

  async preview(actor: ActorContext, planId: string) {
    this.policy.assertCanWriteCrm(actor);
    return this.database.transaction(client => this.snapshot(client, actor, planId));
  }

  async archive(actor: ActorContext, planId: string, dto: SchedulePlanArchiveCommandDto, metadata: LessonCommandMetadata) {
    return this.changeArchiveState(actor, planId, dto, metadata, false);
  }

  async previewRestore(actor: ActorContext, planId: string) {
    this.policy.assertCanWriteCrm(actor);
    return this.database.transaction(client => this.snapshot(client, actor, planId, true));
  }

  async restore(actor: ActorContext, planId: string, dto: SchedulePlanArchiveCommandDto, metadata: LessonCommandMetadata) {
    return this.changeArchiveState(actor, planId, dto, metadata, true);
  }

  private async changeArchiveState(actor: ActorContext, planId: string, dto: SchedulePlanArchiveCommandDto,
    metadata: LessonCommandMetadata, restore: boolean) {
    this.policy.assertCanWriteCrm(actor);
    assertSchedulePlanMetadata(metadata);
    const operation = restore ? "restore" : "archive";
    const code = `SCHEDULE_PLAN_${operation.toUpperCase()}`;
    if (dto.confirm !== true || !dto.reasonText?.trim()) throw new UnprocessableEntityException({
      code: `${code}_CONFIRMATION_REQUIRED`, message: restore
        ? "Укажите причину и подтвердите восстановление из архива."
        : "Укажите причину и подтвердите архивирование.",
    });
    const result = await this.integrity.executeVersionedMutation({
      actorKey: `user:${actor.userId}`, actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "schedule.lesson.write" },
      operation: `schedule.plan.${operation}`, aggregateType: "schedule:plan", aggregateId: planId,
      expectedVersion: dto.expectedVersion, payload: dto,
      idempotencyKey: metadata.idempotencyKey, requestId: metadata.requestId,
      audit: { action: restore ? "crm.schedule_plan_restored" : "crm.schedule_plan_archived",
        entityType: "schedule_plan", entityId: planId,
        reason: `schedule.plan.${operation}`, reasonText: dto.reasonText.trim() },
      outbox: { type: "schedule.plan.changed", payload: { entityId: planId, state: restore ? "ended" : "archived" } },
      mutate: async (client, version) => {
        const snapshot = await this.snapshot(client, actor, planId, restore);
        if (!snapshot.canConfirm) throw new UnprocessableEntityException({
          code: `${code}_BLOCKED`, message: snapshot.blockers.join(" "), blockers: snapshot.blockers,
        });
        if (snapshot.version !== dto.expectedVersion || snapshot.impactFingerprint !== dto.impactFingerprint) {
          throw new ConflictException({ code: `${code}_STALE`,
            message: "Расписание или связанные операции изменились. Повторите проверку." });
        }
        if (restore) {
          // Only undo visibility for this archive operation, never lesson cancellation.
          await client.query("update app.lessons set archived_at = null where id = any($1::uuid[])", [snapshot.lessonIds]);
          await client.query(`update app.schedule_plans set archived_at = null, archived_by = null,
            archive_reason = null, version = $2, updated_at = now() where id = $1`, [planId, version]);
        } else {
          await client.query(`update app.schedule_plans set archived_at = now(), archived_by = $2,
          archive_reason = $3, version = $4, updated_at = now() where id = $1`,
        [planId, actor.userId, dto.reasonText.trim(), version]);
        await client.query("update app.lessons set archived_at = now() where id = any($1::uuid[])", [snapshot.lessonIds]);
        }
        return { id: planId, hiddenLessons: restore ? 0 : snapshot.lessonCount,
          restoredLessons: restore ? snapshot.lessonCount : 0 };
      },
    });
    return { ...result.resultRef, version: result.version, replayed: result.replayed };
  }

  private async snapshot(client: PoolClient, actor: ActorContext, planId: string, restore = false) {
    // Terminal commands and multi-lesson operations use this same gate before lesson locks.
    await acquireLessonSettlementCoordinationGate(client);
    const plan = await this.plans.lock(client, planId, actor);
    const lessons = await client.query<{ id: string; version: number; lifecycle_state: string }>(`
      with recursive members(id) as (
        select lesson.id from app.lessons lesson join app.schedule_series series on series.id = lesson.series_id
        where series.plan_id = $1
        union
        select successor.id from app.lessons successor join members on successor.predecessor_id = members.id
      ) select lesson.id, lesson.version, lesson.lifecycle_state, lesson.archived_at
      from app.lessons lesson join members on members.id = lesson.id
      where lesson.deleted_at is null
        ${restore ? "and lesson.archived_at = (select archived_at from app.schedule_plans where id = $1)" : ""}
      order by lesson.id`, [planId]);
    const ids = lessons.rows.map(row => row.id);
    await acquireLessonSettlementLocks(client, ids);
    await client.query("select id from app.lessons where id = any($1::uuid[]) order by id for update", [ids]);
    const linked = await client.query<{ financial: boolean; reserved: boolean }>(`
      select (
        exists(select 1 from app.payments where lesson_id = any($1::uuid[]))
        or exists(select 1 from app.lesson_client_charge_facts
          where lesson_id = any($1::uuid[]) and (amount_minor <> 0 or units <> 0))
        or exists(select 1 from app.lesson_teacher_compensation_facts
          where lesson_id = any($1::uuid[]) and amount_minor <> 0)
      ) as financial,
      exists(select 1 from app.lesson_reservations where lesson_id = any($1::uuid[])
        and state in ('reserved', 'consumed')) as reserved`, [ids]);
    const blockers: string[] = [];
    if (restore && !plan.archived_at) blockers.push("Расписание не находится в архиве.");
    if (!restore && plan.archived_at) blockers.push("Расписание уже находится в архиве.");
    if (plan.kind !== "individual" || plan.status !== "ended") blockers.push("Сначала завершите индивидуальное расписание.");
    if (lessons.rows.some(row => row.lifecycle_state !== "cancelled")) blockers.push("В серии есть занятия, которые не отменены.");
    if (!restore && linked.rows[0]?.financial) blockers.push("В серии есть оплаты, списания или начисления. Финансовая история должна оставаться видимой.");
    if (!restore && linked.rows[0]?.reserved) blockers.push("В серии остались резервы абонемента. Сначала проверьте расчёт занятий.");
    return { id: planId, title: plan.title, version: Number(plan.version), lessonCount: ids.length, lessonIds: ids,
      canConfirm: blockers.length === 0, blockers,
      impactFingerprint: fingerprintPayload({ planId, restore, version: plan.version,
        archivedAt: plan.archived_at, lessons: lessons.rows, linked: linked.rows }) };
  }
}
