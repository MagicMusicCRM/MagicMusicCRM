import { BadRequestException, NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { LeadIntakePort } from "../common/lead-intake.port";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { RealtimeBus } from "../realtime/realtime-bus";
import { MessageService } from "./message.service";
import { MessengerFanoutService } from "./messenger-fanout.service";
import { MessengerService } from "./messenger.service";
import { MessengerPolicy } from "./messenger.policy";
import { ReadReceiptService } from "./read-receipt.service";
import { RealtimeGateway } from "./realtime.gateway";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)
) {
  throw new Error("Direct chat integration tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("direct chat media lifecycle (PostgreSQL)", () => {
  let database: DatabaseService;
  let messenger: MessengerService;
  let messages: MessageService;
  let receipts: ReadReceiptService;
  let teacher: ActorContext;
  let manager: ActorContext;
  let outsider: ActorContext;
  let chatId: string;
  const userIds: string[] = [];
  const chatIds: string[] = [];
  const fileIds: string[] = [];

  const realtime = {
    publishChatEvent: jest.fn(),
    publishChannelEvent: jest.fn(),
    publishUserEvent: jest.fn(),
    publishAdminInboxEvent: jest.fn(),
  } as unknown as RealtimeGateway;
  const audit = {
    record: jest.fn().mockResolvedValue(undefined),
  } as unknown as AuditService;

  async function createUser(
    role: ActorContext["role"],
    name: string,
  ): Promise<ActorContext> {
    const result = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, $2::app.user_role, now())
        returning id
      `,
      [`uat-110-${randomUUID()}@example.test`, role],
    );
    const userId = result.rows[0]!.id;
    userIds.push(userId);
    await database.query(
      "insert into app.profiles (user_id, first_name) values ($1, $2)",
      [userId, name],
    );
    return { userId, role };
  }

  async function createDirectChat(memberIds: string[]): Promise<string> {
    const result = await database.query<{ id: string }>(
      `
        insert into app.chats (type, created_by)
        values ('direct', $1)
        returning id
      `,
      [memberIds[0]],
    );
    const id = result.rows[0]!.id;
    chatIds.push(id);
    for (const userId of memberIds) {
      await database.query(
        "insert into app.chat_members (chat_id, user_id) values ($1, $2)",
        [id, userId],
      );
    }
    return id;
  }

  async function createFile(input: {
    owner: ActorContext;
    purpose: "chat_attachment" | "chat_voice";
    mimeType: string;
    ownerChatId?: string;
  }): Promise<string> {
    const result = await database.query<{ id: string }>(
      `
        insert into app.file_objects (
          owner_user_id, owner_type, owner_id, purpose, original_name,
          mime_type, size_bytes, storage_key, sha256, created_by
        )
        values ($1, 'chat', $2, $3::app.file_purpose, $4, $5, 128, $6, $7, $1)
        returning id
      `,
      [
        input.owner.userId,
        input.ownerChatId ?? chatId,
        input.purpose,
        input.purpose === "chat_voice" ? "voice.webm" : "attachment.bin",
        input.mimeType,
        `uat-110/${randomUUID()}`,
        randomUUID().replaceAll("-", ""),
      ],
    );
    const id = result.rows[0]!.id;
    fileIds.push(id);
    return id;
  }

  beforeAll(async () => {
    const migrationPool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(migrationPool).up();
    } finally {
      await migrationPool.end();
    }
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    const policy = new MessengerPolicy(database);
    const fanout = new MessengerFanoutService(database, realtime);
    messenger = new MessengerService(
      database,
      audit,
      policy,
      realtime,
      {
        autoCreateLeadFromChat: jest.fn(),
      } as unknown as LeadIntakePort,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
      fanout,
    );
    messages = new MessageService(database, audit, policy, realtime, fanout);
    receipts = new ReadReceiptService(database, policy, realtime, fanout);

    teacher = await createUser("teacher", "Преподаватель");
    manager = await createUser("manager", "Управляющий");
    outsider = await createUser("admin", "Другой администратор");
    chatId = await createDirectChat([teacher.userId, manager.userId]);
  });

  afterAll(async () => {
    if (!database) return;
    if (chatIds.length > 0) {
      await database.query("delete from app.chats where id = any($1::uuid[])", [
        chatIds,
      ]);
    }
    if (fileIds.length > 0) {
      await database.query(
        "delete from app.file_objects where id = any($1::uuid[])",
        [fileIds],
      );
    }
    if (userIds.length > 0) {
      await database.query(
        "delete from app.audit_events where actor_user_id = any($1::uuid[])",
        [userIds],
      );
      await database.query("delete from app.users where id = any($1::uuid[])", [
        userIds,
      ]);
    }
    await database.onModuleDestroy();
  });

  it("persists text, image, file and voice and supports edit, reaction, pin, read and media delete", async () => {
    const imageFileId = await createFile({
      owner: teacher,
      purpose: "chat_attachment",
      mimeType: "image/png",
    });
    const documentFileId = await createFile({
      owner: teacher,
      purpose: "chat_attachment",
      mimeType: "application/pdf",
    });
    const voiceFileId = await createFile({
      owner: teacher,
      purpose: "chat_voice",
      mimeType: "audio/webm",
    });

    const text = await messenger.sendMessage(teacher, chatId, {
      content: "Первый текст",
    });
    const image = await messenger.sendMessage(teacher, chatId, {
      content: "Фото",
      messageType: "image",
      attachmentFileId: imageFileId,
    });
    await messenger.sendMessage(teacher, chatId, {
      content: "Документ",
      messageType: "file",
      attachmentFileId: documentFileId,
    });
    const voice = await messenger.sendMessage(teacher, chatId, {
      content: "Голосовое сообщение",
      messageType: "voice",
      attachmentFileId: voiceFileId,
      voiceDurationMs: 1_750,
    });

    await messages.updateMessage(teacher, text.id, {
      content: "Исправленный текст",
    });
    await messages.setReaction(manager, text.id, "👍");
    await messages.pinMessage(manager, text.id);
    await messages.unpinMessage(teacher, text.id);
    await messages.pinMessage(teacher, text.id);
    await receipts.markRead(manager, chatId, {
      lastReadMessageId: voice.id,
    });

    const listed = await messenger.getMessages(teacher, chatId, { limit: 20 });
    expect(listed.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: text.id,
          content: "Исправленный текст",
          pinnedAt: expect.any(Date),
          isRead: true,
          reactions: [{ emoji: "👍", count: 1, reactedByMe: false }],
        }),
        expect.objectContaining({
          id: image.id,
          messageType: "image",
          attachmentFileId: imageFileId,
        }),
        expect.objectContaining({
          id: voice.id,
          messageType: "voice",
          attachmentFileId: voiceFileId,
          voiceDurationMs: 1_750,
        }),
      ]),
    );

    const deleted = await messages.deleteMessage(teacher, image.id, {});
    expect(deleted).toMatchObject({
      id: image.id,
      content: null,
      attachmentFileId: null,
      deletedAt: expect.any(Date),
    });
  });

  it("rejects invalid media ownership, cross-chat references and dangling files without partial messages", async () => {
    const teacherVoiceId = await createFile({
      owner: teacher,
      purpose: "chat_voice",
      mimeType: "audio/webm",
    });
    const managerVoiceId = await createFile({
      owner: manager,
      purpose: "chat_voice",
      mimeType: "audio/webm",
    });
    const privateChatId = await createDirectChat([
      manager.userId,
      outsider.userId,
    ]);
    const source = await messenger.sendMessage(manager, privateChatId, {
      content: "Закрытый источник",
    });
    const before = await database.query<{ count: string }>(
      "select count(*)::text as count from app.messages where chat_id = $1",
      [chatId],
    );

    await expect(
      messenger.sendMessage(teacher, chatId, {
        messageType: "voice",
        attachmentFileId: teacherVoiceId,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      messenger.sendMessage(teacher, chatId, {
        messageType: "voice",
        attachmentFileId: managerVoiceId,
        voiceDurationMs: 500,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      messenger.sendMessage(teacher, chatId, {
        content: "Чужой ответ",
        replyToId: source.id,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      messenger.sendMessage(teacher, chatId, {
        content: "Чужая пересылка",
        forwardedFromId: source.id,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    const after = await database.query<{ count: string }>(
      "select count(*)::text as count from app.messages where chat_id = $1",
      [chatId],
    );
    expect(after.rows[0]!.count).toBe(before.rows[0]!.count);

    await expect(
      database.query(
        `
          insert into app.messages (
            chat_id, sender_id, content, message_type, attachment_file_id
          ) values ($1, $2, 'dangling', 'file', $3)
        `,
        [chatId, teacher.userId, randomUUID()],
      ),
    ).rejects.toMatchObject({ code: "23503" });
  });
});
