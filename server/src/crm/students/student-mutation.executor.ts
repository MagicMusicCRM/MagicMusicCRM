import {
  ConflictException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  replaceTypedClientValues,
  saveTypedClientValues,
} from "../clients/client-config.repository";
import {
  applyEligibleResponsibleToCustomData,
  assertEligibleResponsible,
} from "../responsible-eligibility";
import type { StudentRow } from "../student-read";
import { StudentFunnelService } from "../student-funnel.service";
import type {
  PreparedStudentCreate,
  PreparedStudentUpdate,
  StudentWriteSnapshot,
} from "./student-mutation.types";

@Injectable()
export class StudentMutationExecutor {
  constructor(
    private readonly database: DatabaseService,
    private readonly studentFunnel: StudentFunnelService,
  ) {}

  create(command: PreparedStudentCreate): Promise<StudentRow> {
    return this.database.transaction((client) =>
      this.createInTransaction(client, command),
    );
  }

  update(command: PreparedStudentUpdate) {
    return this.database.transaction((client) =>
      this.updateInTransaction(client, command),
    );
  }

  private async createInTransaction(
    client: PoolClient,
    command: PreparedStudentCreate,
  ): Promise<StudentRow> {
    await this.studentFunnel.assertCreateStatus(
      client,
      command.branchId,
      command.status,
    );
    await this.lockLeadForConversion(client, command.leadId);
    const customData = await this.withEligibleResponsible(
      client,
      command.customDataPatch,
      command.requestedResponsibleId,
    );
    const student = await this.insertStudent(client, command, customData);
    await this.saveCreateCustomFields(client, student.id, command.customFields);
    return student;
  }

  private async lockLeadForConversion(
    client: PoolClient,
    leadId: string | null,
  ): Promise<void> {
    if (!leadId) return;
    await client.query(
      "select pg_advisory_xact_lock(hashtextextended($1::uuid::text, 0))",
      [leadId],
    );
    const existingStudent = await client.query<{ id: string }>(
      "select id from app.students where lead_id = $1 and deleted_at is null limit 1",
      [leadId],
    );
    if (existingStudent.rows[0]) {
      throw new ConflictException("Этот лид уже конвертирован в ученика.");
    }
  }

  private async withEligibleResponsible(
    client: PoolClient,
    customDataPatch: Readonly<Record<string, unknown>>,
    requestedResponsibleId: string | undefined,
  ): Promise<Record<string, unknown>> {
    const mutablePatch = { ...customDataPatch };
    if (!requestedResponsibleId) return mutablePatch;
    const responsible = await assertEligibleResponsible(
      client,
      requestedResponsibleId,
      { lock: true },
    );
    return applyEligibleResponsibleToCustomData(mutablePatch, responsible);
  }

