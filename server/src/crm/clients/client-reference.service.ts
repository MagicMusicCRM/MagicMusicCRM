import { Injectable, NotFoundException } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import {
  ClientRefDto,
  ClientRefSearchQuery,
  ClientRefType,
} from "../dto/client-ref.dto";

interface ClientReferenceRow {
  type: ClientRefType;
  id: string;
  label: string;
  deleted_at: Date | string | null;
  version: number | string;
  linked_type: ClientRefType | null;
  linked_id: string | null;
}

export interface ResolvedClientReference {
  ref: {
    type: ClientRefType;
    id: string;
  };
  label: string;
  lifecycleState: "active" | "archived";
  tombstone: boolean;
  archivedAt: Date | string | null;
  version: number;
  links: Array<{
    rel: "convertedStudent" | "sourceLead";
    ref: { type: ClientRefType; id: string };
    href: string;
  }>;
}

const MANAGEMENT_ROLES = ["admin", "manager", "director", "system_admin"];

/**
 * A single actor-scoped resolver for every cross-domain Lead/Student link.
 *
 * The projection deliberately contains no contact, finance or subscription
 * fields. Resource scope is applied inside the query, so an inaccessible UUID
 * is indistinguishable from a missing one.
 */
@Injectable()
export class ClientReferenceService {
  constructor(private readonly database: DatabaseService) {}

  async resolve(
    actor: ActorContext,
    ref: ClientRefDto,
  ): Promise<ResolvedClientReference> {
    const result = await this.database.query<ClientReferenceRow>(
      `
        ${this.candidatesCte()}
        select candidate.type, candidate.id, candidate.label,
          candidate.deleted_at, candidate.version,
          candidate.linked_type, candidate.linked_id
        from client_candidates candidate
        where candidate.type = $3
          and candidate.id = $4
          and ${this.actorScopeSql("candidate")}
        limit 1
      `,
      [actor.role, actor.userId, ref.type, ref.id],
    );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException("Клиент не найден.");
    }
    return this.toDto(row);
  }

  async search(actor: ActorContext, query: ClientRefSearchQuery) {
    const limit = Math.min(query.limit ?? 25, 50);
    const term = query.q?.trim().toLowerCase() || null;
    const escapedTerm = term?.replace(/[\\%_]/g, (value) => `\\${value}`) ?? null;
    const result = await this.database.query<ClientReferenceRow>(
      `
        ${this.candidatesCte()}
        select candidate.type, candidate.id, candidate.label,
          candidate.deleted_at, candidate.version,
          candidate.linked_type, candidate.linked_id
        from client_candidates candidate
        where ${this.actorScopeSql("candidate")}
          and ($3::text is null or candidate.type = $3)
          and ($4::boolean or candidate.deleted_at is null)
          and (
            $5::text is null
            or lower(candidate.label) like '%' || $5 || '%' escape '\\'
          )
        order by
          (candidate.deleted_at is not null) asc,
          lower(candidate.label) asc,
          candidate.type asc,
          candidate.id asc
        limit $6
      `,
      [
        actor.role,
        actor.userId,
        query.type ?? null,
        query.includeArchived ?? false,
        escapedTerm,
        limit,
      ],
    );
    return { items: result.rows.map((row) => this.toDto(row)) };
  }

  private candidatesCte(): string {
    return `
      with client_candidates as (
        select
          'student'::text as type,
          student.id,
          coalesce(
            nullif(
              btrim(
                coalesce(profile.first_name, '') || ' ' ||
                coalesce(profile.last_name, '')
              ),
              ''
            ),
            'Ученик без имени'
          ) as label,
          student.deleted_at,
          student.version,
          case when conversion.lead_id is null then null else 'lead' end
            as linked_type,
          conversion.lead_id as linked_id,
          profile.user_id as profile_user_id
        from app.students student
        left join app.profiles profile on profile.id = student.profile_id
        left join app.client_conversion_links conversion
          on conversion.student_id = student.id

        union all

        select
          'lead'::text as type,
          lead.id,
          coalesce(
            nullif(
              btrim(
                coalesce(lead.first_name, '') || ' ' ||
                coalesce(lead.last_name, '')
              ),
              ''
            ),
            'Лид без имени'
          ) as label,
          lead.deleted_at,
          lead.version,
          case when conversion.student_id is null then null else 'student' end
            as linked_type,
          conversion.student_id as linked_id,
          null::uuid as profile_user_id
        from app.leads lead
        left join app.client_conversion_links conversion
          on conversion.lead_id = lead.id
      )
    `;
  }

  private actorScopeSql(alias: string): string {
    return `
      (
        $1::text = any(array[${MANAGEMENT_ROLES.map((role) => `'${role}'`).join(", ")}]::text[])
        or (
          $1::text = 'client'
          and (
            (${alias}.type = 'student' and ${alias}.profile_user_id = $2::uuid)
            or exists (
              select 1
              from app.user_crm_links client_link
              where client_link.user_id = $2::uuid
                and client_link.entity_type::text = ${alias}.type
                and client_link.entity_id = ${alias}.id
                and client_link.deleted_at is null
            )
          )
        )
        or (
          $1::text = 'teacher'
          and (
            exists (
              select 1
              from app.tasks assigned_task
              where assigned_task.entity_type::text = ${alias}.type
                and assigned_task.entity_id = ${alias}.id
                and assigned_task.assigned_to = $2::uuid
                and assigned_task.deleted_at is null
            )
            or (
              ${alias}.type = 'student'
              and (
                exists (
                  select 1
                  from app.lessons assigned_lesson
                  join app.teachers assigned_teacher
                    on assigned_teacher.id = assigned_lesson.teacher_id
                  join app.profiles teacher_profile
                    on teacher_profile.id = assigned_teacher.profile_id
                  where assigned_lesson.student_id = ${alias}.id
                    and teacher_profile.user_id = $2::uuid
                    and assigned_lesson.deleted_at is null
                    and assigned_teacher.deleted_at is null
                    and teacher_profile.deleted_at is null
                )
                or exists (
                  select 1
                  from app.group_students membership
                  join app.groups assigned_group
                    on assigned_group.id = membership.group_id
                  join app.teachers group_teacher
                    on group_teacher.id = assigned_group.teacher_id
                  join app.profiles group_teacher_profile
                    on group_teacher_profile.id = group_teacher.profile_id
                  where membership.student_id = ${alias}.id
                    and membership.left_at is null
                    and group_teacher_profile.user_id = $2::uuid
                    and assigned_group.deleted_at is null
                    and group_teacher.deleted_at is null
                    and group_teacher_profile.deleted_at is null
                )
              )
            )
            or (
              ${alias}.type = 'lead'
              and exists (
                select 1
                from app.lessons assigned_lead_lesson
                join app.teachers lead_teacher
                  on lead_teacher.id = assigned_lead_lesson.teacher_id
                join app.profiles lead_teacher_profile
                  on lead_teacher_profile.id = lead_teacher.profile_id
                where assigned_lead_lesson.lead_id = ${alias}.id
                  and lead_teacher_profile.user_id = $2::uuid
                  and assigned_lead_lesson.deleted_at is null
                  and lead_teacher.deleted_at is null
                  and lead_teacher_profile.deleted_at is null
              )
            )
          )
        )
      )
    `;
  }

  private toDto(row: ClientReferenceRow): ResolvedClientReference {
    const tombstone = row.deleted_at !== null;
    return {
      ref: { type: row.type, id: row.id },
      label: row.label,
      lifecycleState: tombstone ? "archived" : "active",
      tombstone,
      archivedAt: row.deleted_at,
      version: Number(row.version),
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
}
