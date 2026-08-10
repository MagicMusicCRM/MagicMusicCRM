import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PoolClient } from "pg";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import {
  ArchiveClientCommandDto,
  ArchiveConvertedLeadDto,
} from "../dto/client-archive.dto";
import { ClientRefDto, ClientRefType } from "../dto/client-ref.dto";

interface ArchiveSnapshotRow {
  type: ClientRefType;
  id: string;
  label: string;
  deleted_at: Date | string | null;
  version: number | string;
  linked_type: ClientRefType | null;
  linked_id: string | null;
  linked_user_count: number | string;
  future_lesson_count: number | string;
  open_task_count: number | string;
  active_subscription_count: number | string;
  payment_count: number | string;
  expected_payment_count: number | string;
  account_adjustment_count: number | string;
}

export interface ArchiveImpact {
  futureLessons: number;
  openTasks: number;
  activeSubscriptions: number;
  financeFacts: number;
  payments: number;
  expectedPayments: number;
  accountAdjustments: number;
}

export interface ClientContextLink {
  rel: "convertedStudent" | "sourceLead";
  ref: { type: ClientRefType; id: string };
  href: string;
}

export interface ArchiveSnapshot {
  ref: { type: ClientRefType; id: string };
  label: string;
  lifecycleState: "active" | "archived";
  tombstone: boolean;
  archivedAt: Date | string | null;
  version: number;
  impact: ArchiveImpact;
  linkedUserCount: number;
  links: ClientContextLink[];
}

export interface ArchiveWarning {
  code:
    | "FUTURE_LESSONS_PRESERVED"
    | "OPEN_TASKS_PRESERVED"
    | "ACTIVE_SUBSCRIPTIONS_PRESERVED"
    | "FINANCE_FACTS_PRESERVED";
  count: number;
  message: string;
}

