import { DatabaseService } from "../db/database.service";

/**
 * Realtime-audience resolution shared across CRM services (B4 AudienceResolver).
 * Given an entity, return the set of app user ids that should receive a realtime
 * `crm.changed` event for it — the entity's own profile user plus any users
 * manually linked via app.user_crm_links (and, for groups/lessons, the teacher
 * and every enrolled student's audience).
 *
 * Free functions over DatabaseService rather than an injectable — no state, and
 * this way callers don't grow a constructor dependency just to fan out events.
 */

/** Users to notify: profile owner + manual links + parent/payer family accounts. */
export async function audienceForStudent(
  db: DatabaseService,
  studentId: string | null | undefined,
): Promise<string[]> {
  if (!studentId) return [];
  const result = await db.query<{ user_id: string }>(
    `
      select distinct user_id
      from (
        select p.user_id
        from app.students s
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where s.id = $1 and s.deleted_at is null and p.user_id is not null
        union
        select link.user_id
        from app.user_crm_links link
        where link.entity_type = 'student'
          and link.entity_id = $1
          and link.deleted_at is null
        union
        select account_profile.user_id
        from app.family_members student_member
        join app.families family
          on family.id = student_member.family_id and family.deleted_at is null
        join app.family_members account_member
          on account_member.family_id = family.id
         and account_member.entity_type = 'profile'
         and account_member.role in ('parent', 'payer')
         and account_member.deleted_at is null
        join app.profiles account_profile
          on account_profile.id = account_member.entity_id
         and account_profile.deleted_at is null
        where student_member.entity_type = 'student'
          and student_member.entity_id = $1
          and student_member.deleted_at is null
      ) affected
      where user_id is not null
    `,
    [studentId],
  );
  return (result?.rows ?? []).map((row) => row.user_id);
}

/**
 * Finance invalidation recipients for one student. Unlike the general CRM
 * audience, this resolver proves at the database boundary that every returned
 * room belongs to an active Client application account. A manually linked
 * Teacher/staff user must therefore never receive a finance.changed event.
 */
export async function clientFinanceAudienceForStudent(
  db: DatabaseService,
  studentId: string | null | undefined,
): Promise<string[]> {
  if (!studentId) return [];
  const result = await db.query<{ user_id: string }>(
    `
      select distinct candidate.user_id
      from (
        select profile.user_id
        from app.students student
        join app.profiles profile
          on profile.id = student.profile_id
         and profile.deleted_at is null
        where student.id = $1
          and student.deleted_at is null
          and profile.user_id is not null
        union
        select link.user_id
        from app.user_crm_links link
        where link.entity_type = 'student'
          and link.entity_id = $1
          and link.deleted_at is null
        union
        select account_profile.user_id
        from app.family_members student_member
        join app.families family
          on family.id = student_member.family_id
         and family.deleted_at is null
        join app.family_members account_member
          on account_member.family_id = family.id
         and account_member.entity_type = 'profile'
         and account_member.role in ('parent', 'payer')
         and account_member.deleted_at is null
        join app.profiles account_profile
          on account_profile.id = account_member.entity_id
         and account_profile.deleted_at is null
        where student_member.entity_type = 'student'
          and student_member.entity_id = $1
          and student_member.deleted_at is null
          and account_profile.user_id is not null
      ) candidate
      join app.users recipient
        on recipient.id = candidate.user_id
       and recipient.deleted_at is null
       and recipient.role = 'client'
       and recipient.is_app_account = true
      where candidate.user_id is not null
    `,
    [studentId],
  );
  return (result?.rows ?? []).map((row) => row.user_id);
}

/**
 * Users to notify about a homework mutation: the linked student/lead client
 * audience plus the teacher assigned to the homework's lesson. Staff receive
 * the same invalidation through the shared CRM room, so they do not need to be
 * enumerated here.
 */
