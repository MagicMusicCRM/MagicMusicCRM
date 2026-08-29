import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext, UserRole } from "../common/security/actor-context";
import { normalizePhoneRu } from "../crm/phone.util";
import { mergeAndAssignStudentProfile } from "../crm/student-profile-link";
import { DatabaseService } from "../db/database.service";
import { LinkProfileCrmDto } from "./dto/link-profile-crm.dto";
import { ProfilePolicy } from "./profile.policy";

interface ProfileRow {
  id: string;
  user_id: string;
  email: string;
  role: UserRole;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  dob: Date | string | null;
  avatar_file_id: string | null;
  email_otp_2fa_enabled: boolean;
  is_app_account?: boolean;
  phone_verified_at?: Date | string | null;
  linked_students_count?: string;
  linked_leads_count?: string;
  linked_teachers_count?: string;
  linked_staff_count?: string;
  candidate_students_count?: string;
  candidate_leads_count?: string;
  candidate_teachers_count?: string;
  candidate_staff_count?: string;
  created_at: Date | string;
  updated_at: Date | string;
}

interface LinkCandidateRow {
  id: string;
  entity_type: "student" | "lead" | "teacher" | "staff";
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  email: string | null;
  status: string | null;
  created_at: Date | string;
}

interface LinkSummaryRow {
  linked_students_count: string;
  linked_leads_count: string;
  linked_teachers_count: string;
  linked_staff_count: string;
  candidate_students_count: string;
  candidate_leads_count: string;
  candidate_teachers_count: string;
  candidate_staff_count: string;
}

export interface LinkCandidateDto {
  id: string;
  entityType: "student" | "lead" | "teacher" | "staff";
  firstName: string | null;
  lastName: string | null;
  phone: string | null;
  email: string | null;
  status: string | null;
  createdAt: Date | string;
}

/**
 * Profile ↔ CRM-entity linking (app.user_crm_links). Owns the 4-way
 * student/lead/teacher/staff candidate discovery + link strategies, the
 * phone-auto-link sweep, and the link summary. Extracted from ProfileService
 * (B7) — the single place the "link a profile to its CRM identity" dispatch
 * lives. `findById`/`ProfileRow` are copied (ProfileService still owns them).
 */