@Injectable()
export class ClientArchiveService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  async preview(actor: ActorContext, ref: ClientRefDto) {
    this.policy.assertCanArchiveClient(actor);
    const snapshot = await this.readSnapshot(ref);
    return {
      ...snapshot,
      confirmRequired: !snapshot.tombstone,
      warnings: this.warnings(snapshot.impact),
      blockers: [],
    };
  }

  async archive(actor: ActorContext, dto: ArchiveClientCommandDto) {
    return this.archiveInternal(actor, dto, false);
  }

  async archiveConvertedLead(
    actor: ActorContext,
    leadId: string,
    dto: ArchiveConvertedLeadDto,
  ) {
    const result = await this.archiveInternal(
      actor,
      { type: "lead", id: leadId, ...dto },
      true,
    );
    const studentLink = result.tombstone.links.find(
      (link) => link.rel === "convertedStudent",
    );
    if (!studentLink) {
      throw new NotFoundException("Конвертированный лид не найден.");
    }
    return {
      leadId,
      studentId: studentLink.ref.id,
      archived: true,
      version: result.tombstone.version,
      replayed: result.replayed,
      tombstone: result.tombstone,
    };
  }

  private async archiveInternal(
    actor: ActorContext,
    dto: ArchiveClientCommandDto,
    requireConversion: boolean,
  ) {
    this.policy.assertCanArchiveClient(actor);
    this.assertCommand(dto);
    const snapshot = await this.readSnapshot(dto);
    if (
      requireConversion &&
      !snapshot.links.some((link) => link.rel === "convertedStudent")
    ) {
      throw new NotFoundException("Конвертированный лид не найден.");
    }
    if (snapshot.tombstone) {
      return { tombstone: snapshot, replayed: true };
    }
    if (snapshot.version !== dto.expectedVersion) {
      throw new ConflictException({
        code: "STALE_CLIENT_VERSION",
        message: "Карточка клиента была изменена.",
        expectedVersion: dto.expectedVersion,
        currentVersion: snapshot.version,
      });
    }

    const aggregateType = `crm:${dto.type}`;
    const table = dto.type === "lead" ? "app.leads" : "app.students";
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.client.archive",
      idempotencyKey: `${dto.type}:${dto.id}:v${dto.expectedVersion}`,
      payload: {
        ref: { type: dto.type, id: dto.id },
        reasonCode: dto.reason,
      },
      aggregateType,
      aggregateId: dto.id,
      expectedVersion: dto.expectedVersion,
      requestId: `client-archive:${dto.type}:${dto.id}:v${dto.expectedVersion}`,
      audit: {
        action: "crm.client_archived",
        entityType: aggregateType,
        entityId: dto.id,
        reason: dto.reason,
        beforeRef: {
          lifecycleState: "active",
          version: snapshot.version,
        },
        afterRef: {
          lifecycleState: "archived",
          version: snapshot.version + 1,
        },
        metadata: {
          clientType: dto.type,
          futureLessons: snapshot.impact.futureLessons,
          openTasks: snapshot.impact.openTasks,
          activeSubscriptions: snapshot.impact.activeSubscriptions,
          financeFacts: snapshot.impact.financeFacts,
          linkedUserCount: snapshot.linkedUserCount,
          linkedEntityId: snapshot.links[0]?.ref.id,
        },
      },
      outbox: {
        type: "crm.client.archived",
        payload: {
          entityId: dto.id,
          state: "archived",
        },
      },
      mutate: async (client, nextVersion) => {
        const recurringActions = await this.cancelRecurringActions(
          client,
          dto,
          actor.userId,
          dto.reason,
        );
        const updated = await client.query<{
          deleted_at: Date | string;
          version: number | string;
        }>(
          `
            update ${table}
               set deleted_at = now(),
                   updated_at = now(),
                   version = $3
             where id = $1
               and deleted_at is null
               and version = $2
            returning deleted_at, version
          `,
          [dto.id, dto.expectedVersion, nextVersion],
        );
        const row = updated.rows[0];
        if (!row) {
          throw new ConflictException({
            code: "STALE_CLIENT_VERSION",
            message: "Карточка клиента была изменена во время архивирования.",
          });
        }
        return {
          entityId: dto.id,
          entityType: dto.type,
          lifecycleState: "archived",
          archivedAt: row.deleted_at,
          version: Number(row.version),
          recurringActions,
        };
      },
    });

    const tombstone: ArchiveSnapshot = {
      ...snapshot,
      lifecycleState: "archived",
      tombstone: true,
      archivedAt: result.resultRef.archivedAt as Date | string,
      version: result.version,
    };
    if (!result.replayed) {
      this.realtime.emitCrmChanged({
        entity: dto.type,
        action: "deleted",
        id: dto.id,
      });
    }
    return { tombstone, replayed: result.replayed };
  }

  private async cancelRecurringActions(
    client: PoolClient,
    ref: ClientRefDto,
    actorUserId: string,
    reasonCode: string,
  ) {
    const plans = ref.type === "student"
      ? await client.query<{ id: string; version: number | string }>(
          `select plan.id, plan.version
           from app.schedule_plans plan
           where plan.status = 'active' and (
             plan.student_id = $1
             or (
               plan.kind = 'group'
               and exists (
                 select 1 from app.schedule_plan_participants participant
                 where participant.plan_id = plan.id
                   and participant.student_id = $1
                   and participant.effective_from <= current_date
                   and (participant.effective_until is null
                     or participant.effective_until >= current_date)
               )
               and not exists (
                 select 1 from app.schedule_plan_participants other
                 where other.plan_id = plan.id
                   and other.student_id <> $1
                   and other.effective_from <= current_date
                   and (other.effective_until is null
                     or other.effective_until >= current_date)
               )
             )
           )
           order by plan.id for update`,
          [ref.id],
        )
      : { rows: [] as Array<{ id: string; version: number | string }> };
    const planIds = plans.rows.map((plan) => plan.id);

    if (ref.type === "student") {
      await client.query(
        `update app.group_students
         set left_at = coalesce(left_at, now())
         where student_id = $1 and left_at is null`,
        [ref.id],
      );
      await client.query(
        `delete from app.schedule_plan_participants
         where student_id = $1 and effective_from > current_date`,
        [ref.id],
      );
      await client.query(
        `update app.schedule_plan_participants
         set effective_until = least(coalesce(effective_until, current_date),
               current_date),
             version = version + 1,
             updated_at = now()
         where student_id = $1 and effective_from <= current_date
           and (effective_until is null or effective_until >= current_date)`,
        [ref.id],
      );
    }

    if (planIds.length > 0) {
      await client.query(
        `update app.schedule_plans
         set status = 'ended',
             active_until = greatest(active_from, current_date),
             version = version + 1,
             ended_at = now(),
             ended_by = $2,
             end_reason = $3,
             updated_at = now()
         where id = any($1::uuid[]) and status = 'active'`,
        [planIds, actorUserId, `client.archive:${reasonCode}`],
      );
      await client.query(
        `insert into app.aggregate_versions (
           aggregate_type, aggregate_id, version
         )
         select 'schedule:plan', plan.id::text, plan.version
         from app.schedule_plans plan where plan.id = any($1::uuid[])
         on conflict (aggregate_type, aggregate_id) do update
         set version = greatest(app.aggregate_versions.version, excluded.version),
             updated_at = now()`,
        [planIds],
      );
    }

    await client.query(
      `update app.schedule_series series
       set valid_until = greatest(
             series.valid_from,
             least(coalesce(series.valid_until, current_date), current_date)
           ),
           deleted_at = case when series.valid_from > current_date
             then coalesce(series.deleted_at, now()) else series.deleted_at end,
           version = series.version + 1,
           updated_at = now()
       where series.deleted_at is null and series.superseded_by is null
         and (
           series.plan_id = any($1::uuid[])
           or (
             series.plan_id is null and (
               ($2::text = 'student' and series.student_id = $3::uuid)
               or (series.client_type = $2 and series.client_id = $3::uuid)
             )
           )
         )`,
      [planIds, ref.type, ref.id],
    );

    let excludedGroupLessons = 0;
    if (ref.type === "student") {
      const exclusions = await client.query(
        `insert into app.lesson_participant_exclusions (
           lesson_id, student_id, reason_code, actor_user_id
         )
         select lesson.id, participant.student_id, $2, $3
         from app.lessons lesson
         join app.lesson_snapshot_participants participant
           on participant.lesson_id = lesson.id and participant.student_id = $1
         where lesson.group_id is not null
           and lesson.deleted_at is null
           and lesson.scheduled_at >= now()
           and lesson.lifecycle_state in ('scheduled', 'settlement_pending')
         on conflict (lesson_id, student_id) do nothing`,
        [ref.id, `client.archive:${reasonCode}`, actorUserId],
      );
      excludedGroupLessons = exclusions.rowCount ?? 0;
      await client.query(
        `update app.lesson_reservations reservation
         set state = 'released', financial_fact_id = null, updated_at = now()
         from app.subscriptions subscription,
              app.lesson_participant_exclusions exclusion
         where reservation.subscription_id = subscription.id
           and exclusion.lesson_id = reservation.lesson_id
           and exclusion.student_id = $1
           and subscription.student_id = $1
           and reservation.state = 'reserved'`,
        [ref.id],
      );
    }

    const candidates = await client.query<{
      id: string;
      lifecycle_state: "scheduled" | "settlement_pending";
    }>(
      `select lesson.id, lesson.lifecycle_state
       from app.lessons lesson
       left join app.schedule_series series on series.id = lesson.series_id
       where lesson.deleted_at is null
         and lesson.scheduled_at >= now()
         and lesson.lifecycle_state in ('scheduled', 'settlement_pending')
         and (
           series.plan_id = any($1::uuid[])
           or (
             series.plan_id is null and series.id is not null and (
               ($2::text = 'student' and series.student_id = $3::uuid)
               or (series.client_type = $2 and series.client_id = $3::uuid)
             )
           )
           or (
             $2::text = 'student' and lesson.group_id is not null
             and exists (
               select 1 from app.lesson_snapshot_participants participant
               where participant.lesson_id = lesson.id
             )
             and not exists (
               select 1 from app.lesson_snapshot_participants participant
               where participant.lesson_id = lesson.id
                 and not exists (
                   select 1 from app.lesson_participant_exclusions exclusion
                   where exclusion.lesson_id = participant.lesson_id
                     and exclusion.student_id = participant.student_id
                 )
             )
           )
         )
       order by lesson.id for update of lesson`,
      [planIds, ref.type, ref.id],
    );
    const lessonIds = candidates.rows.map((lesson) => lesson.id);
    if (lessonIds.length > 0) {
      await client.query(
        `update app.lessons set lifecycle_state = 'cancelled', updated_at = now()
         where id = any($1::uuid[])
           and lifecycle_state in ('scheduled', 'settlement_pending')`,
        [lessonIds],
      );
      await client.query(
        `insert into app.lesson_transitions (
           lesson_id, from_state, to_state, reason_code, reason_text,
           actor_user_id, financial_decision
         )
         select item.id, item.from_state, 'cancelled', $2,
           'Архивирование клиента отменило повторяющееся действие', $3,
           '{"settlementTypeKey":"free_lesson","teacherCompensationRuleKey":"none"}'::jsonb
         from jsonb_to_recordset($1::jsonb)
           as item(id uuid, from_state text)`,
        [
          JSON.stringify(candidates.rows.map((lesson) => ({
            id: lesson.id,
            from_state: lesson.lifecycle_state,
          }))),
          "client.archive",
          actorUserId,
        ],
      );
      await client.query(
        `update app.lesson_reservations
         set state = 'released', financial_fact_id = null, updated_at = now()
         where lesson_id = any($1::uuid[]) and state = 'reserved'`,
        [lessonIds],
      );
      await client.query(
        `update app.lesson_settlement_plans
         set state = 'cancelled', version = version + 1, updated_at = now()
         where lesson_id = any($1::uuid[])
           and state in ('planned', 'review_required')`,
        [lessonIds],
      );
    }

    return {
      endedPlans: planIds.length,
      cancelledLessons: lessonIds.length,
      excludedGroupLessons,
    };
  }

  private assertCommand(dto: ArchiveClientCommandDto): void {
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "ARCHIVE_CONFIRMATION_REQUIRED",
        message: "Подтвердите архивирование после просмотра последствий.",
      });
    }
    if (!Number.isSafeInteger(dto.expectedVersion) || dto.expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "CLIENT_VERSION_REQUIRED",
        message: "Передайте актуальную версию карточки клиента.",
      });
    }
    if (!/^[A-Za-z0-9._:-]{1,120}$/.test(dto.reason)) {
      throw new UnprocessableEntityException({
        code: "ARCHIVE_REASON_REQUIRED",
        message: "Передайте безопасный код причины архивирования.",
      });
    }
  }

  private async readSnapshot(ref: ClientRefDto): Promise<ArchiveSnapshot> {
    const result = await this.database.query<ArchiveSnapshotRow>(
      `
        with target as (
          select
            'lead'::text as type,
            lead.id,
            coalesce(
              nullif(btrim(coalesce(lead.first_name, '') || ' ' ||
                coalesce(lead.last_name, '')), ''),
              'Лид без имени'
            ) as label,
            lead.deleted_at,
            lead.version,
            conversion.student_id as related_student_id,
            null::uuid as related_lead_id
          from app.leads lead
          left join app.client_conversion_links conversion
            on conversion.lead_id = lead.id
          where $1::text = 'lead' and lead.id = $2

          union all

          select
            'student'::text as type,
            student.id,
            coalesce(
              nullif(btrim(coalesce(profile.first_name, '') || ' ' ||
                coalesce(profile.last_name, '')), ''),
              'Ученик без имени'
            ) as label,
            student.deleted_at,
            student.version,
            student.id as related_student_id,
            conversion.lead_id as related_lead_id
          from app.students student
          left join app.profiles profile on profile.id = student.profile_id
          left join app.client_conversion_links conversion
            on conversion.student_id = student.id
          where $1::text = 'student' and student.id = $2
        )
        select
          target.type,
          target.id,
          target.label,
          target.deleted_at,
          target.version,
          case
            when target.type = 'lead' and target.related_student_id is not null
              then 'student'
            when target.type = 'student' and target.related_lead_id is not null
              then 'lead'
          end as linked_type,
          case
            when target.type = 'lead' then target.related_student_id
            else target.related_lead_id
          end as linked_id,
          (
            select count(*)
            from app.user_crm_links link
            where link.entity_type::text = target.type
              and link.entity_id = target.id
              and link.deleted_at is null
          ) as linked_user_count,
          (
            select count(*)
            from app.lessons lesson
            where lesson.deleted_at is null
              and lesson.scheduled_at >= now()
              and lesson.status not in ('cancelled', 'completed')
              and (
                (target.type = 'lead' and lesson.lead_id = target.id)
                or (
                  target.related_student_id is not null
                  and (
                    lesson.student_id = target.related_student_id
                    or exists (
                      select 1
                      from app.lesson_snapshot_participants participant
                      where participant.lesson_id = lesson.id
                        and participant.student_id = target.related_student_id
                        and not exists (
                          select 1
                          from app.lesson_participant_exclusions exclusion
                          where exclusion.lesson_id = participant.lesson_id
                            and exclusion.student_id = participant.student_id
                        )
                    )
                    or exists (
                      select 1
                      from app.schedule_series series
                      join app.schedule_plan_participants participant
                        on participant.plan_id = series.plan_id
                       and participant.student_id = target.related_student_id
                       and participant.effective_from <= current_date
                       and (
                         participant.effective_until is null
                         or participant.effective_until >= current_date
                       )
                      where series.id = lesson.series_id
                        and series.deleted_at is null
                    )
                  )
                )
              )
          ) as future_lesson_count,
          (
            select count(*)
            from app.canonical_tasks task
            where task.deleted_at is null
              and task.status in ('open', 'todo', 'in_progress')
              and (
                (task.entity_type::text = target.type
                  and task.entity_id = target.id)
                or (
                  target.related_student_id is not null
                  and task.entity_type::text = 'student'
                  and task.entity_id = target.related_student_id
                )
              )
          ) as open_task_count,
          (
            select count(*)
            from app.subscriptions subscription
            where subscription.status = 'active'
              and (
                subscription.expires_at is null
                or subscription.expires_at >= current_date
              )
              and (
                subscription.student_id = target.related_student_id
                or (
                  target.type = 'lead'
                  and subscription.conversion_lead_id = target.id
                )
              )
          ) as active_subscription_count,
          (
            select count(*)
            from app.payments payment
            where payment.deleted_at is null
              and payment.student_id = target.related_student_id
          ) as payment_count,
          (
            select count(*)
            from app.expected_payments expected
            where expected.student_id = target.related_student_id
          ) as expected_payment_count,
          (
            select count(*)
            from app.account_adjustments adjustment
            where adjustment.deleted_at is null
              and adjustment.student_id = target.related_student_id
          ) as account_adjustment_count
        from target
        limit 1
      `,
      [ref.type, ref.id],
    );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException("Клиент не найден.");
    }
    const payments = Number(row.payment_count);
    const expectedPayments = Number(row.expected_payment_count);
    const accountAdjustments = Number(row.account_adjustment_count);
    return {
      ref: { type: row.type, id: row.id },
      label: row.label,
      lifecycleState: row.deleted_at ? "archived" : "active",
      tombstone: row.deleted_at !== null,
      archivedAt: row.deleted_at,
      version: Number(row.version),
      impact: {
        futureLessons: Number(row.future_lesson_count),
        openTasks: Number(row.open_task_count),
        activeSubscriptions: Number(row.active_subscription_count),
        financeFacts: payments + expectedPayments + accountAdjustments,
        payments,
        expectedPayments,
        accountAdjustments,
      },
      linkedUserCount: Number(row.linked_user_count),
      links:
        row.linked_type && row.linked_id
          ? [
              {
                rel:
                  row.linked_type === "student"
                    ? "convertedStudent"
                    : "sourceLead",
                ref: { type: row.linked_type, id: row.linked_id },
                href: `/crm/clients/resolve?type=${row.linked_type}&id=${row.linked_id}`,
              },
            ]
          : [],
    };
  }

  private warnings(impact: ArchiveImpact): ArchiveWarning[] {
    const warnings: ArchiveWarning[] = [];
    if (impact.futureLessons > 0) {
      warnings.push({
        code: "FUTURE_LESSONS_PRESERVED",
        count: impact.futureLessons,
        message:
          "Повторяющиеся действия будут отменены; разовые будущие занятия останутся в расписании.",
      });
    }
    if (impact.openTasks > 0) {
      warnings.push({
        code: "OPEN_TASKS_PRESERVED",
        count: impact.openTasks,
        message: "Открытые задачи останутся связанными с карточкой.",
      });
    }
    if (impact.activeSubscriptions > 0) {
      warnings.push({
        code: "ACTIVE_SUBSCRIPTIONS_PRESERVED",
        count: impact.activeSubscriptions,
        message: "Активные абонементы не будут отменены или удалены.",
      });
    }
    if (impact.financeFacts > 0) {
      warnings.push({
        code: "FINANCE_FACTS_PRESERVED",
        count: impact.financeFacts,
        message: "Финансовые факты останутся неизменными.",
      });
    }
    return warnings;
  }
}
