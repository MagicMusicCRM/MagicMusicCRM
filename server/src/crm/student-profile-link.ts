import type { QueryResult, QueryResultRow } from "pg";

interface StudentProfileLinkExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

/**
 * Connect an existing Student to a newly registered app profile without
 * discarding identity data already stored in the Student card. Existing
 * non-null scalar values and existing custom-data keys win; the app profile
 * only fills gaps. The Student is then moved to the app profile so legacy
 * client read paths that still scope through students.profile_id keep working.
 */
export async function mergeAndAssignStudentProfile(
  executor: StudentProfileLinkExecutor,
  studentId: string,
  appProfileId: string,
): Promise<boolean> {
  const result = await executor.query<{ id: string }>(
    `with existing_profile as (
       select profile.first_name,
              profile.last_name,
              profile.phone,
              profile.dob,
              profile.avatar_file_id,
              profile.custom_data
         from app.students student
         join app.profiles profile
           on profile.id = student.profile_id
          and profile.deleted_at is null
        where student.id = $1
          and student.deleted_at is null
     ),
     merged_profile as (
       update app.profiles target
          set first_name = coalesce(existing.first_name, target.first_name),
              last_name = coalesce(existing.last_name, target.last_name),
              phone = coalesce(existing.phone, target.phone),
              dob = coalesce(existing.dob, target.dob),
              avatar_file_id = coalesce(
                existing.avatar_file_id,
                target.avatar_file_id
              ),
              custom_data = coalesce(target.custom_data, '{}'::jsonb)
                || coalesce(existing.custom_data, '{}'::jsonb),
              updated_at = now()
         from existing_profile existing
        where target.id = $2
          and target.deleted_at is null
        returning target.id
     )
     update app.students student
        set profile_id = merged.id,
            updated_at = now()
       from merged_profile merged
      where student.id = $1
        and student.deleted_at is null
      returning student.id`,
    [studentId, appProfileId],
  );
  return result.rows.length === 1;
}