export async function audienceForHomework(
  db: DatabaseService,
  homeworkId: string,
): Promise<string[]> {
  const result = await db.query<{ user_id: string }>(
    `
      select distinct user_id
      from (
        select student_profile.user_id
        from app.lesson_homeworks homework
        join app.students student
          on student.id = homework.student_id and student.deleted_at is null
        join app.profiles student_profile
          on student_profile.id = student.profile_id
         and student_profile.deleted_at is null
        where homework.id = $1
          and homework.deleted_at is null
          and student_profile.user_id is not null
        union
        select student_link.user_id
        from app.lesson_homeworks homework
        join app.user_crm_links student_link
          on student_link.entity_type = 'student'
         and student_link.entity_id = homework.student_id
         and student_link.deleted_at is null
        where homework.id = $1 and homework.deleted_at is null
        union
        select student_family_profile.user_id
        from app.lesson_homeworks homework
        join app.family_members student_member
          on student_member.entity_type = 'student'
         and student_member.entity_id = homework.student_id
         and student_member.deleted_at is null
        join app.families student_family
          on student_family.id = student_member.family_id
         and student_family.deleted_at is null
        join app.family_members student_account
          on student_account.family_id = student_family.id
         and student_account.entity_type = 'profile'
         and student_account.role in ('parent', 'payer')
         and student_account.deleted_at is null
        join app.profiles student_family_profile
          on student_family_profile.id = student_account.entity_id
         and student_family_profile.deleted_at is null
        where homework.id = $1 and homework.deleted_at is null
        union
        select lead_link.user_id
        from app.lesson_homeworks homework
        join app.user_crm_links lead_link
          on lead_link.entity_type = 'lead'
         and lead_link.entity_id = homework.lead_id
         and lead_link.deleted_at is null
        where homework.id = $1 and homework.deleted_at is null
        union
        select lead_family_profile.user_id
        from app.lesson_homeworks homework
        join app.family_members lead_member
          on lead_member.entity_type = 'lead'
         and lead_member.entity_id = homework.lead_id
         and lead_member.deleted_at is null
        join app.families lead_family
          on lead_family.id = lead_member.family_id
         and lead_family.deleted_at is null
        join app.family_members lead_account
          on lead_account.family_id = lead_family.id
         and lead_account.entity_type = 'profile'
         and lead_account.role in ('parent', 'payer')
         and lead_account.deleted_at is null
        join app.profiles lead_family_profile
          on lead_family_profile.id = lead_account.entity_id
         and lead_family_profile.deleted_at is null
        where homework.id = $1 and homework.deleted_at is null
        union
        select teacher_profile.user_id
        from app.lesson_homeworks homework
        join app.lessons lesson
          on lesson.id = homework.lesson_id and lesson.deleted_at is null
        join app.teachers teacher
          on teacher.id = lesson.teacher_id and teacher.deleted_at is null
        join app.profiles teacher_profile
          on teacher_profile.id = teacher.profile_id
         and teacher_profile.deleted_at is null
        where homework.id = $1
          and homework.deleted_at is null
          and teacher_profile.user_id is not null
      ) affected
      where user_id is not null
    `,
    [homeworkId],
  );
  return (result?.rows ?? []).map((row) => row.user_id);
}

/** Users to notify about a group change: teacher + members + members' links. */
export async function audienceForGroup(
  db: DatabaseService,
  groupId: string,
): Promise<string[]> {
  const result = await db.query<{ user_id: string }>(
    `
      select distinct user_id
      from (
        select tp.user_id
        from app.groups g
        join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
        join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where g.id = $1 and g.deleted_at is null and tp.user_id is not null
        union
        select sp.user_id
        from app.group_students gs
        join app.students s on s.id = gs.student_id and s.deleted_at is null
        join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        where gs.group_id = $1 and gs.left_at is null and sp.user_id is not null
        union
        select link.user_id
        from app.group_students gs
        join app.user_crm_links link
          on link.entity_type = 'student'
         and link.entity_id = gs.student_id
         and link.deleted_at is null
        where gs.group_id = $1 and gs.left_at is null
        union
        select account_profile.user_id
        from app.group_students gs
        join app.family_members student_member
          on student_member.entity_type = 'student'
         and student_member.entity_id = gs.student_id
         and student_member.deleted_at is null
        join app.families family
          on family.id = student_member.family_id and family.deleted_at is null
        join app.family_members account_member
          on account_member.family_id = family.id
         and account_member.entity_type = 'profile'
         and account_member.role in ('parent', 'payer')
         and account_member.deleted_at is null
        join app.profiles account_profile
          on account_profile.id = account_member.entity_id
         and account_profile.deleted_at is null
        where gs.group_id = $1 and gs.left_at is null
      ) affected
      where user_id is not null
    `,
    [groupId],
  );
  return (result?.rows ?? []).map((row) => row.user_id);
}

