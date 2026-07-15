import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerRole,
  isStaffRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

/**
 * Staff-side triage of administration chats: claim/assign, unassign, and
 * per-staff archive state. Distinct from the messaging aggregate — touches
 * only chat_inbox_state / chat_work_events / chats.assigned_to_user_id and
 * shares no message infrastructure.
 */
@Injectable()
export class ChatInboxService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: MessengerPolicy,
    private readonly realtime: RealtimeGateway,
    private readonly realtimeBus: RealtimeBus,
  ) {}

  // ponytail: 4-line policy wrapper copied from MessengerService; not worth a
  // shared util for one caller each.
  private async requireChat(actor: ActorContext, chatId: string) {
    const chat = await this.policy.getChatAccess(actor, chatId);
    if (!chat) throw new NotFoundException("Чат не найден.");
    return chat;
  }

  async archiveChat(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "administration") {
      throw new NotFoundException("Чат не найден.");
    }
    if (!isStaffRole(actor.role)) {
      throw new ForbiddenException("Только сотрудники могут архивировать чаты.");
    }
    await this.database.query(
      `insert into app.chat_inbox_state (chat_id, staff_user_id, archived_at)
       values ($1, $2, now())
       on conflict (chat_id, staff_user_id) do update set archived_at = now()`,
      [chatId, actor.userId],
    );
    this.realtime.publishUserEvent(actor.userId, "chat.updated", {
      id: chatId,
      archived: true,
    });
    return { success: true };
  }

  async unarchiveChat(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "administration") {
      throw new NotFoundException("Чат не найден.");
    }
    if (!isStaffRole(actor.role)) {
      throw new ForbiddenException("Только сотрудники могут разархивировать чаты.");
    }
    await this.database.query(
      `insert into app.chat_inbox_state (chat_id, staff_user_id, archived_at)
       values ($1, $2, null)
       on conflict (chat_id, staff_user_id) do update set archived_at = null`,
      [chatId, actor.userId],
    );
    this.realtime.publishUserEvent(actor.userId, "chat.updated", {
      id: chatId,
      archived: false,
    });
    return { success: true };
  }

  async assignChat(actor: ActorContext, chatId: string, userId?: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "administration") {
      throw new NotFoundException("Чат не найден.");
    }
    if (!isStaffRole(actor.role)) {
      throw new ForbiddenException("Только сотрудники могут брать чаты в работу.");
    }

    const targetUserId = userId ?? actor.userId;

    // Verify the target is a staff user
    const targetResult = await this.database.query<{ role: string }>(
      "select role from app.users where id = $1 and deleted_at is null limit 1",
      [targetUserId],
    );
    const targetRow = targetResult.rows[0];
    if (!targetRow) {
      throw new NotFoundException("Пользователь не найден.");
    }
    if (!isStaffRole(targetRow.role as never)) {
      throw new ForbiddenException("Чат можно назначить только сотруднику.");
    }

    this.policy.assertCanAssign(actor, chat);

    const event = await this.database.transaction(async (client) => {
      await client.query(
        "update app.chats set assigned_to_user_id = $2, assigned_at = now() where id = $1",
        [chatId, targetUserId],
      );
      const inserted = await client.query<{ id: string }>(
        `insert into app.chat_work_events (
           chat_id, actor_user_id, target_user_id, previous_assigned_user_id, action
         )
         values ($1, $2, $3, $4, 'claimed')
         returning id`,
        [chatId, actor.userId, targetUserId, chat.assignedToUserId ?? null],
      );
      return inserted.rows[0];
    });

    await this.audit.record({
      actor,
      action: "messenger.chat_claimed",
      entityType: "chat",
      entityId: chatId,
      metadata: {
        targetUserId,
        previousAssignedUserId: chat.assignedToUserId ?? null,
      },
    });

    this.realtime.publishAdminInboxEvent("chat.updated", {
      id: chatId,
      assignedTo: { id: targetUserId },
    });
    this.realtimeBus.emitCrmChanged({
      entity: "chat_work",
      action: "created",
      id: event.id,
    });

    return { success: true };
  }

  async unassignChat(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "administration") {
      throw new NotFoundException("Чат не найден.");
    }
    if (!isStaffRole(actor.role)) {
      throw new ForbiddenException("Только сотрудники могут снимать назначение.");
    }

    // Allowed for the current assignee or manager-tier
    const current = chat.assignedToUserId ?? null;
    if (!isManagerRole(actor.role) && current !== actor.userId) {
      throw new ForbiddenException("Недостаточно прав для снятия назначения.");
    }

    const event = await this.database.transaction(async (client) => {
      await client.query(
        "update app.chats set assigned_to_user_id = null, assigned_at = null where id = $1",
        [chatId],
      );
      const inserted = await client.query<{ id: string }>(
        `insert into app.chat_work_events (
           chat_id, actor_user_id, target_user_id, previous_assigned_user_id, action
         )
         values ($1, $2, null, $3, 'unassigned')
         returning id`,
        [chatId, actor.userId, current],
      );
      return inserted.rows[0];
    });

    await this.audit.record({
      actor,
      action: "messenger.chat_unassigned",
      entityType: "chat",
      entityId: chatId,
      metadata: { previousAssignedUserId: current },
    });

    this.realtime.publishAdminInboxEvent("chat.updated", {
      id: chatId,
      assignedTo: null,
    });
    this.realtimeBus.emitCrmChanged({
      entity: "chat_work",
      action: "created",
      id: event.id,
    });

    return { success: true };
  }
}
