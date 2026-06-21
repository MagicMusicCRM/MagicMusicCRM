import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import {
  ActorContext,
  isAdminRole,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MessengerPolicy } from "../messenger/messenger.policy";
import { FilePurpose } from "./dto/upload-file.dto";

export interface FileAccessRecord {
  id: string;
  owner_user_id: string | null;
  owner_type: string | null;
  owner_id: string | null;
  purpose: FilePurpose;
  deleted_at: Date | string | null;
}

@Injectable()
export class FilesPolicy {
  constructor(
    private readonly database: DatabaseService,
    private readonly messengerPolicy: MessengerPolicy,
  ) {}

  async assertCanUpload(
    actor: ActorContext,
    purpose: FilePurpose,
    ownerType?: string,
    ownerId?: string,
  ): Promise<string | null> {
    if ((ownerType && !ownerId) || (!ownerType && ownerId)) {
      throw new ForbiddenException("Некорректная привязка файла.");
    }

    if (purpose === "chat_attachment" || purpose === "chat_voice") {
      if (ownerType !== "chat" || !ownerId) {
        throw new ForbiddenException("Для вложения требуется чат.");
      }
      const chat = await this.messengerPolicy.getChatAccess(actor, ownerId);
      if (!chat) throw new NotFoundException("Чат не найден.");
      this.messengerPolicy.assertCanWriteChat(actor, chat);
      return actor.userId;
    }

    if (purpose === "profile_avatar") {
      if (!ownerType && !ownerId) return actor.userId;
      if (ownerType !== "profile" || !ownerId) {
        throw new ForbiddenException("Некорректная привязка аватара.");
      }
      const profileOwner = await this.findProfileOwner(ownerId);
      if (!profileOwner) throw new NotFoundException("Профиль не найден.");
      if (profileOwner === actor.userId || isAdminRole(actor.role))
        return profileOwner;
      throw new ForbiddenException("Недостаточно прав для загрузки аватара.");
    }

    if (purpose === "legal_document" || purpose === "crm_document") {
      if (isManagerOrAdminRole(actor.role))
        return actor.userId;
      throw new ForbiddenException("Недостаточно прав для загрузки документа.");
    }

    if (purpose === "homework_attachment") {
      if (ownerType !== "homework" || !ownerId) {
        throw new ForbiddenException("Для вложения требуется задание.");
      }
      // The homework endpoint enforces homework ownership when linking.
      return actor.userId;
    }

    return actor.userId;
  }

  async assertCanRead(
    actor: ActorContext,
    file: FileAccessRecord,
  ): Promise<void> {
    if (file.deleted_at) throw new NotFoundException("Файл не найден.");
    if (file.owner_user_id === actor.userId) return;
    if (isManagerOrAdminRole(actor.role)) return;
    if (file.purpose === "legal_document") return;
    if (
      (file.purpose === "chat_attachment" || file.purpose === "chat_voice") &&
      file.owner_type === "chat" &&
      file.owner_id
    ) {
      const chat = await this.messengerPolicy.getChatAccess(
        actor,
        file.owner_id,
      );
      if (chat) {
        this.messengerPolicy.assertCanReadChat(actor, chat);
        return;
      }
    }
    if (
      file.purpose === "homework_attachment" &&
      file.owner_type === "homework" &&
      file.owner_id
    ) {
      // Manager/admin already returned above. Allow the assigning teacher or
      // the owning client; everyone else falls through to NotFound.
      const access = await this.database.query<{
        assigned_by: string | null;
        student_user_id: string | null;
      }>(
        `
          select lh.assigned_by, p.user_id as student_user_id
          from app.lesson_homeworks lh
          join app.students s on s.id = lh.student_id
          left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
          where lh.id = $1 and lh.deleted_at is null
          limit 1
        `,
        [file.owner_id],
      );
      const homework = access.rows[0];
      if (homework) {
        if (homework.assigned_by === actor.userId) return;
        if (homework.student_user_id === actor.userId) return;
      }
    }
    throw new NotFoundException("Файл не найден.");
  }

  assertCanDelete(actor: ActorContext, file: FileAccessRecord): void {
    if (file.deleted_at) throw new NotFoundException("Файл не найден.");
    if (file.owner_user_id === actor.userId) return;
    if (isAdminRole(actor.role)) return;
    throw new ForbiddenException("Недостаточно прав для удаления файла.");
  }

  private async findProfileOwner(
    profileId: string,
  ): Promise<string | undefined> {
    const result = await this.database.query<{ user_id: string }>(
      `
        select user_id
        from app.profiles
        where id = $1 and deleted_at is null
        limit 1
      `,
      [profileId],
    );
    return result.rows[0]?.user_id;
  }
}