/**
 * Users to notify about a lesson change: the lesson's student (+ links), its
 * lead (via links), its teacher, and — for group lessons — every enrolled
 * student's audience.
 */
export async function audienceForLesson(
  db: DatabaseService,
  lesson: {
    student_id: string | null;
    group_id: string | null;
    lead_id: string | null;
    teacher_id: string | null;
  },
): Promise<string[]> {
  const result = await db.query<{ user_id: string }>(
    `
      select distinct user_id
      from (
        select p.user_id
        from app.students s
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where s.id = $1 and s.deleted_at is null and p.user_id is not null
        union
        select student_link.user_id
        from app.user_crm_links student_link
        where student_link.entity_type = 'student'
          and student_link.entity_id = $1
          and student_link.deleted_at is null
        union
        select student_family_profile.user_id
        from app.family_members lesson_student_member
        join app.families lesson_student_family
          on lesson_student_family.id = lesson_student_member.family_id
         and lesson_student_family.deleted_at is null
        join app.family_members lesson_student_account
          on lesson_student_account.family_id = lesson_student_family.id
         and lesson_student_account.entity_type = 'profile'
         and lesson_student_account.role in ('parent', 'payer')
         and lesson_student_account.deleted_at is null
        join app.profiles student_family_profile
          on student_family_profile.id = lesson_student_account.entity_id
         and student_family_profile.deleted_at is null
        where lesson_student_member.entity_type = 'student'
          and lesson_student_member.entity_id = $1
          and lesson_student_member.deleted_at is null
        union
        select lead_link.user_id
        from app.user_crm_links lead_link
        where lead_link.entity_type = 'lead'
          and lead_link.entity_id = $2
          and lead_link.deleted_at is null
        union
        select lead_family_profile.user_id
        from app.family_members lesson_lead_member
        join app.families lesson_lead_family
          on lesson_lead_family.id = lesson_lead_member.family_id
         and lesson_lead_family.deleted_at is null
        join app.family_members lesson_lead_account
          on lesson_lead_account.family_id = lesson_lead_family.id
         and lesson_lead_account.entity_type = 'profile'
         and lesson_lead_account.role in ('parent', 'payer')
         and lesson_lead_account.deleted_at is null
        join app.profiles lead_family_profile
          on lead_family_profile.id = lesson_lead_account.entity_id
         and lead_family_profile.deleted_at is null
        where lesson_lead_member.entity_type = 'lead'
          and lesson_lead_member.entity_id = $2
          and lesson_lead_member.deleted_at is null
        union
        select tp.user_id
        from app.teachers t
        join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where t.id = $4 and t.deleted_at is null and tp.user_id is not null
        union
        select gp.user_id
        from app.group_students gs
        join app.students gs_student
          on gs_student.id = gs.student_id
         and gs_student.deleted_at is null
        join app.profiles gp
          on gp.id = gs_student.profile_id
         and gp.deleted_at is null
        where gs.group_id = $3 and gs.left_at is null and gp.user_id is not null
        union
        select group_link.user_id
        from app.group_students gs
        join app.user_crm_links group_link
          on group_link.entity_type = 'student'
         and group_link.entity_id = gs.student_id
         and group_link.deleted_at is null
        where gs.group_id = $3 and gs.left_at is null
        union
        select group_family_profile.user_id
        from app.group_students gs
        join app.family_members group_student_member
          on group_student_member.entity_type = 'student'
         and group_student_member.entity_id = gs.student_id
         and group_student_member.deleted_at is null
        join app.families group_family
          on group_family.id = group_student_member.family_id
         and group_family.deleted_at is null
        join app.family_members group_account_member
          on group_account_member.family_id = group_family.id
         and group_account_member.entity_type = 'profile'
         and group_account_member.role in ('parent', 'payer')
         and group_account_member.deleted_at is null
        join app.profiles group_family_profile
          on group_family_profile.id = group_account_member.entity_id
         and group_family_profile.deleted_at is null
        where gs.group_id = $3 and gs.left_at is null
      ) affected
      where user_id is not null
    `,
    [lesson.student_id, lesson.lead_id, lesson.group_id, lesson.teacher_id],
  );
  return (result?.rows ?? []).map((row) => row.user_id);
}