  private async insertStudent(
    client: PoolClient,
    command: PreparedStudentCreate,
    customData: Record<string, unknown>,
  ): Promise<StudentRow> {
    const inserted = await client.query<StudentRow>(
      `
        with identity as (
          select coalesce($3::text, 'student-' || gen_random_uuid()::text || '@local.magicmusiccrm.invalid') as email
        ),
        inserted_user as (
          insert into app.users (email, full_name, phone, role, profile_completed, is_app_account)
          select identity.email, $4, $5, 'client'::app.user_role, false, false
          from identity
          returning id, email
        ),
        inserted_profile as (
          insert into app.profiles (user_id, first_name, last_name, phone)
          select id, $1, $2, $5
          from inserted_user
          returning id, user_id, first_name, last_name, phone
        ),
        inserted_student as (
          insert into app.students (
            profile_id, status, lead_id, custom_data, branch_id, source_id
          )
          select id, $6, $7, $8::jsonb, $9::uuid, $10::uuid
          from inserted_profile
          returning id, status, profile_id, lead_id, source_id, custom_data, created_at,
            blacklisted, blacklist_reason
        ),
        inserted_student_link as (
          insert into app.user_crm_links (
            user_id, entity_type, entity_id, link_source, created_by, confirmed_at
          )
          select linked.user_id, 'student', s.id, 'manual_phone',
            linked.created_by, now()
          from inserted_student s
          join lateral (
            select ucl.user_id, ucl.created_by
            from app.user_crm_links ucl
            where ucl.entity_type = 'lead'
              and ucl.entity_id = s.lead_id
              and ucl.deleted_at is null
            order by ucl.confirmed_at desc nulls last, ucl.created_at desc
            limit 1
          ) linked on true
          where s.lead_id is not null
          on conflict do nothing
          returning entity_id
        )
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.source_id, source.display_name as source_name,
          s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          '{}'::uuid[] as teacher_user_ids
        from inserted_student s
        join inserted_profile p on p.id = s.profile_id
        join inserted_user u on u.id = p.user_id
        left join app.lead_sources source on source.id = s.source_id
        limit 1
      `,
      [
        command.firstName,
        command.lastName,
        command.email,
        command.fullName,
        command.phone,
        command.status,
        command.leadId,
        JSON.stringify(customData),
        command.branchId,
        command.sourceId,
      ],
    );
    return inserted.rows[0]!;
  }

  private async saveCreateCustomFields(
    client: PoolClient,
    studentId: string,
    customFields: PreparedStudentCreate["customFields"],
  ): Promise<void> {
    if (customFields === undefined) return;
    await saveTypedClientValues(client, "student", studentId, [...customFields]);
  }

  private async updateInTransaction(
    client: PoolClient,
    command: PreparedStudentUpdate,
  ) {
    const beforeStudent = await this.lockStudentSnapshot(
      client,
      command.studentId,
    );
    await this.validateFunnel(client, beforeStudent, command);
    await this.validateSource(client, command.sourceId);
    const customData = await this.withEligibleResponsible(
      client,
      command.customDataPatch,
      beforeStudent ? command.requestedResponsibleId : undefined,
    );
    const student = await this.updateStudent(client, command, customData);
    await this.replaceUpdateCustomFields(client, command, student);
    await this.appendStatusHistory(client, command, beforeStudent, student);
    return { beforeStudent, student };
  }

  private async lockStudentSnapshot(
    client: PoolClient,
    studentId: string,
  ): Promise<StudentWriteSnapshot | null> {
    const result = await client.query<StudentWriteSnapshot>(
      `select s.status, s.branch_id, s.custom_data,
         p.first_name, p.last_name, p.phone, u.email
       from app.students s
       left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
       left join app.users u on u.id = p.user_id and u.deleted_at is null
       where s.id = $1 and s.deleted_at is null
       for update of s`,
      [studentId],
    );
    return result.rows[0] ?? null;
  }

  private async validateFunnel(
    client: PoolClient,
    beforeStudent: StudentWriteSnapshot | null,
    command: PreparedStudentUpdate,
  ): Promise<void> {
    if (!beforeStudent) return;
    if (command.status !== null) {
      await this.studentFunnel.assertTransition(
        client,
        command.branchId ?? beforeStudent.branch_id,
        beforeStudent.status,
        command.status,
      );
      return;
    }
    if (command.branchId && command.branchId !== beforeStudent.branch_id) {
      await this.studentFunnel.assertCreateStatus(
        client,
        command.branchId,
        beforeStudent.status ?? "",
      );
    }
  }

  private async validateSource(
    client: PoolClient,
    sourceId: string | null,
  ): Promise<void> {
    if (!sourceId) return;
    const source = await client.query<{ display_name: string }>(
      `select display_name from app.lead_sources
       where id = $1 and is_active and deleted_at is null limit 1`,
      [sourceId],
    );
    if (!source.rows[0]) {
      throw new UnprocessableEntityException({
        code: "SOURCE_INACTIVE",
        field: "sourceId",
        message: "Выберите активный источник.",
      });
    }
  }

