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

interface HomeworkAccessRow {
  assigned_by: string | null;
  teacher_user_id: string | null;
  client_can_access: boolean;
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
      const homework = await this.loadHomeworkAccess(ownerId, actor.userId);
      if (!homework) throw new NotFoundException("Задание не найдено.");
      if (
        isManagerOrAdminRole(actor.role) ||
        homework.assigned_by === actor.userId ||
        homework.teacher_user_id === actor.userId ||
        homework.client_can_access
      ) {
        return actor.userId;
      }
      throw new NotFoundException("Задание не найдено.");
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
      const homework = await this.loadHomeworkAccess(
        file.owner_id,
        actor.userId,
      );
      if (homework) {
        if (homework.assigned_by === actor.userId) return;
        if (homework.teacher_user_id === actor.userId) return;
        if (homework.client_can_access) return;
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

  private async loadHomeworkAccess(
    homeworkId: string,
    userId: string,
  ): Promise<HomeworkAccessRow | null> {
    const result = await this.database.query<HomeworkAccessRow>(
      `
        select homework.assigned_by,
          teacher_profile.user_id as teacher_user_id,
          (
            exists (
              select 1
              from app.students student
              join app.profiles student_profile
                on student_profile.id = student.profile_id
               and student_profile.deleted_at is null
              where student.id = homework.student_id
                and student.deleted_at is null
                and student_profile.user_id = $2
            )
            or exists (
              select 1
              from app.user_crm_links student_link
              where student_link.user_id = $2
                and student_link.entity_type = 'student'
                and student_link.entity_id = homework.student_id
                and student_link.deleted_at is null
            )
            or exists (
              select 1
              from app.user_crm_links lead_link
              where lead_link.user_id = $2
                and lead_link.entity_type = 'lead'
                and lead_link.entity_id = homework.lead_id
                and lead_link.deleted_at is null
            )
            or exists (
              select 1
              from app.profiles account_profile
              join app.family_members account_member
                on account_member.entity_type = 'profile'
               and account_member.entity_id = account_profile.id
               and account_member.role in ('parent', 'payer')
               and account_member.deleted_at is null
              join app.families family
                on family.id = account_member.family_id
               and family.deleted_at is null
              join app.family_members subject_member
                on subject_member.family_id = family.id
               and subject_member.deleted_at is null
               and (
                 (subject_member.entity_type = 'student'
                   and subject_member.entity_id = homework.student_id)
                 or (subject_member.entity_type = 'lead'
                   and subject_member.entity_id = homework.lead_id)
               )
              where account_profile.user_id = $2
                and account_profile.deleted_at is null
            )
          ) as client_can_access
        from app.lesson_homeworks homework
        left join app.lessons lesson
          on lesson.id = homework.lesson_id and lesson.deleted_at is null
        left join app.teachers teacher
          on teacher.id = lesson.teacher_id and teacher.deleted_at is null
        left join app.profiles teacher_profile
          on teacher_profile.id = teacher.profile_id
         and teacher_profile.deleted_at is null
        where homework.id = $1 and homework.deleted_at is null
        limit 1
      `,
      [homeworkId, userId],
    );
    return result.rows[0] ?? null;
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
