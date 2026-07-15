import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext, UserRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { ListProfilesQuery } from "./dto/list-profiles.query";
import { UpdateProfileDto } from "./dto/update-profile.dto";
import { ProfileLinkingService } from "./profile-linking.service";
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

@Injectable()
export class ProfileService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: ProfilePolicy,
    private readonly linking: ProfileLinkingService,
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
      await this.linking.linkProfileByPhone(actor, profile, "auto_phone");
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
            p.phone_normalized as normalized_phone,
            count(*) over() as total
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
        ),
        limited_profiles as (
          select *
          from visible_profiles
          order by created_at desc, id desc
          limit $3
        ),
        linked_students as (
          select vp.user_id, s.id
          from limited_profiles vp
          join app.students s
            on s.profile_id = vp.id
           and s.deleted_at is null
          union
          select vp.user_id, s.id
          from limited_profiles vp
          join app.user_crm_links l
            on l.user_id = vp.user_id
           and l.entity_type = 'student'
           and l.deleted_at is null
          join app.students s
            on s.id = l.entity_id
           and s.deleted_at is null
        ),
        linked_students_count as (
          select user_id, count(*)::text as count
          from linked_students
          group by user_id
        ),
        linked_leads_count as (
          select vp.user_id, count(l.id)::text as count
          from limited_profiles vp
          left join app.user_crm_links l
            on l.user_id = vp.user_id
           and l.entity_type = 'lead'
           and l.deleted_at is null
          group by vp.user_id
        ),
        linked_teachers as (
          select vp.user_id, t.id
          from limited_profiles vp
          join app.teachers t
            on t.profile_id = vp.id
           and t.deleted_at is null
          union
          select vp.user_id, t.id
          from limited_profiles vp
          join app.user_crm_links l
            on l.user_id = vp.user_id
           and l.entity_type = 'teacher'
           and l.deleted_at is null
          join app.teachers t
            on t.id = l.entity_id
           and t.deleted_at is null
        ),
        linked_teachers_count as (
          select user_id, count(*)::text as count
          from linked_teachers
          group by user_id
        ),
        linked_staff as (
          select vp.user_id, sm.id
          from limited_profiles vp
          join app.staff_members sm
            on sm.profile_id = vp.id
           and sm.deleted_at is null
          union
          select vp.user_id, sm.id
          from limited_profiles vp
          join app.user_crm_links l
            on l.user_id = vp.user_id
           and l.entity_type = 'staff'
           and l.deleted_at is null
          join app.staff_members sm
            on sm.id = l.entity_id
           and sm.deleted_at is null
        ),
        linked_staff_count as (
          select user_id, count(*)::text as count
          from linked_staff
          group by user_id
        ),
        candidate_students_count as (
          select vp.user_id, count(s.id)::text as count
          from limited_profiles vp
          join app.profiles sp
            on sp.phone_normalized = vp.normalized_phone
           and sp.deleted_at is null
          join app.students s
            on s.profile_id = sp.id
           and s.deleted_at is null
          left join app.users su on su.id = sp.user_id and su.deleted_at is null
          where vp.normalized_phone is not null
            and vp.normalized_phone <> ''
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
          group by vp.user_id
        ),
        candidate_leads_count as (
          select vp.user_id, count(l.id)::text as count
          from limited_profiles vp
          join app.leads l
            on l.phone_normalized = vp.normalized_phone
           and l.deleted_at is null
          where vp.normalized_phone is not null
            and vp.normalized_phone <> ''
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
          group by vp.user_id
        ),
        candidate_teachers_count as (
          select vp.user_id, count(t.id)::text as count
          from limited_profiles vp
          join app.profiles tp
            on tp.phone_normalized = vp.normalized_phone
           and tp.deleted_at is null
          join app.teachers t
            on t.profile_id = tp.id
           and t.deleted_at is null
          left join app.users tu on tu.id = tp.user_id and tu.deleted_at is null
          where vp.normalized_phone is not null
            and vp.normalized_phone <> ''
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
          group by vp.user_id
        ),
        candidate_staff_count as (
          select vp.user_id, count(sm.id)::text as count
          from limited_profiles vp
          join app.profiles sp
            on sp.phone_normalized = vp.normalized_phone
           and sp.deleted_at is null
          join app.staff_members sm
            on sm.profile_id = sp.id
           and sm.deleted_at is null
          left join app.users su on su.id = sp.user_id and su.deleted_at is null
          where vp.normalized_phone is not null
            and vp.normalized_phone <> ''
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
          group by vp.user_id
        )
        select vp.id, vp.user_id, vp.email, vp.role, vp.first_name, vp.last_name,
          vp.phone, vp.dob, vp.avatar_file_id, vp.email_otp_2fa_enabled,
          vp.is_app_account, vp.phone_verified_at, vp.created_at, vp.updated_at,
          coalesce(lsc.count, '0') as linked_students_count,
          coalesce(llc.count, '0') as linked_leads_count,
          coalesce(ltc.count, '0') as linked_teachers_count,
          coalesce(lsfc.count, '0') as linked_staff_count,
          coalesce(csc.count, '0') as candidate_students_count,
          coalesce(clc.count, '0') as candidate_leads_count,
          coalesce(ctc.count, '0') as candidate_teachers_count,
          coalesce(csfc.count, '0') as candidate_staff_count,
          vp.total
        from limited_profiles vp
        left join linked_students_count lsc on lsc.user_id = vp.user_id
        left join linked_leads_count llc on llc.user_id = vp.user_id
        left join linked_teachers_count ltc on ltc.user_id = vp.user_id
        left join linked_staff_count lsfc on lsfc.user_id = vp.user_id
        left join candidate_students_count csc on csc.user_id = vp.user_id
        left join candidate_leads_count clc on clc.user_id = vp.user_id
        left join candidate_teachers_count ctc on ctc.user_id = vp.user_id
        left join candidate_staff_count csfc on csfc.user_id = vp.user_id
        order by vp.created_at desc, vp.id desc
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

  // Linked client cards (students/leads) for the Users section — returns ids so
  // the UI can open each card (the list query only returned counts before, KVA).
  async listProfileLinks(actor: ActorContext, profileId: string) {
    const profile = await this.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanListProfiles(actor);

    const result = await this.database.query<{
      entity_type: string;
      entity_id: string;
      name: string | null;
    }>(
      `
        with prof as (
          select id, user_id from app.profiles
          where id = $1 and deleted_at is null
        )
        select 'student' as entity_type, s.id::text as entity_id,
          nullif(btrim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')), '') as name
        from app.students s
        cross join prof
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        where s.deleted_at is null
          and (
            s.profile_id = prof.id
            or exists (
              select 1 from app.user_crm_links l
              where l.entity_type = 'student' and l.entity_id = s.id
                and l.user_id = prof.user_id and l.deleted_at is null
            )
          )
        union all
        select 'lead' as entity_type, ld.id::text as entity_id,
          nullif(btrim(coalesce(ld.first_name, '') || ' ' || coalesce(ld.last_name, '')), '') as name
        from app.leads ld
        cross join prof
        where ld.deleted_at is null
          and exists (
            select 1 from app.user_crm_links l
            where l.entity_type = 'lead' and l.entity_id = ld.id
              and l.user_id = prof.user_id and l.deleted_at is null
          )
        order by 1, 3
        limit 500
      `,
      [profileId],
    );

    return {
      items: result.rows.map((row) => ({
        entityType: row.entity_type,
        entityId: row.entity_id,
        name: row.name ?? "—",
      })),
    };
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

}
