import { DatabaseService } from "../db/database.service";

/**
 * Shared student read model + lookup (B3 StudentRepository seed). Several CRM
 * services need to load a student for authorization/aggregation (card, finance,
 * groups, comments); rather than each re-implementing the join or depending on
 * the whole CrmService, they share this. A thin hand-written-SQL read — not an
 * ORM/DDD repository.
 */
export interface StudentRow {
  id: string;
  lead_id: string | null;
  status: string;
  custom_data: Record<string, unknown> | null;
  profile_id: string | null;
  profile_user_id: string | null;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  teacher_user_ids: string[] | null;
  created_at: Date | string;
  /** Чёрный список = бан на чаты. См. blacklist.ts. */
  blacklisted?: boolean | null;
  blacklist_reason?: string | null;
}

/** Load a non-deleted student with its profile identity + teacher user ids. */
export async function findStudent(
  db: DatabaseService,
  studentId: string,
): Promise<StudentRow | undefined> {
  const result = await db.query<StudentRow>(
    `
      select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
        s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason,
        p.first_name, p.last_name, u.email, p.phone, s.created_at,
        coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids
      from app.students s
      left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
      left join app.users u on u.id = p.user_id and u.deleted_at is null
      left join app.lessons l on l.student_id = s.id and l.deleted_at is null
      left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
      left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
      where s.id = $1 and s.deleted_at is null
      group by s.id, p.id, u.id
      limit 1
    `,
    [studentId],
  );
  return result.rows[0];
}
