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

/** Users to notify about a student change: profile owner + manual links. */
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
      ) affected
      where user_id is not null
    `,
    [studentId],
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
        select lead_link.user_id
        from app.user_crm_links lead_link
        where lead_link.entity_type = 'lead'
          and lead_link.entity_id = $2
          and lead_link.deleted_at is null
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
      ) affected
      where user_id is not null
    `,
    [lesson.student_id, lesson.lead_id, lesson.group_id, lesson.teacher_id],
  );
  return (result?.rows ?? []).map((row) => row.user_id);
}
