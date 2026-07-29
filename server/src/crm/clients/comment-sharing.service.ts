import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";

interface CommentSharingRow {
  id: string;
  entity_type: string;
  entity_id: string;
  kind: string;
  shared_with_teacher: boolean;
  version: number | string;
}

export interface SetCommentSharingCommand {
  commentId: string;
  sharedWithTeacher: boolean;
  expectedVersion?: number;
  idempotencyKey: string;
  requestId: string;
  reasonCode: string;
}

@Injectable()
export class CommentSharingService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly realtime: RealtimeBus,
  ) {}

  async setTeacherSharing(
    actor: ActorContext,
    command: SetCommentSharingCommand,
  ) {
    if (!isManagerOrAdminRole(actor.role)) {
      throw new ForbiddenException({
        code: "COMMENT_SHARE_FORBIDDEN",
        message: "Only CRM staff may change teacher comment sharing.",
      });
    }
    if (!command.requestId || command.requestId.length > 128) {
      throw new BadRequestException({
        code: "REQUEST_ID_REQUIRED",
        message: "A bounded request id is required.",
      });
    }
    if (!command.idempotencyKey || command.idempotencyKey.length > 160) {
      throw new BadRequestException({
        code: "IDEMPOTENCY_KEY_REQUIRED",
        message: "A bounded idempotency key is required.",
      });
    }

    const expectedVersion =
      command.expectedVersion ??
      (await this.readCurrentVersion(command.commentId));
    const audit: {
      action: string;
      entityType: string;
      entityId: string;
      reason: string;
      beforeRef?: Record<string, unknown>;
      afterRef?: Record<string, unknown>;
      metadata: Record<string, unknown>;
    } = {
      action: "crm.comment_teacher_sharing_changed",
      entityType: "crm:comment",
      entityId: command.commentId,
      reason: command.reasonCode,
      metadata: { commentId: command.commentId },
    };

    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "crm.comment.teacher-sharing.set",
      idempotencyKey: command.idempotencyKey,
      payload: {
        commentId: command.commentId,
        sharedWithTeacher: command.sharedWithTeacher,
        reasonCode: command.reasonCode,
      },
      aggregateType: "crm:comment",
      aggregateId: command.commentId,
      expectedVersion,
      requestId: command.requestId,
      audit,
      outbox: {
        type: "crm.comment.teacher-sharing.changed",
        payload: {
          entityId: command.commentId,
          changedFields: ["sharedWithTeacher"],
        },
      },
      mutate: async (client, nextVersion) => {
        const comment = await this.lockComment(client, command.commentId);
        if (
          comment.kind !== "admin_comment" &&
          comment.kind !== "teacher_note"
        ) {
          throw new BadRequestException({
            code: "COMMENT_STREAM_NOT_SHAREABLE",
            message: "Only staff and teacher comment streams may be shared.",
          });
        }
        if (Number(comment.version) !== expectedVersion) {
          throw new ConflictException({
            code: "COMMENT_VERSION_DIVERGED",
            message: "Comment version is out of sync.",
            expectedVersion,
            currentVersion: Number(comment.version),
          });
        }

        audit.beforeRef = {
          sharedWithTeacher: comment.shared_with_teacher,
          version: Number(comment.version),
        };
        audit.afterRef = {
          sharedWithTeacher: command.sharedWithTeacher,
          version: nextVersion,
        };

        const updated = await client.query<CommentSharingRow>(
          `
            update app.entity_comments
               set shared_with_teacher = $2,
                   kind = case when $2 then 'teacher_note' else 'admin_comment' end,
                   version = $3
             where id = $1
               and deleted_at is null
               and version = $4
            returning id, entity_type, entity_id, kind,
              shared_with_teacher, version
          `,
          [
            command.commentId,
            command.sharedWithTeacher,
            nextVersion,
            expectedVersion,
          ],
        );
        const row = updated.rows[0];
        if (!row) {
          throw new ConflictException({
            code: "STALE_COMMENT_VERSION",
            message: "Comment changed while sharing was updated.",
          });
        }
        return {
          entityId: row.id,
          entityType: row.entity_type,
          ownerEntityId: row.entity_id,
          kind: row.kind,
          sharedWithTeacher: row.shared_with_teacher,
          version: Number(row.version),
        };
      },
    });

    if (!result.replayed) {
      this.realtime.emitCrmChanged({
        entity: "comment",
        action: "updated",
        id: command.commentId,
      });
    }
    return result;
  }

  private async readCurrentVersion(commentId: string): Promise<number> {
    const result = await this.database.query<{ version: number | string }>(
      `
        select version
        from app.entity_comments
        where id = $1 and deleted_at is null
      `,
      [commentId],
    );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException({
        code: "COMMENT_NOT_FOUND",
        message: "Comment was not found.",
      });
    }
    return Number(row.version);
  }

  private async lockComment(
    client: PoolClient,
    commentId: string,
  ): Promise<CommentSharingRow> {
    const result = await client.query<CommentSharingRow>(
      `
        select id, entity_type, entity_id, kind, shared_with_teacher, version
        from app.entity_comments
        where id = $1 and deleted_at is null
        for update
      `,
      [commentId],
    );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException({
        code: "COMMENT_NOT_FOUND",
        message: "Comment was not found.",
      });
    }
    return row;
  }
}
