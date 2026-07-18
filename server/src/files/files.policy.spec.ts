import { NotFoundException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { MessengerPolicy } from "../messenger/messenger.policy";
import { FilesPolicy } from "./files.policy";

describe("FilesPolicy", () => {
  const policy = new FilesPolicy(
    { query: jest.fn() } as unknown as DatabaseService,
    {} as MessengerPolicy,
  );

  it("allows owners to read their own files", async () => {
    await expect(
      policy.assertCanRead(
        { userId: "user-a", role: "client" },
        {
          id: "file-a",
          owner_user_id: "user-a",
          owner_type: null,
          owner_id: null,
          purpose: "profile_avatar",
          deleted_at: null,
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("hides foreign files from clients", async () => {
    await expect(
      policy.assertCanRead(
        { userId: "user-a", role: "client" },
        {
          id: "file-b",
          owner_user_id: "user-b",
          owner_type: null,
          owner_id: null,
          purpose: "chat_attachment",
          deleted_at: null,
        },
      ),
    ).rejects.toThrow(NotFoundException);
  });

  it("allows staff to read operational files", async () => {
    await expect(
      policy.assertCanRead(
        { userId: "manager-a", role: "manager" },
        {
          id: "file-c",
          owner_user_id: "user-b",
          owner_type: "student",
          owner_id: "student-a",
          purpose: "crm_document",
          deleted_at: null,
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("allows chat members to read chat attachment files", async () => {
    const chatPolicy = {
      getChatAccess: jest.fn().mockResolvedValue({
        id: "chat-a",
        type: "direct",
        memberUserId: "user-a",
        memberRole: "member",
      }),
      assertCanReadChat: jest.fn(),
    } as unknown as MessengerPolicy;
    const chatFilePolicy = new FilesPolicy(
      { query: jest.fn() } as unknown as DatabaseService,
      chatPolicy,
    );

    await expect(
      chatFilePolicy.assertCanRead(
        { userId: "user-a", role: "client" },
        {
          id: "file-d",
          owner_user_id: "user-b",
          owner_type: "chat",
          owner_id: "chat-a",
          purpose: "chat_voice",
          deleted_at: null,
        },
      ),
    ).resolves.toBeUndefined();
    expect(chatPolicy.assertCanReadChat).toHaveBeenCalledWith(
      { userId: "user-a", role: "client" },
      {
        id: "chat-a",
        type: "direct",
        memberUserId: "user-a",
        memberRole: "member",
      },
    );
  });

  it("hides chat attachment files when chat exists but actor is not a member", async () => {
    const chatPolicy = {
      getChatAccess: jest.fn().mockResolvedValue({
        id: "chat-a",
        type: "direct",
        memberUserId: null,
        memberRole: null,
      }),
      assertCanReadChat: jest.fn(() => {
        throw new NotFoundException("Чат не найден.");
      }),
    } as unknown as MessengerPolicy;
    const chatFilePolicy = new FilesPolicy(
      { query: jest.fn() } as unknown as DatabaseService,
      chatPolicy,
    );

    await expect(
      chatFilePolicy.assertCanRead(
        { userId: "user-a", role: "client" },
        {
          id: "file-d",
          owner_user_id: "user-b",
          owner_type: "chat",
          owner_id: "chat-a",
          purpose: "chat_attachment",
          deleted_at: null,
        },
      ),
    ).rejects.toThrow(NotFoundException);
  });

  it("lets a linked lead client read a trial-homework attachment", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          assigned_by: "teacher-user",
          teacher_user_id: "teacher-user",
          client_can_access: true,
        },
      ],
    });
    const homeworkPolicy = new FilesPolicy(
      { query } as unknown as DatabaseService,
      {} as MessengerPolicy,
    );

    await expect(
      homeworkPolicy.assertCanRead(
        { userId: "client-user", role: "client" },
        {
          id: "file-homework",
          owner_user_id: "teacher-user",
          owner_type: "homework",
          owner_id: "homework-lead",
          purpose: "homework_attachment",
          deleted_at: null,
        },
      ),
    ).resolves.toBeUndefined();
    await expect(
      homeworkPolicy.assertCanUpload(
        { userId: "client-user", role: "client" },
        "homework_attachment",
        "homework",
        "homework-lead",
      ),
    ).resolves.toBe("client-user");
    expect(String(query.mock.calls[0][0])).toContain(
      "app.user_crm_links lead_link",
    );
    expect(String(query.mock.calls[0][0])).toContain(
      "subject_member.entity_type = 'lead'",
    );
    expect(query.mock.calls[0][1]).toEqual([
      "homework-lead",
      "client-user",
    ]);
  });

  it("checks homework ownership before accepting an attachment upload", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          assigned_by: "teacher-user",
          teacher_user_id: "teacher-user",
          client_can_access: false,
        },
      ],
    });
    const homeworkPolicy = new FilesPolicy(
      { query } as unknown as DatabaseService,
      {} as MessengerPolicy,
    );

    await expect(
      homeworkPolicy.assertCanUpload(
        { userId: "teacher-user", role: "teacher" },
        "homework_attachment",
        "homework",
        "homework-a",
      ),
    ).resolves.toBe("teacher-user");
    await expect(
      homeworkPolicy.assertCanUpload(
        { userId: "other-user", role: "client" },
        "homework_attachment",
        "homework",
        "homework-a",
      ),
    ).rejects.toThrow(NotFoundException);
  });
});
