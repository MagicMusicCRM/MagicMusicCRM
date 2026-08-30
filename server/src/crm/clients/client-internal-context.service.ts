import {
  ConflictException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../../common/security/actor-context";
import { AuditPresentationService } from "../../audit/audit-presentation.service";
import { managerAdminRolesSql } from "../../common/security/role-sql";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { RealtimeBus } from "../../realtime/realtime-bus";
import {
  ClientOperationalHistoryQueryDto,
  UpdateClientInternalNoteDto,
} from "../dto/client-internal-context.dto";
import { ClientRefType } from "../dto/client-ref.dto";
import { currentActorRoleSql } from "../branch-scope";
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
  actor_id: string | null;
  actor_name: string;
  actor_role: string | null;
  target_type: string;
  target_id: string | null;
  target_display_name: string | null;
  created_at: Date | string;
}


@Injectable()
export class ClientInternalContextService {
  constructor(
    private readonly database: DatabaseService,
    private readonly references: ClientReferenceService,
    private readonly integrity: PlatformIntegrityRepository,
    private readonly realtime: RealtimeBus,
    private readonly presenter: AuditPresentationService = new AuditPresentationService(),
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
            [
              current.id,
              lineage.lead_id,
              lineage.student_id,
              body,
              actor.userId,
            ],
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
        beforeRef: {
          version: currentVersion,
          bodyLength: current?.body.length ?? 0,
        },
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
    const limit = Math.min(query.limit ?? 10, 100);
    const result = await this.database.query<HistoryRow>(
      `${this.lineageCte()},
       audit_history as (
         select audit.id, audit.action, audit.reason, audit.reason_text,
           audit.metadata, audit.before_ref, audit.after_ref,
           audit.actor_user_id as actor_id,
           coalesce(
             nullif(btrim(coalesce(profile.first_name, '') || ' ' ||
               coalesce(profile.last_name, '')), ''),
             nullif(actor_user.full_name, ''),
             'Системный процесс'
           ) as actor_name,
           actor_user.role as actor_role,
           coalesce(
             nullif(audit.metadata ->> 'targetType', ''),
             case audit.entity_type
               when 'crm:student' then 'student'
               when 'crm:lead' then 'lead'
               when 'crm:comment' then 'comment'
               when 'shared_task' then 'task'
               else audit.entity_type
             end
           ) as target_type,
           coalesce(nullif(audit.metadata ->> 'targetId', ''), audit.entity_id) as target_id,
           coalesce(
             nullif(audit.metadata ->> 'targetDisplayName', ''),
             nullif(audit.after_ref ->> 'displayName', ''),
             nullif(audit.after_ref ->> 'name', ''),
             nullif(audit.before_ref ->> 'displayName', ''),
             nullif(audit.before_ref ->> 'name', ''),
             nullif(btrim(concat_ws(' ', student_profile.first_name, student_profile.last_name)), ''),
             nullif(btrim(concat_ws(' ', target_lead.first_name, target_lead.last_name)), '')
           ) as target_display_name,
           audit.created_at
         from app.audit_events audit
         cross join lineage
         left join app.users actor_user
           on actor_user.id = audit.actor_user_id and actor_user.deleted_at is null
         left join app.profiles profile
           on profile.user_id = actor_user.id and profile.deleted_at is null
         left join app.students target_student
           on audit.entity_type in ('student', 'crm:student')
             and target_student.id::text = audit.entity_id
             and target_student.deleted_at is null
         left join app.profiles student_profile
           on student_profile.id = target_student.profile_id
             and student_profile.deleted_at is null
         left join app.leads target_lead
           on audit.entity_type in ('lead', 'crm:lead')
             and target_lead.id::text = audit.entity_id
             and target_lead.deleted_at is null
         where (audit.action like 'crm.%' or audit.action like 'workflow.%')
           and (
             audit.entity_type = 'client_internal_note' and exists (
               select 1 from app.client_internal_notes note
               where note.id::text = audit.entity_id
                 and ((lineage.lead_id is not null and note.lead_id = lineage.lead_id)
                   or (lineage.student_id is not null and note.student_id = lineage.student_id))
             )
             or audit.entity_type = 'crm:comment' and exists (
               select 1 from app.entity_comments comment
               where comment.id::text = audit.entity_id
                 and comment.deleted_at is null
                 and ((lineage.lead_id is not null
                       and comment.entity_type::text = 'lead'
                       and comment.entity_id = lineage.lead_id)
                   or (lineage.student_id is not null
                       and comment.entity_type::text = 'student'
                       and comment.entity_id = lineage.student_id))
             )
             or audit.entity_type = 'shared_task' and exists (
               select 1 from app.shared_tasks task
               where task.id::text = audit.entity_id
                 and task.deleted_at is null
                 and ((lineage.lead_id is not null
                       and task.linked_entity_type = 'lead'
                       and task.linked_entity_id = lineage.lead_id)
                   or (lineage.student_id is not null
                       and task.linked_entity_type = 'student'
                       and task.linked_entity_id = lineage.student_id))
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
       ),
       status_history as (
         select status_history.id,
           case
             when status_history.old_status_id is distinct from status_history.new_status_id
               and status_history.old_owner_id is distinct from status_history.new_owner_id
               then 'crm.lead_status_and_owner_changed'
             when status_history.old_status_id is distinct from status_history.new_status_id
               then 'crm.lead_status_changed'
             else 'crm.lead_owner_changed'
           end as action,
           null::text as reason,
           coalesce(
             nullif(btrim(status_history.comment), ''),
             nullif(btrim(status_history.reason_name_snapshot), '')
           ) as reason_text,
           '{}'::jsonb as metadata,
           jsonb_build_object(
             'status', old_status.name,
             'ownerName', coalesce(
               nullif(btrim(coalesce(old_owner_profile.first_name, '') || ' ' ||
                 coalesce(old_owner_profile.last_name, '')), ''),
               nullif(old_owner.full_name, '')
             )
           ) as before_ref,
           jsonb_build_object(
             'status', new_status.name,
             'ownerName', coalesce(
               nullif(btrim(coalesce(new_owner_profile.first_name, '') || ' ' ||
                 coalesce(new_owner_profile.last_name, '')), ''),
               nullif(new_owner.full_name, '')
             )
           ) as after_ref,
           status_history.changed_by as actor_id,
           coalesce(
             nullif(btrim(coalesce(actor_profile.first_name, '') || ' ' ||
               coalesce(actor_profile.last_name, '')), ''),
             nullif(actor_user.full_name, ''),
             'Системный процесс'
           ) as actor_name,
           actor_user.role as actor_role,
           'lead'::text as target_type,
           status_history.lead_id::text as target_id,
           nullif(btrim(concat_ws(' ', target_lead.first_name, target_lead.last_name)), '')
             as target_display_name,
           status_history.changed_at as created_at
         from app.lead_status_history status_history
         cross join lineage
         left join app.lead_statuses old_status
           on old_status.id = status_history.old_status_id
         left join app.lead_statuses new_status
           on new_status.id = status_history.new_status_id
         left join app.users old_owner
           on old_owner.id = status_history.old_owner_id and old_owner.deleted_at is null
         left join app.profiles old_owner_profile
           on old_owner_profile.user_id = old_owner.id and old_owner_profile.deleted_at is null
         left join app.users new_owner
           on new_owner.id = status_history.new_owner_id and new_owner.deleted_at is null
         left join app.profiles new_owner_profile
           on new_owner_profile.user_id = new_owner.id and new_owner_profile.deleted_at is null
         left join app.users actor_user
           on actor_user.id = status_history.changed_by and actor_user.deleted_at is null
         left join app.profiles actor_profile
           on actor_profile.user_id = actor_user.id and actor_profile.deleted_at is null
         left join app.leads target_lead
           on target_lead.id = status_history.lead_id and target_lead.deleted_at is null
         where lineage.lead_id is not null
           and status_history.lead_id = lineage.lead_id
       ),
       history_event as (
         select * from audit_history
         union all
         select * from status_history
       ),
       cursor_event as (
         select created_at, id from history_event where id = $3::uuid
       )
       select history.id, history.action, history.reason, history.reason_text,
         history.metadata, history.before_ref, history.after_ref,
         history.actor_id, history.actor_name, history.actor_role,
         history.target_type, history.target_id, history.target_display_name,
         history.created_at
       from history_event history
       where $3::uuid is null
         or (history.created_at, history.id) < (
           select created_at, id from cursor_event
         )
       order by history.created_at desc, history.id desc
       limit $4`,
      [ref.type, ref.id, query.cursor ?? null, limit + 1],
    );
    const hasMore = result.rows.length > limit;
    const rows = result.rows
      .filter((row) => this.presenter.isBusinessAction(row.action))
      .slice(0, limit);
    return {
      items: rows.map((row) =>
        this.presenter.present({
          id: row.id,
          actionKey: row.action,
          actor: {
            id: row.actor_id,
            name: row.actor_name,
            role: row.actor_role,
          },
          target: {
            type: row.target_type,
            id: row.target_id,
            displayName: row.target_display_name,
          },
          metadata: row.metadata,
          beforeRef: row.before_ref,
          afterRef: row.after_ref,
          reason: row.reason,
          reasonText: row.reason_text,
          occurredAt: row.created_at,
        }),
      ),
      nextCursor: hasMore ? rows.at(-1)!.id : null,
    };
  }

  private async assertStaffScoped(actor: ActorContext, ref: ClientRef) {
    if (!isManagerOrAdminRole(actor.role)) {
      throw new ForbiddenException("Внутренняя информация клиента недоступна.");
    }
    const currentAccess = await this.database.query<{ allowed: boolean }>(
      `select coalesce(
         ${managerAdminRolesSql(currentActorRoleSql("$1"))},
         false
       ) as allowed`,
      [actor.userId],
    );
    if (currentAccess.rows[0]?.allowed !== true) {
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

}
