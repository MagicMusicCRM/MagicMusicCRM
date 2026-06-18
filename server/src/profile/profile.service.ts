import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext, UserRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { LinkProfileCrmDto } from "./dto/link-profile-crm.dto";
import { ListProfilesQuery } from "./dto/list-profiles.query";
import { UpdateProfileDto } from "./dto/update-profile.dto";
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

interface CountRow {
  total: string;
}

interface ProfileNoteRow {
  id: string;
  profile_id: string;
  author_id: string | null;
  body: string;
  created_at: Date | string;
  author_email: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
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

@Injectable()
export class ProfileService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: ProfilePolicy,
  ) {}

  async getMe(actor: ActorContext) {
    let profile = await this.findByUserId(actor.userId);
    if (!profile) {
      await this.ensureProfile(actor.userId);
      profile = await this.findByUserId(actor.userId);
    }
    if (!profile) throw new NotFoundException("Профиль не найден.");
    return this.toProfileDto(profile);
  }

  async updateMe(actor: ActorContext, dto: UpdateProfileDto) {
    await this.ensureProfile(actor.userId);
    if (dto.avatarFileId) {
      await this.assertOwnAvatarFile(actor, dto.avatarFileId);
    }
    const firstName = dto.firstName?.trim() || null;
    const lastName = dto.lastName?.trim() || null;
    const phone = dto.phone?.trim() || null;
    const result = await this.database.query<ProfileRow>(
      `
        update app.profiles p
        set
          first_name = coalesce($2, p.first_name),
          last_name = coalesce($3, p.last_name),
          phone = coalesce($4, p.phone),
          dob = coalesce($5::date, p.dob),
          email_otp_2fa_enabled = coalesce($6, p.email_otp_2fa_enabled),
          avatar_file_id = coalesce($7::uuid, p.avatar_file_id),
          updated_at = now()
        from app.users u
        where p.user_id = u.id
          and p.user_id = $1
          and p.deleted_at is null
          and u.deleted_at is null
        returning p.id, p.user_id, u.email, u.role,
          p.first_name, p.last_name, p.phone,
          p.dob, p.avatar_file_id,
          p.email_otp_2fa_enabled, p.created_at,
          p.updated_at
      `,
      [
        actor.userId,
        firstName,
        lastName,
        phone,
        dto.dob ?? null,
        dto.emailOtp2faEnabled ?? null,
        dto.avatarFileId ?? null,
      ],
    );

    const profile = result.rows[0];
    if (!profile) throw new NotFoundException("Профиль не найден.");
    if (profile.first_name && profile.last_name && profile.phone) {
      await this.database.query(
        `
          update app.users
          set profile_completed = true,
              is_app_account = true,
              phone_verified_at = coalesce(phone_verified_at, now()),
              updated_at = now()
          where id = $1
            and deleted_at is null
        `,
        [actor.userId],
      );
      await this.linkProfileByPhone(actor, profile, "auto_phone");
    }

    await this.audit.record({
      actor,
      action: "profile.updated",
      entityType: "profile",
      entityId: profile.id,
    });

    return this.toProfileDto(profile);
  }

  async listProfiles(actor: ActorContext, query: ListProfilesQuery) {
    this.policy.assertCanListProfiles(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<ProfileRow & CountRow>(
      `
        with visible_profiles as (
          select p.id, p.user_id, u.email, u.role, p.first_name, p.last_name,
            p.phone, p.dob, p.avatar_file_id, p.email_otp_2fa_enabled,
            u.is_app_account, u.phone_verified_at,
            p.created_at, p.updated_at,
            ${this.normalizedPhoneSql("p.phone")} as normalized_phone
          from app.profiles p
          join app.users u on u.id = p.user_id
          where p.deleted_at is null
            and u.deleted_at is null
            and u.is_app_account = true
            and ($1::text is null or u.role = $1::app.user_role)
            and (
              $2::text is null
              or lower(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || u.email || ' ' || coalesce(p.phone, '')) like lower('%' || $2 || '%')
            )
        )
        select vp.id, vp.user_id, vp.email, vp.role, vp.first_name, vp.last_name,
          vp.phone, vp.dob, vp.avatar_file_id, vp.email_otp_2fa_enabled,
          vp.is_app_account, vp.phone_verified_at, vp.created_at, vp.updated_at,
          (
            select count(distinct s.id)::text
            from app.students s
            left join app.user_crm_links l
              on l.entity_type = 'student'
             and l.entity_id = s.id
             and l.deleted_at is null
            where s.deleted_at is null
              and (s.profile_id = vp.id or l.user_id = vp.user_id)
          ) as linked_students_count,
          (
            select count(*)::text
            from app.user_crm_links l
            where l.user_id = vp.user_id
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
              and (t.profile_id = vp.id or l.user_id = vp.user_id)
          ) as linked_teachers_count,
          (
            select count(distinct sm.id)::text
            from app.staff_members sm
            left join app.user_crm_links l
              on l.entity_type = 'staff'
             and l.entity_id = sm.id
             and l.deleted_at is null
            where sm.deleted_at is null
              and (sm.profile_id = vp.id or l.user_id = vp.user_id)
          ) as linked_staff_count,
          (
            select count(*)::text
            from app.students s
            left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
            left join app.users su on su.id = sp.user_id and su.deleted_at is null
            where s.deleted_at is null
              and vp.normalized_phone <> ''
              and ${this.normalizedPhoneSql("sp.phone")} = vp.normalized_phone
              and s.profile_id is distinct from vp.id
              and (su.id is null or su.id = vp.user_id or su.is_app_account = false)
              and not exists (
                select 1
                from app.user_crm_links target_link
                where target_link.entity_type = 'student'
                  and target_link.entity_id = s.id
                  and target_link.deleted_at is null
                  and target_link.user_id = vp.user_id
              )
              and not exists (
                select 1
                from app.user_crm_links occupied
                where occupied.entity_type = 'student'
                  and occupied.entity_id = s.id
                  and occupied.deleted_at is null
                  and occupied.user_id <> vp.user_id
              )
          ) as candidate_students_count,
          (
            select count(*)::text
            from app.leads l
            where l.deleted_at is null
              and vp.normalized_phone <> ''
              and ${this.normalizedPhoneSql("l.phone")} = vp.normalized_phone
              and not exists (
                select 1
                from app.user_crm_links target_link
                where target_link.entity_type = 'lead'
                  and target_link.entity_id = l.id
                  and target_link.deleted_at is null
                  and target_link.user_id = vp.user_id
              )
              and not exists (
                select 1
                from app.user_crm_links occupied
                where occupied.entity_type = 'lead'
                  and occupied.entity_id = l.id
                  and occupied.deleted_at is null
                  and occupied.user_id <> vp.user_id
              )
          ) as candidate_leads_count,
          (
            select count(*)::text
            from app.teachers t
            left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
            left join app.users tu on tu.id = tp.user_id and tu.deleted_at is null
            where t.deleted_at is null
              and vp.normalized_phone <> ''
              and ${this.normalizedPhoneSql("tp.phone")} = vp.normalized_phone
              and t.profile_id is distinct from vp.id
              and (tu.id is null or tu.id = vp.user_id or tu.is_app_account = false)
              and not exists (
                select 1
                from app.user_crm_links target_link
                where target_link.entity_type = 'teacher'
                  and target_link.entity_id = t.id
                  and target_link.deleted_at is null
                  and target_link.user_id = vp.user_id
              )
              and not exists (
                select 1
                from app.user_crm_links occupied
                where occupied.entity_type = 'teacher'
                  and occupied.entity_id = t.id
                  and occupied.deleted_at is null
                  and occupied.user_id <> vp.user_id
              )
          ) as candidate_teachers_count,
          (
            select count(*)::text
            from app.staff_members sm
            left join app.profiles sp on sp.id = sm.profile_id and sp.deleted_at is null
            left join app.users su on su.id = sp.user_id and su.deleted_at is null
            where sm.deleted_at is null
              and vp.normalized_phone <> ''
              and ${this.normalizedPhoneSql("sp.phone")} = vp.normalized_phone
              and sm.profile_id is distinct from vp.id
              and (su.id is null or su.id = vp.user_id or su.is_app_account = false)
              and not exists (
                select 1
                from app.user_crm_links target_link
                where target_link.entity_type = 'staff'
                  and target_link.entity_id = sm.id
                  and target_link.deleted_at is null
                  and target_link.user_id = vp.user_id
              )
              and not exists (
                select 1
                from app.user_crm_links occupied
                where occupied.entity_type = 'staff'
                  and occupied.entity_id = sm.id
                  and occupied.deleted_at is null
                  and occupied.user_id <> vp.user_id
              )
          ) as candidate_staff_count,
          count(*) over() as total
        from visible_profiles vp
        order by vp.created_at desc, vp.id desc
        limit $3
      `,
      [query.role ?? null, q || null, limit],
    );

    return {
      items: result.rows.map((row) => this.toProfileSummaryDto(row)),
      total: Number(result.rows[0]?.total ?? "0"),
    };
  }

  async getProfile(actor: ActorContext, profileId: string) {
    const profile = await this.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanReadProfile(actor, profile.user_id);
    return this.toProfileDto(profile);
  }

  async listProfileNotes(actor: ActorContext, profileId: string) {
    const profile = await this.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanListProfiles(actor);

    const result = await this.database.query<ProfileNoteRow>(
      `
        select n.id, n.profile_id, n.author_id, n.body, n.created_at,
          u.email as author_email,
          p.first_name as author_first_name,
          p.last_name as author_last_name
        from app.profile_notes n
        left join app.users u on u.id = n.author_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where n.profile_id = $1
          and n.deleted_at is null
        order by n.created_at desc, n.id desc
        limit 100
      `,
      [profileId],
    );

    return { items: result.rows.map((row) => this.toProfileNoteDto(row)) };
  }

  async createProfileNote(
    actor: ActorContext,
    profileId: string,
    body: string,
  ) {
    const profile = await this.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanListProfiles(actor);

    const normalizedBody = body.trim();
    if (!normalizedBody) {
      throw new BadRequestException("Заметка не может быть пустой.");
    }
    const result = await this.database.query<ProfileNoteRow>(
      `
        with inserted as (
          insert into app.profile_notes (profile_id, author_id, body)
          values ($1, $2, $3)
          returning id, profile_id, author_id, body, created_at
        )
        select inserted.id, inserted.profile_id, inserted.author_id,
          inserted.body, inserted.created_at,
          u.email as author_email,
          p.first_name as author_first_name,
          p.last_name as author_last_name
        from inserted
        left join app.users u on u.id = inserted.author_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
      `,
      [profileId, actor.userId, normalizedBody],
    );

    const note = result.rows[0];
    await this.audit.record({
      actor,
      action: "profile.note_created",
      entityType: "profile",
      entityId: profileId,
      metadata: { noteId: note.id },
    });

    return this.toProfileNoteDto(note);
  }

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

  async updateRole(actor: ActorContext, profileId: string, role: UserRole) {
    const profile = await this.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanUpdateRole(actor, profile.role, role);

    // Не допускаем потерю последнего активного администратора системы: если
    // снимаем роль system_admin с пользователя, должен остаться хотя бы один
    // другой активный system_admin. Иначе система останется без владельца.
    if (profile.role === "system_admin" && role !== "system_admin") {
      const remaining = await this.database.query<{ count: string }>(
        `
          select count(*)::text as count
          from app.users
          where role = 'system_admin'
            and deleted_at is null
            and id <> $1
        `,
        [profile.user_id],
      );
      if (Number(remaining.rows[0]?.count ?? "0") === 0) {
        throw new BadRequestException(
          "Нельзя снять роль с последнего администратора системы.",
        );
      }
    }

    await this.database.query(
      `
        update app.users
        set role = $2, updated_at = now()
        where id = $1 and deleted_at is null
      `,
      [profile.user_id, role],
    );

    await this.audit.record({
      actor,
      action: "profile.role_updated",
      entityType: "profile",
      entityId: profileId,
      metadata: { role },
    });

    const updated = await this.findById(profileId);
    if (!updated) throw new NotFoundException("Профиль не найден.");
    return this.toProfileDto(updated);
  }

  private async linkProfileByPhone(
    actor: ActorContext,
    profile: ProfileRow,
    source: "auto_phone" | "manual_phone",
  ) {
    if (!this.normalizePhone(profile.phone)) {
      return this.linkSummary(profile);
    }

    const students = await this.findStudentCandidates(profile);
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
          and ${this.normalizedPhoneSql("sp.phone")} = $2
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
          and ${this.normalizedPhoneSql("l.phone")} = $2
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
          and ${this.normalizedPhoneSql("tp.phone")} = $2
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
          and ${this.normalizedPhoneSql("sp.phone")} = $2
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
          and ${this.normalizedPhoneSql("sp.phone")} = $3
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

    await this.database.query(
      `
        update app.students
        set profile_id = $2,
            updated_at = now()
        where id = $1
          and deleted_at is null
      `,
      [studentId, profile.id],
    );
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
          and ${this.normalizedPhoneSql("l.phone")} = $3
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
          and ${this.normalizedPhoneSql("tp.phone")} = $3
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
          and ${this.normalizedPhoneSql("sp.phone")} = $3
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
              and ${this.normalizedPhoneSql("sp.phone")} = $3
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
              and ${this.normalizedPhoneSql("l.phone")} = $3
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
              and ${this.normalizedPhoneSql("tp.phone")} = $3
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
              and ${this.normalizedPhoneSql("sp.phone")} = $3
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

  private async ensureProfile(userId: string): Promise<void> {
    await this.database.query(
      `
        insert into app.profiles (user_id)
        values ($1)
        on conflict (user_id) do nothing
      `,
      [userId],
    );
  }

  private async assertOwnAvatarFile(
    actor: ActorContext,
    fileId: string,
  ): Promise<void> {
    const result = await this.database.query<{ id: string }>(
      `
        select id
        from app.file_objects
        where id = $1
          and owner_user_id = $2
          and purpose = 'profile_avatar'
          and deleted_at is null
        limit 1
      `,
      [fileId, actor.userId],
    );
    if (!result.rows[0]) throw new NotFoundException("Файл аватара не найден.");
  }

  private async findByUserId(userId: string): Promise<ProfileRow | undefined> {
    const result = await this.database.query<ProfileRow>(
      `
        select p.id, p.user_id, u.email, u.role, p.first_name, p.last_name,
          p.phone, p.dob, p.avatar_file_id, p.email_otp_2fa_enabled,
          u.is_app_account, u.phone_verified_at,
          p.created_at, p.updated_at
        from app.profiles p
        join app.users u on u.id = p.user_id
        where p.user_id = $1 and p.deleted_at is null and u.deleted_at is null
        limit 1
      `,
      [userId],
    );
    return result.rows[0];
  }

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

  private toProfileDto(row: ProfileRow) {
    return {
      id: row.id,
      userId: row.user_id,
      email: row.email,
      role: row.role,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      dob: row.dob,
      avatarFileId: row.avatar_file_id,
      emailOtp2faEnabled: row.email_otp_2fa_enabled,
      isAppAccount: row.is_app_account ?? true,
      phoneVerifiedAt: row.phone_verified_at ?? null,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private toProfileSummaryDto(row: ProfileRow) {
    return {
      id: row.id,
      userId: row.user_id,
      email: row.email,
      role: row.role,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      isAppAccount: row.is_app_account ?? true,
      phoneVerifiedAt: row.phone_verified_at ?? null,
      linkedStudents: Number(row.linked_students_count ?? "0"),
      linkedLeads: Number(row.linked_leads_count ?? "0"),
      linkedTeachers: Number(row.linked_teachers_count ?? "0"),
      linkedStaff: Number(row.linked_staff_count ?? "0"),
      candidateStudents: Number(row.candidate_students_count ?? "0"),
      candidateLeads: Number(row.candidate_leads_count ?? "0"),
      candidateTeachers: Number(row.candidate_teachers_count ?? "0"),
      candidateStaff: Number(row.candidate_staff_count ?? "0"),
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

  private toProfileNoteDto(row: ProfileNoteRow) {
    return {
      id: row.id,
      profileId: row.profile_id,
      authorId: row.author_id,
      body: row.body,
      createdAt: row.created_at,
      author: row.author_id
        ? {
            id: row.author_id,
            email: row.author_email,
            firstName: row.author_first_name,
            lastName: row.author_last_name,
          }
      : null,
    };
  }

  private normalizePhone(phone: string | null | undefined): string | null {
    const digits = phone?.replace(/\D/g, "") ?? "";
    if (!digits) return null;
    if (digits.length === 11 && digits.startsWith("8")) {
      return `7${digits.slice(1)}`;
    }
    return digits;
  }

  private normalizedPhoneSql(column: string): string {
    const digits = `regexp_replace(coalesce(${column}, ''), '[^0-9]', '', 'g')`;
    return `
      case
        when length(${digits}) = 11 and left(${digits}, 1) = '8'
          then '7' || substr(${digits}, 2)
        else ${digits}
      end
    `;
  }
}
