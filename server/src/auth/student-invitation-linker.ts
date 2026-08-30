import { DatabaseService } from "../db/database.service";

/**
 * Claims only CRM students for which staff explicitly queued an invitation.
 * The caller must invoke this after email ownership has been verified.
 */
export async function linkInvitedStudentsByVerifiedEmail(
  database: DatabaseService,
  userId: string,
  email: string,
): Promise<string[]> {
  const linked = await database.query<{ entity_id: string }>(
    `
      insert into app.user_crm_links (
        user_id, entity_type, entity_id, link_source, confirmed_at
      )
      select $1, 'student', student.id, 'auto_email', now()
      from app.students student
      where student.deleted_at is null
        and lower(btrim(student.contact_email)) = lower($2)
        and exists (
          select 1
          from app.email_outbox invite
          where invite.recipient_student_id = student.id
            and invite.template = 'student_invite'
        )
      on conflict (entity_type, entity_id) where deleted_at is null
      do nothing
      returning entity_id
    `,
    [userId, email],
  );
  return linked.rows.map((row) => row.entity_id);
}
