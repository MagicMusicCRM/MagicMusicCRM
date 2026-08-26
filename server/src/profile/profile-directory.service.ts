import { Injectable, NotFoundException } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { ListProfilesQuery } from "./dto/list-profiles.query";
import { ProfilePolicy } from "./profile.policy";
import {
  ProfileDtoProjection,
  ProfileRecordRepository,
  ProfileRow,
  ProfileSummaryProjection,
} from "./profile-record.repository";

interface CountRow {
  total: string;
}

export interface ProfileDirectoryOperations {
  listProfiles(
    actor: ActorContext,
    query: ListProfilesQuery,
  ): Promise<{ items: ProfileSummaryProjection[]; total: number }>;
  getProfile(
    actor: ActorContext,
    profileId: string,
  ): Promise<ProfileDtoProjection>;
  listProfileLinks(
    actor: ActorContext,
    profileId: string,
  ): Promise<{
    items: Array<{ entityType: string; entityId: string; name: string }>;
  }>;
}

@Injectable()
export class ProfileDirectoryService implements ProfileDirectoryOperations {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: ProfilePolicy,
    private readonly repository: ProfileRecordRepository,
  ) {}

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
            and ($4::text = 'system_admin' or u.role <> 'system_admin'::app.user_role)
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
      [query.role ?? null, q || null, limit, actor.role],
    );

    return {
      items: result.rows.map((row) =>
        this.repository.toProfileSummaryDto(row),
      ),
      total: Number(result.rows[0]?.total ?? "0"),
    };
  }

  async getProfile(actor: ActorContext, profileId: string) {
    const profile = await this.repository.findById(profileId);
    if (!profile) throw new NotFoundException("Профиль не найден.");
    this.policy.assertCanReadProfile(actor, profile.user_id);
    return this.repository.toProfileDto(profile);
  }

  async listProfileLinks(actor: ActorContext, profileId: string) {
    const profile = await this.repository.findById(profileId);
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
}
