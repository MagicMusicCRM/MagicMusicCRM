import {
  BadRequestException,
  ConflictException,
  Injectable,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import {
  assertVersionedMutationMetadata,
  VersionedMutationMetadata,
} from "../../platform/versioned-mutation-metadata";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { BulkLessonRateDto } from "../dto/bulk-lesson-rate.dto";

@Injectable()
export class LessonTeacherRateService {
  constructor(
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
    private readonly integrity: PlatformIntegrityService,
  ) {}

  /**
   * Applies one per-lesson teacher rate to a bounded selection. Only Director
   * and system_admin may change the rate. Corrections of already-settled
   * compensation preserve the previous fact and supersede it with a new one.
   *
   * Unlike updateLesson this SETS rather than coalesces — clearing the override
   * (rate = null, fall back to the group/history rate) is a thing the caller
   * must be able to express, and coalesce cannot express it.
   */
  async setLessonsTeacherRate(
    actor: ActorContext,
    dto: BulkLessonRateDto,
    metadata: VersionedMutationMetadata,
  ) {
    this.policy.assertCanManagePayrollHistory(actor);
    assertVersionedMutationMetadata(metadata);
    const rate = dto.teacherRate ?? null;
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину изменения ставки.");
    }
    const canCorrectSettled =
      actor.role === "director" || actor.role === "system_admin";
    const mutation = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: {
        actor,
        capabilityKey: "config.commerce.manage",
      },
      operation: "crm.lessons-teacher-rate.bulk-set",
      idempotencyKey: metadata.idempotencyKey,
      payload: {
        lessonIds: [...dto.lessonIds].sort(),
        teacherRate: rate,
        reasonText,
      },
      aggregateType: "schedule:teacher-rate-bulk",
      aggregateId: "global",
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.lessons_teacher_rate_bulk_set",
        entityType: "lesson",
        reason: "LESSON_TEACHER_RATE_BULK_CHANGE",
        reasonText,
        metadata: {
          teacherRate: rate,
          requested: dto.lessonIds.length,
        },
      },
      outbox: {
        type: "crm.lesson_teacher_rate.changed",
        payload: { action: "bulk_set" },
      },
      mutate: async (client) => {
        const targets = await client.query<{ id: string; locked: boolean }>(
          `
          select lesson.id,
            exists (
              select 1
              from app.lesson_teacher_compensation_facts_effective fact
              where fact.lesson_id = lesson.id
            ) as locked
          from app.lessons lesson
          where lesson.id = any($1::uuid[]) and lesson.deleted_at is null
          for update
        `,
          [dto.lessonIds],
        );
        if (targets.rows.length !== dto.lessonIds.length) {
          throw new BadRequestException(
            "Часть выбранных занятий не найдена или уже удалена.",
          );
        }
        const locked = targets.rows
          .filter((row) => row.locked)
          .map((row) => row.id);
        if (locked.length && !canCorrectSettled) {
          throw new ConflictException({
            code: "SETTLED_TEACHER_RATE_IMMUTABLE",
            message:
              "Расчёт завершённого занятия зафиксирован. Используйте корректировку расчёта в карточке занятия.",
            lessonIds: locked,
            canonicalAction: "lesson_settlement_correction",
          });
        }
        if (locked.length && rate === null) {
          throw new ConflictException({
            code: "SETTLED_TEACHER_RATE_REQUIRED",
            message:
              "Для исправления зафиксированных расчётов укажите конкретную ставку.",
            lessonIds: locked,
          });
        }
        const updated = await client.query<{ id: string }>(
          `
          update app.lessons
          set teacher_rate = $2::numeric,
            updated_at = now()
          where id = any($1::uuid[]) and deleted_at is null
          returning id
        `,
          [dto.lessonIds, rate],
        );
        if (locked.length) {
          await client.query(
            `insert into app.lesson_teacher_compensation_facts (
             lesson_id, teacher_id, compensation_type, snapshot_rate,
             rate_minor, duration_minutes, amount_minor, currency_code,
             compensation_rule_key, compensation_rule_label,
             compensation_mode, compensation_default_value,
             compensation_actual_value, compensation_override_reason,
             compensation_source, configuration_revision_id,
             supersedes_fact_id
           )
           select lesson.id, current_fact.teacher_id,
             case when $2::numeric = 0 then 'none' else 'hourly' end,
             $2::numeric, round($2::numeric * 100)::bigint,
             current_fact.duration_minutes,
             case when $2::numeric = 0 then 0 else
               round($2::numeric * 100 * current_fact.duration_minutes / 60)::bigint
             end,
             current_fact.currency_code,
             case when current_fact.configuration_revision_id is null
               then null else 'director.manual_rate_correction' end,
             case when current_fact.configuration_revision_id is null
               then null else 'Ручная коррекция ставки директором' end,
             case when current_fact.configuration_revision_id is null
               then null
               when $2::numeric = 0 then 'none' else 'hourly' end,
             case when current_fact.configuration_revision_id is null
               then null else round($2::numeric * 100)::bigint end,
             case when current_fact.configuration_revision_id is null
               then null else round($2::numeric * 100)::bigint end,
             case when current_fact.configuration_revision_id is null
               then null else $3 end,
             'manual',
             current_fact.configuration_revision_id,
             current_fact.id
           from app.lessons lesson
           join app.lesson_teacher_compensation_facts_effective current_fact
             on current_fact.lesson_id = lesson.id
           where lesson.id = any($1::uuid[])`,
            [locked, rate, reasonText],
          );
        }
        return {
          lessonIds: updated.rows.map((row) => row.id),
          correctedSettled: locked.length,
        };
      },
    });
    // One event for the batch: 500 per-lesson events would just make every
    // connected client refetch 500 times.
    this.realtime.emitCrmChanged({ entity: "lesson", action: "updated" });
    const result = mutation.resultRef as {
      lessonIds: string[];
      correctedSettled: number;
    };
    return {
      updated: result.lessonIds.length,
      correctedSettled: result.correctedSettled,
      lessonIds: result.lessonIds,
    };
  }
}