  private async updateStudent(
    client: PoolClient,
    command: PreparedStudentUpdate,
    customData: Record<string, unknown>,
  ): Promise<StudentRow | undefined> {
    const updated = await client.query<StudentRow>(
      `
        with target as (
          select s.id, s.profile_id, p.user_id
          from app.students s
          left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
          where s.id = $1 and s.deleted_at is null
          limit 1
        ),
        updated_profile as (
          update app.profiles p
          set first_name = coalesce($2, p.first_name),
            last_name = coalesce($3, p.last_name),
            phone = coalesce($4, p.phone),
            updated_at = now()
          from target
          where p.id = target.profile_id
          returning p.id, p.user_id, p.first_name, p.last_name, p.phone
        ),
        updated_user as (
          update app.users u
          set email = coalesce($5, u.email),
            updated_at = now()
          from target
          where u.id = target.user_id
          returning u.id, u.email
        ),
        updated_student as (
          update app.students s
          set status = coalesce($6, s.status),
            custom_data = case when $9::boolean then
                (coalesce(s.custom_data, '{}'::jsonb) || $7::jsonb)
                  - 'responsible' - 'responsibleUserId' - 'responsibleName'
              else coalesce(s.custom_data, '{}'::jsonb) || $7::jsonb end,
            branch_id = coalesce($8::uuid, s.branch_id),
            source_id = coalesce($10::uuid, s.source_id),
            updated_at = now()
          from target
          where s.id = target.id
          returning s.id, s.status, s.profile_id, s.lead_id, s.source_id, s.custom_data,
            s.blacklisted, s.blacklist_reason, s.created_at
        )
        select us.id, us.status, us.profile_id,
          coalesce(updated_profile_dependency.user_id, p.user_id) as profile_user_id,
          us.lead_id, us.source_id, source.display_name as source_name,
          us.custom_data, us.blacklisted, us.blacklist_reason,
          coalesce(updated_profile_dependency.first_name, p.first_name) as first_name,
          coalesce(updated_profile_dependency.last_name, p.last_name) as last_name,
          coalesce(updated_user_dependency.email, u.email) as email,
          coalesce(updated_profile_dependency.phone, p.phone) as phone,
          us.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids
        from updated_student us
        join app.students s on s.id = us.id
        left join updated_profile updated_profile_dependency on true
        left join updated_user updated_user_dependency on true
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lead_sources source on source.id = us.source_id
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        group by us.id, us.status, us.profile_id, us.lead_id, us.source_id, us.custom_data,
          us.blacklisted, us.blacklist_reason, us.created_at, p.id, u.id,
          updated_profile_dependency.user_id,
          updated_profile_dependency.first_name,
          updated_profile_dependency.last_name,
          updated_profile_dependency.phone,
          updated_user_dependency.email, source.id
        limit 1
      `,
      [
        command.studentId,
        command.firstName,
        command.lastName,
        command.phone,
        command.email,
        command.status || null,
        JSON.stringify(customData),
        command.branchId,
        command.clearResponsible,
        command.sourceId,
      ],
    );
    return updated.rows[0];
  }

  private async replaceUpdateCustomFields(
    client: PoolClient,
    command: PreparedStudentUpdate,
    student: StudentRow | undefined,
  ): Promise<void> {
    if (!student || command.customFields === undefined) return;
    await replaceTypedClientValues(
      client,
      "student",
      command.studentId,
      [...command.customFields],
    );
  }

  private async appendStatusHistory(
    client: PoolClient,
    command: PreparedStudentUpdate,
    beforeStudent: StudentWriteSnapshot | null,
    student: StudentRow | undefined,
  ): Promise<void> {
    if (!student || !beforeStudent || beforeStudent.status === student.status) {
      return;
    }
    await client.query(
      `insert into app.student_status_history (student_id, status, branch_id)
       values ($1, $2, $3)`,
      [
        command.studentId,
        student.status,
        command.branchId ?? beforeStudent.branch_id,
      ],
    );
  }
}
