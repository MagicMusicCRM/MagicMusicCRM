import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ConvertLeadDto } from "../dto/client-conversion.dto";
import { ClientConfigRepository } from "./client-config.repository";
import { ClientWriteValidator } from "./client-write.validator";

@Injectable()
export class ClientConversionService {
  constructor(
    private readonly database: DatabaseService,
    private readonly repository: ClientConfigRepository,
    private readonly validator: ClientWriteValidator,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
    private readonly realtime: RealtimeBus,
  ) {}

  async convert(
    actor: ActorContext,
    leadId: string,
    dto: ConvertLeadDto,
  ): Promise<{ leadId: string; studentId: string; replayed: boolean }> {
    this.policy.assertCanWriteCrm(actor);
    const outcome = await this.database.transaction(async (client) => {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1::uuid::text, 0))",
        [leadId],
      );
      const existing = await client.query<{ student_id: string }>(
        `
          select student_id
          from app.client_conversion_links
          where lead_id = $1
          limit 1
        `,
        [leadId],
      );
      if (existing.rows[0]) {
        return { studentId: existing.rows[0].student_id, replayed: true };
      }
      const leadResult = await client.query<{
        id: string;
        email: string | null;
        source_id: string | null;
        custom_data: Record<string, unknown> | null;
      }>(
        `
          select id, email, source_id, custom_data
          from app.leads
          where id = $1 and deleted_at is null
          for update
        `,
        [leadId],
      );
      const lead = leadResult.rows[0];
      if (!lead) throw new NotFoundException("Лид не найден.");
      const validated = await this.validator.validateStudentCreate(
        dto,
        lead.source_id,
      );
      const legacyCustomData = {
        ...(lead.custom_data ?? {}),
        sourceLeadId: leadId,
      };
      const fullName = `${validated.firstName} ${validated.lastName}`.trim();
      const student = await client.query<{ id: string }>(
        `
          with account as (
            insert into app.users (
              email, full_name, phone, role, profile_completed, is_app_account
            )
            values (
              'student-' || gen_random_uuid()::text || '@local.magicmusiccrm.invalid',
              $1, $2, 'client'::app.user_role, false, false
            )
            returning id
          ), profile as (
            insert into app.profiles (user_id, first_name, last_name, phone)
            select id, $3, $4, $2 from account
            returning id
          )
          insert into app.students (
            id, client_id, profile_id, lead_id, status, custom_data, branch_id,
            source_id, contact_email
          )
          select $5, $5, id, $5, $6, $7::jsonb, $8, $9, $10 from profile
          returning id, client_id
        `,
        [
          fullName,
          validated.phone,
          validated.firstName,
          validated.lastName,
          leadId,
          validated.status,
          JSON.stringify(legacyCustomData),
          validated.branchId,
          validated.sourceId,
          lead.email,
        ],
      );
      const studentId = student.rows[0]!.id;
      await this.repository.saveValues(
        client,
        "student",
        studentId,
        validated.customFields,
      );
      await client.query(
        `update app.client_custom_field_values value
         set entity_type = 'student', entity_id = $2, updated_at = now()
         where value.client_id = $1`,
        [leadId, studentId],
      );
      await client.query(
        `
          insert into app.user_crm_links (
            user_id, entity_type, entity_id, matched_phone,
            link_source, created_by, confirmed_at
          )
          select user_id, 'student', $2, matched_phone, link_source,
            coalesce(created_by, $3), coalesce(confirmed_at, now())
          from app.user_crm_links
          where entity_type = 'lead' and entity_id = $1 and deleted_at is null
          on conflict do nothing
        `,
        [leadId, studentId, actor.userId],
      );
      await client.query(
        `
          update app.chats
          set student_id = $2, lead_id = null, updated_at = now()
          where lead_id = $1 and deleted_at is null
        `,
        [leadId, studentId],
      );
      await client.query(
        `
          update app.lessons
          set student_id = $2, lead_id = null, updated_at = now()
          where lead_id = $1 and deleted_at is null
        `,
        [leadId, studentId],
      );
      await client.query(
        `
          update app.lesson_homeworks
          set student_id = $2, lead_id = null, updated_at = now()
          where lead_id = $1 and deleted_at is null
        `,
        [leadId, studentId],
      );
      await client.query(
        `
          update app.shared_tasks
          set linked_entity_type = 'student', linked_entity_id = $2,
              version = version + 1, updated_at = now()
          where linked_entity_type = 'lead'
            and linked_entity_id = $1 and deleted_at is null
        `,
        [leadId, studentId],
      );
      await client.query(
        `
          update app.entity_comments
          set entity_type = 'student', entity_id = $2
          where entity_type = 'lead' and entity_id = $1 and deleted_at is null
        `,
        [leadId, studentId],
      );
      await client.query(
        `
          insert into app.family_members (
            family_id, entity_type, entity_id, role, is_primary_contact
          )
          select family_id, 'student', $2, role, is_primary_contact
          from app.family_members
          where entity_type = 'lead' and entity_id = $1 and deleted_at is null
          on conflict (family_id, entity_type, entity_id)
          do update set deleted_at = null,
            role = excluded.role,
            is_primary_contact = excluded.is_primary_contact
        `,
        [leadId, studentId],
      );
      await client.query(
        `
          update app.family_members
          set deleted_at = now()
          where entity_type = 'lead' and entity_id = $1 and deleted_at is null
        `,
        [leadId],
      );
      await client.query(
        `
          insert into app.client_conversion_links (
            lead_id, student_id, converted_by
          )
          values ($1, $2, $3)
        `,
        [leadId, studentId, actor.userId],
      );
      await client.query(
        `update app.client_internal_notes
         set student_id = $2
         where lead_id = $1 and student_id is null`,
        [leadId, studentId],
      );
      await client.query(
        `update app.leads
            set version = version + 1, updated_at = now()
          where id = $1 and deleted_at is null`,
        [leadId],
      );
      return { studentId, replayed: false };
    });

    if (!outcome.replayed) {
      await this.audit.record({
        actor,
        action: "crm.lead_converted",
        entityType: "lead",
        entityId: leadId,
        metadata: { studentId: outcome.studentId },
      });
      this.realtime.emitCrmChanged({
        entity: "lead",
        action: "updated",
        id: leadId,
      });
      this.realtime.emitCrmChanged({
        entity: "student",
        action: "created",
        id: outcome.studentId,
      });
    }
    return { leadId, ...outcome };
  }
}