@Injectable()
export class ProfileLinkingService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: ProfilePolicy,
  ) {}

  async listLinkCandidates(actor: ActorContext, profileId: string) {
    const profile = await this.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanListProfiles(actor);

    return {
      students: await this.findStudentCandidates(profile),
      leads: await this.findLeadCandidates(profile),
      teachers: await this.findTeacherCandidates(profile),
      staff: await this.findStaffCandidates(profile),
    };
  }

  async autoLinkByPhone(actor: ActorContext, profileId: string) {
    const profile = await this.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanListProfiles(actor);
    return this.linkProfileByPhone(actor, profile, "auto_phone");
  }

  async linkCrmEntity(
    actor: ActorContext,
    profileId: string,
    dto: LinkProfileCrmDto,
  ) {
    const profile = await this.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanListProfiles(actor);

    if (dto.entityType === "student") {
      await this.linkStudentToProfile(actor, profile, dto.entityId, "manual_phone");
    } else if (dto.entityType === "lead") {
      await this.linkLeadToProfile(actor, profile, dto.entityId, "manual_phone");
    } else if (dto.entityType === "teacher") {
      await this.linkTeacherToProfile(actor, profile, dto.entityId, "manual_phone");
    } else {
      await this.linkStaffToProfile(actor, profile, dto.entityId, "manual_phone");
    }

    return this.linkSummary(profile);
  }

  async linkProfileByPhone(
    actor: ActorContext,
    profile: ProfileRow,
    source: "auto_phone" | "manual_phone",
  ) {
    if (!this.normalizePhone(profile.phone)) {
      return this.linkSummary(profile);
    }

    const students = await this.findStudentCandidates(profile);
    if (profile.role === "client") {
      // A phone can legitimately be shared by a family. Client auto-linking
      // must therefore select only one unambiguous CRM identity and must never
      // attach a client account to Teacher/Staff records. Student wins over
      // Lead because it is the later lifecycle state.
      if (students.length === 1) {
        await this.linkStudentToProfile(
          actor,
          profile,
          students[0].id,
          source,
        );
        return this.linkSummary(profile);
      }
      if (students.length > 1) {
        return this.linkSummary(profile);
      }

      const leads = await this.findLeadCandidates(profile);
      if (leads.length === 1) {
        await this.linkLeadToProfile(actor, profile, leads[0].id, source);
      }
      return this.linkSummary(profile);
    }

    for (const student of students) {
      await this.linkStudentToProfile(actor, profile, student.id, source);
    }

    const leads = await this.findLeadCandidates(profile);
    for (const lead of leads) {
      await this.linkLeadToProfile(actor, profile, lead.id, source);
    }

    const teachers = await this.findTeacherCandidates(profile);
    for (const teacher of teachers) {
      await this.linkTeacherToProfile(actor, profile, teacher.id, source);
    }

    const staff = await this.findStaffCandidates(profile);
    for (const staffMember of staff) {
      await this.linkStaffToProfile(actor, profile, staffMember.id, source);
    }

    return this.linkSummary(profile);
  }

  private async findStudentCandidates(
    profile: ProfileRow,
  ): Promise<LinkCandidateDto[]> {
    const normalizedPhone = this.normalizePhone(profile.phone);
    if (!normalizedPhone) return [];

    const result = await this.database.query<LinkCandidateRow>(
      `
        select s.id,
          'student'::text as entity_type,
          sp.first_name,
          sp.last_name,
          sp.phone,
          su.email,
          s.status,
          s.created_at
        from app.students s
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.users su on su.id = sp.user_id and su.deleted_at is null
        where s.deleted_at is null
          and sp.phone_normalized = $2
          and s.profile_id is distinct from $3::uuid
          and (su.id is null or su.id = $1 or su.is_app_account = false)
          and not exists (
            select 1
            from app.user_crm_links target_link
            where target_link.entity_type = 'student'
              and target_link.entity_id = s.id
              and target_link.deleted_at is null
              and target_link.user_id = $1
          )
          and not exists (
            select 1
            from app.user_crm_links occupied
            where occupied.entity_type = 'student'
              and occupied.entity_id = s.id
              and occupied.deleted_at is null
              and occupied.user_id <> $1
          )
        order by s.created_at desc, s.id desc
        limit 50
      `,
      [profile.user_id, normalizedPhone, profile.id],
    );
    return result.rows.map((row) => this.toLinkCandidateDto(row));
  }

  private async findLeadCandidates(
    profile: ProfileRow,
  ): Promise<LinkCandidateDto[]> {
    const normalizedPhone = this.normalizePhone(profile.phone);
    if (!normalizedPhone) return [];

    const result = await this.database.query<LinkCandidateRow>(
      `
        select l.id,
          'lead'::text as entity_type,
          l.first_name,
          l.last_name,
          l.phone,
          l.email,
          ls.name as status,
          l.created_at
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where l.deleted_at is null
          and l.phone_normalized = $2
          and not exists (
            select 1
            from app.user_crm_links target_link
            where target_link.entity_type = 'lead'
              and target_link.entity_id = l.id
              and target_link.deleted_at is null
              and target_link.user_id = $1
          )
          and not exists (
            select 1
            from app.user_crm_links occupied
            where occupied.entity_type = 'lead'
              and occupied.entity_id = l.id
              and occupied.deleted_at is null
              and occupied.user_id <> $1
          )
        order by l.created_at desc, l.id desc
        limit 50
      `,
      [profile.user_id, normalizedPhone],
    );
    return result.rows.map((row) => this.toLinkCandidateDto(row));
  }

  private async findTeacherCandidates(
    profile: ProfileRow,
  ): Promise<LinkCandidateDto[]> {
    const normalizedPhone = this.normalizePhone(profile.phone);
    if (!normalizedPhone) return [];

    const result = await this.database.query<LinkCandidateRow>(
      `
        select t.id,
          'teacher'::text as entity_type,
          tp.first_name,
          tp.last_name,
          tp.phone,
          tu.email,
          t.status,
          t.created_at
        from app.teachers t
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.users tu on tu.id = tp.user_id and tu.deleted_at is null
        where t.deleted_at is null
          and tp.phone_normalized = $2
          and t.profile_id is distinct from $3::uuid
          and (tu.id is null or tu.id = $1 or tu.is_app_account = false)
          and not exists (
            select 1
            from app.user_crm_links target_link
            where target_link.entity_type = 'teacher'
              and target_link.entity_id = t.id
              and target_link.deleted_at is null
              and target_link.user_id = $1
          )
          and not exists (
            select 1
            from app.user_crm_links occupied
            where occupied.entity_type = 'teacher'
              and occupied.entity_id = t.id
              and occupied.deleted_at is null
              and occupied.user_id <> $1
          )
        order by t.created_at desc, t.id desc
        limit 50
      `,
      [profile.user_id, normalizedPhone, profile.id],
    );
    return result.rows.map((row) => this.toLinkCandidateDto(row));
  }

  private async findStaffCandidates(
    profile: ProfileRow,
  ): Promise<LinkCandidateDto[]> {
    const normalizedPhone = this.normalizePhone(profile.phone);
    if (!normalizedPhone) return [];

    const result = await this.database.query<LinkCandidateRow>(
      `
        select sm.id,
          'staff'::text as entity_type,
          sp.first_name,
          sp.last_name,
          sp.phone,
          su.email,
          sm.status,
          sm.created_at
        from app.staff_members sm
        left join app.profiles sp on sp.id = sm.profile_id and sp.deleted_at is null
        left join app.users su on su.id = sp.user_id and su.deleted_at is null
        where sm.deleted_at is null
          and sp.phone_normalized = $2
          and sm.profile_id is distinct from $3::uuid
          and (su.id is null or su.id = $1 or su.is_app_account = false)
          and not exists (
            select 1
            from app.user_crm_links target_link
            where target_link.entity_type = 'staff'
              and target_link.entity_id = sm.id
              and target_link.deleted_at is null
              and target_link.user_id = $1
          )
          and not exists (
            select 1
            from app.user_crm_links occupied
            where occupied.entity_type = 'staff'
              and occupied.entity_id = sm.id
              and occupied.deleted_at is null
              and occupied.user_id <> $1
          )
        order by sm.created_at desc, sm.id desc
        limit 50
      `,
      [profile.user_id, normalizedPhone, profile.id],
    );
    return result.rows.map((row) => this.toLinkCandidateDto(row));
  }

  private async linkStudentToProfile(
    actor: ActorContext,
    profile: ProfileRow,
    studentId: string,
    source: "auto_phone" | "manual_phone",
  ) {
    const normalizedPhone = this.normalizePhone(profile.phone);
    if (!normalizedPhone) {
      throw new BadRequestException("У пользователя не указан телефон.");
    }

    const candidate = await this.database.query<{ id: string }>(
      `
        select s.id
        from app.students s
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.users su on su.id = sp.user_id and su.deleted_at is null
        where s.id = $2
          and s.deleted_at is null
          and sp.phone_normalized = $3
          and (su.id is null or su.id = $1 or su.is_app_account = false)
          and not exists (
            select 1
            from app.user_crm_links occupied
            where occupied.entity_type = 'student'
              and occupied.entity_id = s.id
              and occupied.deleted_at is null
              and occupied.user_id <> $1
          )
        limit 1
      `,
      [profile.user_id, studentId, normalizedPhone],
    );
    if (!candidate.rows[0]) {
      throw new BadRequestException(
        "Ученик не найден или его телефон не совпадает с телефоном пользователя.",
      );
    }

    const assigned = await mergeAndAssignStudentProfile(
      this.database,
      studentId,
      profile.id,
    );
    if (!assigned) {
      throw new BadRequestException(
        "Карточка ученика изменилась во время привязки. Повторите попытку.",
      );
    }
    await this.insertCrmLink(
      actor,
      profile,
      "student",
      studentId,
      normalizedPhone,
      source,
    );
    await this.audit.record({
      actor,
      action: "profile.crm_student_linked",
      entityType: "profile",
      entityId: profile.id,
      metadata: { studentId, source },
    });
  }

  private async linkLeadToProfile(
    actor: ActorContext,
    profile: ProfileRow,
    leadId: string,
    source: "auto_phone" | "manual_phone",
  ) {
    const normalizedPhone = this.normalizePhone(profile.phone);
    if (!normalizedPhone) {
      throw new BadRequestException("У пользователя не указан телефон.");
    }

    const candidate = await this.database.query<{ id: string }>(
      `
        select l.id
        from app.leads l
        where l.id = $2
          and l.deleted_at is null
          and l.phone_normalized = $3
          and not exists (
            select 1
            from app.user_crm_links occupied
            where occupied.entity_type = 'lead'
              and occupied.entity_id = l.id
              and occupied.deleted_at is null
              and occupied.user_id <> $1
          )
        limit 1
      `,
      [profile.user_id, leadId, normalizedPhone],
    );
    if (!candidate.rows[0]) {
      throw new BadRequestException(
        "Лид не найден или его телефон не совпадает с телефоном пользователя.",
      );
    }

    await this.insertCrmLink(
      actor,
      profile,
      "lead",
      leadId,
      normalizedPhone,
      source,
    );
    await this.audit.record({
      actor,
      action: "profile.crm_lead_linked",
      entityType: "profile",
      entityId: profile.id,
      metadata: { leadId, source },
    });
  }

  private async linkTeacherToProfile(
    actor: ActorContext,
    profile: ProfileRow,
    teacherId: string,
    source: "auto_phone" | "manual_phone",
  ) {
    const normalizedPhone = this.normalizePhone(profile.phone);
    if (!normalizedPhone) {
      throw new BadRequestException("У пользователя не указан телефон.");
    }

    const candidate = await this.database.query<{ id: string }>(
      `
        select t.id
        from app.teachers t
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.users tu on tu.id = tp.user_id and tu.deleted_at is null
        where t.id = $2
          and t.deleted_at is null
          and tp.phone_normalized = $3
          and (tu.id is null or tu.id = $1 or tu.is_app_account = false)
          and not exists (
            select 1
            from app.user_crm_links occupied
            where occupied.entity_type = 'teacher'
              and occupied.entity_id = t.id
              and occupied.deleted_at is null
              and occupied.user_id <> $1
          )
        limit 1
      `,
      [profile.user_id, teacherId, normalizedPhone],
    );
    if (!candidate.rows[0]) {
      throw new BadRequestException(
        "Преподаватель не найден или его телефон не совпадает с телефоном пользователя.",
      );
    }

    await this.database.query(
      `
        update app.teachers
        set profile_id = $2,
            updated_at = now()
        where id = $1
          and deleted_at is null
      `,
      [teacherId, profile.id],
    );
    await this.insertCrmLink(
      actor,
      profile,
      "teacher",
      teacherId,
      normalizedPhone,
      source,
    );
    await this.audit.record({
      actor,
      action: "profile.crm_teacher_linked",
      entityType: "profile",
      entityId: profile.id,
      metadata: { teacherId, source },
    });
  }

  private async linkStaffToProfile(
    actor: ActorContext,
    profile: ProfileRow,
    staffId: string,
    source: "auto_phone" | "manual_phone",
  ) {
    const normalizedPhone = this.normalizePhone(profile.phone);
    if (!normalizedPhone) {
      throw new BadRequestException("У пользователя не указан телефон.");
    }

    const candidate = await this.database.query<{ id: string }>(
      `
        select sm.id
        from app.staff_members sm
        left join app.profiles sp on sp.id = sm.profile_id and sp.deleted_at is null
        left join app.users su on su.id = sp.user_id and su.deleted_at is null
        where sm.id = $2
          and sm.deleted_at is null
          and sp.phone_normalized = $3
          and (su.id is null or su.id = $1 or su.is_app_account = false)
          and not exists (
            select 1
            from app.user_crm_links occupied
            where occupied.entity_type = 'staff'
              and occupied.entity_id = sm.id
              and occupied.deleted_at is null
              and occupied.user_id <> $1
          )
        limit 1
      `,
      [profile.user_id, staffId, normalizedPhone],
    );
    if (!candidate.rows[0]) {
      throw new BadRequestException(
        "Сотрудник не найден или его телефон не совпадает с телефоном пользователя.",
      );
    }

    await this.database.query(
      `
        update app.staff_members
        set profile_id = $2,
            updated_at = now()
        where id = $1
          and deleted_at is null
      `,
      [staffId, profile.id],
    );
    await this.insertCrmLink(
      actor,
      profile,
      "staff",
      staffId,
      normalizedPhone,
      source,
    );
    await this.audit.record({
      actor,
      action: "profile.crm_staff_linked",
      entityType: "profile",
      entityId: profile.id,
      metadata: { staffId, source },
    });
  }

  private async insertCrmLink(
    actor: ActorContext,
    profile: ProfileRow,
    entityType: "student" | "lead" | "teacher" | "staff",
    entityId: string,
    normalizedPhone: string,
    source: "auto_phone" | "manual_phone",
  ) {
    if (entityType === "student" || entityType === "lead") {
      const aggregateTable =
        entityType === "student" ? "app.students" : "app.leads";
      await this.database.query(
        `
          with target as (
            select id, version
            from ${aggregateTable}
            where id = $3::uuid and deleted_at is null
            for update
          ), linked as (
            insert into app.user_crm_links (
              user_id,
              entity_type,
              entity_id,
              matched_phone,
              link_source,
              confirmed_at,
              created_by
            )
            select $1, $2::app.crm_entity_type, $3::uuid, $4, $5, now(), $6::uuid
            from target
            where not exists (
              select 1
              from app.user_crm_links existing
              where existing.user_id = $1
                and existing.entity_type = $2::app.crm_entity_type
                and existing.entity_id = $3::uuid
                and existing.deleted_at is null
            )
            returning entity_id
          ), bumped as (
            update ${aggregateTable} aggregate
            set version = target.version + 1, updated_at = now()
            from target, linked
            where aggregate.id = target.id
            returning aggregate.id
          )
          select id from bumped
        `,
        [
          profile.user_id,
          entityType,
          entityId,
          normalizedPhone,
          source,
          actor.userId,
        ],
      );
      return;
    }
    await this.database.query(
      `
        insert into app.user_crm_links (
          user_id,
          entity_type,
          entity_id,
          matched_phone,
          link_source,
          confirmed_at,
          created_by
        )
        select $1, $2::app.crm_entity_type, $3::uuid, $4, $5, now(), $6::uuid
        where not exists (
          select 1
          from app.user_crm_links existing
          where existing.user_id = $1
            and existing.entity_type = $2::app.crm_entity_type
            and existing.entity_id = $3::uuid
            and existing.deleted_at is null
        )
      `,
      [
        profile.user_id,
        entityType,
        entityId,
        normalizedPhone,
        source,
        actor.userId,
      ],
    );
  }

  private async linkSummary(profile: ProfileRow) {
    const result = await this.database.query<LinkSummaryRow>(
      `
        select
          (
            select count(distinct s.id)::text
            from app.students s
            left join app.user_crm_links l
              on l.entity_type = 'student'
             and l.entity_id = s.id
             and l.deleted_at is null
            where s.deleted_at is null
              and (s.profile_id = $1 or l.user_id = $2)
          ) as linked_students_count,
          (
            select count(*)::text
            from app.user_crm_links l
            where l.user_id = $2
              and l.entity_type = 'lead'
              and l.deleted_at is null
          ) as linked_leads_count,
          (
            select count(distinct t.id)::text
            from app.teachers t
            left join app.user_crm_links l
              on l.entity_type = 'teacher'
             and l.entity_id = t.id
             and l.deleted_at is null
            where t.deleted_at is null
              and (t.profile_id = $1 or l.user_id = $2)
          ) as linked_teachers_count,
          (
            select count(distinct sm.id)::text
            from app.staff_members sm
            left join app.user_crm_links l
              on l.entity_type = 'staff'
             and l.entity_id = sm.id
             and l.deleted_at is null
            where sm.deleted_at is null
              and (sm.profile_id = $1 or l.user_id = $2)
          ) as linked_staff_count,
          (
            select count(*)::text
            from app.students s
            left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
            left join app.users su on su.id = sp.user_id and su.deleted_at is null
            where s.deleted_at is null
              and $3 <> ''
              and sp.phone_normalized = $3
              and s.profile_id is distinct from $1::uuid
              and (su.id is null or su.id = $2 or su.is_app_account = false)
              and not exists (
                select 1
                from app.user_crm_links target_link
                where target_link.entity_type = 'student'
                  and target_link.entity_id = s.id
                  and target_link.deleted_at is null
                  and target_link.user_id = $2
              )
              and not exists (
                select 1
                from app.user_crm_links occupied
                where occupied.entity_type = 'student'
                  and occupied.entity_id = s.id
                  and occupied.deleted_at is null
                  and occupied.user_id <> $2
              )
          ) as candidate_students_count,
          (
            select count(*)::text
            from app.leads l
            where l.deleted_at is null
              and $3 <> ''
              and l.phone_normalized = $3
              and not exists (
                select 1
                from app.user_crm_links target_link
                where target_link.entity_type = 'lead'
                  and target_link.entity_id = l.id
                  and target_link.deleted_at is null
                  and target_link.user_id = $2
              )
              and not exists (
                select 1
                from app.user_crm_links occupied
                where occupied.entity_type = 'lead'
                  and occupied.entity_id = l.id
                  and occupied.deleted_at is null
                  and occupied.user_id <> $2
              )
          ) as candidate_leads_count
          ,
          (
            select count(*)::text
            from app.teachers t
            left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
            left join app.users tu on tu.id = tp.user_id and tu.deleted_at is null
            where t.deleted_at is null
              and $3 <> ''
              and tp.phone_normalized = $3
              and t.profile_id is distinct from $1::uuid
              and (tu.id is null or tu.id = $2 or tu.is_app_account = false)
              and not exists (
                select 1
                from app.user_crm_links target_link
                where target_link.entity_type = 'teacher'
                  and target_link.entity_id = t.id
                  and target_link.deleted_at is null
                  and target_link.user_id = $2
              )
              and not exists (
                select 1
                from app.user_crm_links occupied
                where occupied.entity_type = 'teacher'
                  and occupied.entity_id = t.id
                  and occupied.deleted_at is null
                  and occupied.user_id <> $2
              )
          ) as candidate_teachers_count,
          (
            select count(*)::text
            from app.staff_members sm
            left join app.profiles sp on sp.id = sm.profile_id and sp.deleted_at is null
            left join app.users su on su.id = sp.user_id and su.deleted_at is null
            where sm.deleted_at is null
              and $3 <> ''
              and sp.phone_normalized = $3
              and sm.profile_id is distinct from $1::uuid
              and (su.id is null or su.id = $2 or su.is_app_account = false)
              and not exists (
                select 1
                from app.user_crm_links target_link
                where target_link.entity_type = 'staff'
                  and target_link.entity_id = sm.id
                  and target_link.deleted_at is null
                  and target_link.user_id = $2
              )
              and not exists (
                select 1
                from app.user_crm_links occupied
                where occupied.entity_type = 'staff'
                  and occupied.entity_id = sm.id
                  and occupied.deleted_at is null
                  and occupied.user_id <> $2
              )
          ) as candidate_staff_count
      `,
      [profile.id, profile.user_id, this.normalizePhone(profile.phone) ?? ""],
    );
    return {
      linkedStudents: Number(result.rows[0]?.linked_students_count ?? "0"),
      linkedLeads: Number(result.rows[0]?.linked_leads_count ?? "0"),
      linkedTeachers: Number(result.rows[0]?.linked_teachers_count ?? "0"),
      linkedStaff: Number(result.rows[0]?.linked_staff_count ?? "0"),
      candidateStudents: Number(
        result.rows[0]?.candidate_students_count ?? "0",
      ),
      candidateLeads: Number(result.rows[0]?.candidate_leads_count ?? "0"),
      candidateTeachers: Number(
        result.rows[0]?.candidate_teachers_count ?? "0",
      ),
      candidateStaff: Number(result.rows[0]?.candidate_staff_count ?? "0"),
    };
  }

  private toLinkCandidateDto(row: LinkCandidateRow): LinkCandidateDto {
    return {
      id: row.id,
      entityType: row.entity_type,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      email: row.email,
      status: row.status,
      createdAt: row.created_at,
    };
  }

  // ponytail: findById copied from ProfileService (both need it — it owns the
  // profile CRUD, this owns linking). Small ProfileRow read.
  private async findById(profileId: string): Promise<ProfileRow | undefined> {
    const result = await this.database.query<ProfileRow>(
      `
        select p.id, p.user_id, u.email, u.role, p.first_name, p.last_name,
          p.phone, p.dob, p.avatar_file_id, p.email_otp_2fa_enabled,
          u.is_app_account, u.phone_verified_at,
          p.created_at, p.updated_at
        from app.profiles p
        join app.users u on u.id = p.user_id
        where p.id = $1 and p.deleted_at is null and u.deleted_at is null
        limit 1
      `,
      [profileId],
    );
    return result.rows[0];
  }

  private normalizePhone(phone: string | null | undefined): string | null {
    return normalizePhoneRu(phone).canonical;
  }
}
