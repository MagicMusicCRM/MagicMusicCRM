import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { ProfilePolicy } from "./profile.policy";
import {
  ProfileNoteProjection,
  ProfileNoteRow,
  ProfileRecordRepository,
} from "./profile-record.repository";

export interface ProfileNoteOperations {
  listProfileNotes(
    actor: ActorContext,
    profileId: string,
  ): Promise<{ items: ProfileNoteProjection[] }>;
  createProfileNote(
    actor: ActorContext,
    profileId: string,
    body: string,
  ): Promise<ProfileNoteProjection>;
}

@Injectable()
export class ProfileNotesService implements ProfileNoteOperations {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: ProfilePolicy,
    private readonly repository: ProfileRecordRepository,
  ) {}

  async listProfileNotes(actor: ActorContext, profileId: string) {
    const profile = await this.repository.findById(profileId);
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

    return {
      items: result.rows.map((row) => this.repository.toProfileNoteDto(row)),
    };
  }

  async createProfileNote(
    actor: ActorContext,
    profileId: string,
    body: string,
  ) {
    const profile = await this.repository.findById(profileId);
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

    return this.repository.toProfileNoteDto(note);
  }
}
