import {
  ConflictException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { ActorContext, isManagerOrAdminRole } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { RealtimeBus } from "../../realtime/realtime-bus";
import {
  ClientOperationalHistoryQueryDto,
  UpdateClientInternalNoteDto,
} from "../dto/client-internal-context.dto";
import { ClientRefType } from "../dto/client-ref.dto";
import { ClientReferenceService } from "./client-reference.service";

type ClientRef = { type: ClientRefType; id: string };

interface LineageRow {
  lead_id: string | null;
  student_id: string | null;
}

interface NoteRow extends LineageRow {
  id: string;
  body: string;
  version: number | string;
  updated_by: string;
  updated_by_name: string | null;
  updated_at: Date | string;
}

interface HistoryRow {
  id: string;
  action: string;
  reason: string | null;
  reason_text: string | null;
  metadata: Record<string, unknown> | null;
  before_ref: Record<string, unknown> | null;
  after_ref: Record<string, unknown> | null;
  actor_name: string;
  created_at: Date | string;
}

const HISTORY_ACTIONS = [
  "crm.subscription_purchased",
  "crm.subscription_issued",
  "crm.subscription_replaced",
  "crm.subscription_cancelled",
  "crm.payment_record_created",
  "crm.payment_record_transitioned",
  "crm.installment_payment_due",
  "crm.payment_reversed",
  "crm.payment_adjustment_recorded",
  "crm.lesson_rescheduled",
  "crm.lesson_cancelled",
  "crm.lesson_settled",
  "crm.lessons_bulk_transitioned",
  "crm.schedule_plan_ended",
  "crm.client_internal_note_changed",
  "crm.client_blacklisted",
  "crm.client_unblacklisted",
] as const;

const ACTION_LABELS: Record<string, string> = {
  "crm.subscription_purchased": "Абонемент куплен",
  "crm.subscription_issued": "Абонемент выдан",
  "crm.subscription_replaced": "Абонемент заменён",
  "crm.subscription_cancelled": "Абонемент отменён",
  "crm.payment_record_created": "Оплата добавлена",
  "crm.payment_record_transitioned": "Статус оплаты изменён",
  "crm.installment_payment_due": "Платёж рассрочки ожидает подтверждения",
  "crm.payment_reversed": "Оплата удалена из обычного учёта",
  "crm.payment_adjustment_recorded": "Возврат или корректировка",
  "crm.lesson_rescheduled": "Занятие перенесено",
  "crm.lesson_cancelled": "Занятие отменено",
  "crm.lesson_settled": "Занятие рассчитано",
  "crm.lessons_bulk_transitioned": "Занятия изменены",
  "crm.schedule_plan_ended": "Постоянное расписание завершено",
  "crm.client_internal_note_changed": "Общая заметка изменена",
  "crm.client_blacklisted": "Клиент добавлен в чёрный список",
  "crm.client_unblacklisted": "Клиент убран из чёрного списка",
};

@Injectable()
export class ClientInternalContextService {
  constructor(
    private readonly database: DatabaseService,
    private readonly references: ClientReferenceService,
    private readonly integrity: PlatformIntegrityRepository,
    private readonly realtime: RealtimeBus,
  ) {}

  async getNote(actor: ActorContext, ref: ClientRef) {
    await this.assertStaffScoped(actor, ref);
    const result = await this.database.query<NoteRow>(
      `${this.lineageCte()}
       select note.id, note.lead_id, note.student_id, note.body, note.version,
         note.updated_by,
         nullif(btrim(coalesce(profile.first_name, '') || ' ' ||
           coalesce(profile.last_name, '')), '') as updated_by_name,
         note.updated_at
       from lineage
       join app.client_internal_notes note
         on (lineage.lead_id is not null and note.lead_id = lineage.lead_id)
         or (lineage.student_id is not null and note.student_id = lineage.student_id)
       left join app.users actor_user
         on actor_user.id = note.updated_by and actor_user.deleted_at is null
       left join app.profiles profile
         on profile.user_id = actor_user.id and profile.deleted_at is null
       limit 1`,
      [ref.type, ref.id],
    );
    return this.noteDto(result.rows[0]);
  }

  async updateNote(
    actor: ActorContext,
    ref: ClientRef,
    dto: UpdateClientInternalNoteDto,
  ) {
    await this.assertStaffScoped(actor, ref);
    const body = dto.body.trim();
    const saved = await this.database.transaction(async (client) => {
      const lineageResult = await client.query<LineageRow>(
        `${this.lineageCte()} select lead_id, student_id from lineage`,
        [ref.type, ref.id],
      );
      const lineage = lineageResult.rows[0]!;
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1::uuid::text, 0))",
        [lineage.lead_id ?? lineage.student_id],
      );
      const currentResult = await client.query<NoteRow>(
        `select note.id, note.lead_id, note.student_id, note.body, note.version,
           note.updated_by, null::text as updated_by_name, note.updated_at
         from app.client_internal_notes note
         where ($1::uuid is not null and note.lead_id = $1)
            or ($2::uuid is not null and note.student_id = $2)
         for update`,
        [lineage.lead_id, lineage.student_id],
      );
      const current = currentResult.rows[0];
      const currentVersion = current ? Number(current.version) : 0;
      if (currentVersion !== dto.expectedVersion) {
        throw new ConflictException({
          code: "CLIENT_NOTE_STALE_VERSION",
          message: "Заметка уже изменена другим сотрудником.",
          current: this.noteDto(current),
        });
      }
      const next = current
        ? await client.query<NoteRow>(
            `update app.client_internal_notes
             set lead_id = coalesce(lead_id, $2),
                 student_id = coalesce(student_id, $3),
                 body = $4, version = version + 1,
                 updated_by = $5, updated_at = now()
             where id = $1
             returning id, lead_id, student_id, body, version, updated_by,
               null::text as updated_by_name, updated_at`,
            [current.id, lineage.lead_id, lineage.student_id, body, actor.userId],
          )
        : await client.query<NoteRow>(
            `insert into app.client_internal_notes (
               lead_id, student_id, body, updated_by
             ) values ($1, $2, $3, $4)
             returning id, lead_id, student_id, body, version, updated_by,
               null::text as updated_by_name, updated_at`,
            [lineage.lead_id, lineage.student_id, body, actor.userId],
          );
      const note = next.rows[0]!;
      await this.integrity.appendAudit(client, {
        actorUserId: actor.userId,
        action: "crm.client_internal_note_changed",
        entityType: "client_internal_note",
        entityId: note.id,
        requestId: `client-note:${note.id}:${note.version}`,
        reason: "client.internal-note.update",
        reasonText: "Общая заметка обновлена",
        beforeRef: { version: currentVersion, bodyLength: current?.body.length ?? 0 },
        afterRef: { version: Number(note.version), bodyLength: body.length },
        metadata: {
          leadId: lineage.lead_id,
          studentId: lineage.student_id,
        },
      });
      return note;
    });
    for (const [entity, id] of [
      ["lead", saved.lead_id],
      ["student", saved.student_id],
    ] as const) {
      if (id) this.realtime.emitCrmChanged({ entity, action: "updated", id });
    }
    return this.noteDto({ ...saved, updated_by_name: null });
  }

  async listOperationalHistory(
    actor: ActorContext,
    ref: ClientRef,
    query: ClientOperationalHistoryQueryDto,
  ) {
    await this.assertStaffScoped(actor, ref);
    const limit = Math.min(query.limit ?? 30, 100);
    const result = await this.database.query<HistoryRow>(
      `${this.lineageCte()},
       cursor_event as (
         select created_at, id from app.audit_events where id = $4::uuid
       )
       select audit.id, audit.action, audit.reason, audit.reason_text,
         audit.metadata, audit.before_ref, audit.after_ref,
         coalesce(
           nullif(btrim(coalesce(profile.first_name, '') || ' ' ||
             coalesce(profile.last_name, '')), ''),
           nullif(actor_user.full_name, ''),
           'Системный процесс'
         ) as actor_name,
         audit.created_at
       from app.audit_events audit
       cross join lineage
       left join app.users actor_user
         on actor_user.id = audit.actor_user_id and actor_user.deleted_at is null
       left join app.profiles profile
         on profile.user_id = actor_user.id and profile.deleted_at is null
       where audit.action = any($3::text[])
         and (
           audit.entity_type = 'client_internal_note' and exists (
             select 1 from app.client_internal_notes note
             where note.id::text = audit.entity_id
               and ((lineage.lead_id is not null and note.lead_id = lineage.lead_id)
                 or (lineage.student_id is not null and note.student_id = lineage.student_id))
           )
           or audit.entity_type = 'subscription' and exists (
             select 1 from app.subscriptions subscription
             where subscription.id::text = audit.entity_id
               and lineage.student_id is not null
               and (subscription.student_id = lineage.student_id
                 or subscription.payer_student_id = lineage.student_id)
           )
           or audit.entity_type = 'client_payment_record' and exists (
             select 1 from app.client_payment_records payment_record
             left join app.subscriptions subscription
               on subscription.id = payment_record.issued_subscription_id
             where payment_record.id::text = audit.entity_id
               and lineage.student_id is not null
               and (payment_record.student_id = lineage.student_id
                 or subscription.student_id = lineage.student_id
                 or subscription.payer_student_id = lineage.student_id)
           )
           or audit.entity_type = 'account_adjustment'
             and lineage.student_id is not null
             and audit.metadata ->> 'studentId' = lineage.student_id::text
           or audit.entity_type = 'lesson' and exists (
             select 1 from app.lessons lesson
             where lesson.id::text = audit.entity_id
               and ((lineage.lead_id is not null and lesson.lead_id = lineage.lead_id)
                 or (lineage.student_id is not null and lesson.student_id = lineage.student_id))
           )
           or audit.entity_type = 'lesson_batch' and exists (
             select 1
             from jsonb_array_elements(coalesce(audit.before_ref -> 'items', '[]'::jsonb)) item
             join app.lessons lesson on lesson.id::text = item ->> 'lessonId'
             where (lineage.lead_id is not null and lesson.lead_id = lineage.lead_id)
                or (lineage.student_id is not null and lesson.student_id = lineage.student_id)
           )
           or audit.entity_type = 'schedule_plan' and exists (
             select 1 from app.schedule_plans plan
             where plan.id::text = audit.entity_id
               and lineage.student_id is not null
               and (plan.student_id = lineage.student_id or exists (
                 select 1 from app.schedule_plan_participants participant
                 where participant.plan_id = plan.id
                   and participant.student_id = lineage.student_id
               ))
           )
           or audit.entity_type = 'lead'
             and lineage.lead_id is not null
             and audit.entity_id = lineage.lead_id::text
           or audit.entity_type = 'student'
             and lineage.student_id is not null
             and audit.entity_id = lineage.student_id::text
         )
         and (
           $4::uuid is null
           or (audit.created_at, audit.id) < (
             select created_at, id from cursor_event
           )
         )
       order by audit.created_at desc, audit.id desc
       limit $5`,
      [ref.type, ref.id, HISTORY_ACTIONS, query.cursor ?? null, limit + 1],
    );
    const hasMore = result.rows.length > limit;
    const rows = result.rows.slice(0, limit);
    return {
      items: rows.map((row) => this.historyDto(row)),
      nextCursor: hasMore ? rows.at(-1)!.id : null,
    };
  }

  private async assertStaffScoped(actor: ActorContext, ref: ClientRef) {
    if (!isManagerOrAdminRole(actor.role)) {
      throw new ForbiddenException("Внутренняя информация клиента недоступна.");
    }
    await this.references.resolve(actor, ref);
  }

  private lineageCte() {
    return `with lineage as (
      select
        case when $1::text = 'lead' then $2::uuid else conversion.lead_id end
          as lead_id,
        case when $1::text = 'student' then $2::uuid else conversion.student_id end
          as student_id
      from (select 1) seed
      left join app.client_conversion_links conversion
        on ($1::text = 'lead' and conversion.lead_id = $2::uuid)
        or ($1::text = 'student' and conversion.student_id = $2::uuid)
    )`;
  }

  private noteDto(row?: NoteRow) {
    return row
      ? {
          id: row.id,
          body: row.body,
          version: Number(row.version),
          updatedBy: row.updated_by,
          updatedByName: row.updated_by_name,
          updatedAt: row.updated_at,
        }
      : {
          id: null,
          body: "",
          version: 0,
          updatedBy: null,
          updatedByName: null,
          updatedAt: null,
        };
  }

  private historyDto(row: HistoryRow) {
    const metadata = row.metadata ?? {};
    const before = row.before_ref ?? {};
    const after = row.after_ref ?? {};
    const status = metadata["targetStatus"];
    const rawMetadataReason =
      typeof metadata["reason"] === "string"
        ? metadata["reason"].trim()
        : "";
    const metadataReason = /^\[(?:PRIVATE|PII|REDACTED)\]$/.test(
      rawMetadataReason,
    )
      ? ""
      : rawMetadataReason;
    const summary = status
      ? `Новый статус: ${this.paymentStatusLabel(String(status))}`
      : row.action === "crm.client_internal_note_changed"
        ? `Версия ${before["version"] ?? 0} → ${after["version"] ?? "—"}`
        : row.action === "crm.lessons_bulk_transitioned"
          ? `Изменено занятий: ${Array.isArray(before["items"]) ? before["items"].length : 0}`
          : null;
    return {
      id: row.id,
      actionKey: row.action,
      action: ACTION_LABELS[row.action] ?? "Действие с клиентом",
      reason:
        row.reason_text?.trim() ||
        metadataReason ||
        row.reason ||
        "Причина не указана",
      summary,
      actorName: row.actor_name,
      occurredAt: row.created_at,
    };
  }

  private paymentStatusLabel(status: string) {
    if (status === "paid") return "Оплачен";
    if (status === "posted_pending") return "Проведён, ожидает подтверждения";
    if (status === "unpaid") return "Не оплачен";
    return status;
  }
}
