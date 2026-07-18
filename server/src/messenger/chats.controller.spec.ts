import { ChatInboxService } from "./chat-inbox.service";
import { ChatsController } from "./chats.controller";

describe("ChatsController archive alias", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  it("routes archived=true to the existing inbox archive operation", async () => {
    const inbox = {
      archiveChat: jest.fn().mockResolvedValue({ success: true }),
      unarchiveChat: jest.fn(),
    };
    const controller = new ChatsController(
      inbox as unknown as ChatInboxService,
    );

    await expect(
      controller.setArchived(actor, "chat-a", { archived: true }),
    ).resolves.toEqual({ ok: true });
    expect(inbox.archiveChat).toHaveBeenCalledWith(actor, "chat-a");
    expect(inbox.unarchiveChat).not.toHaveBeenCalled();
  });

  it("routes archived=false to unarchive", async () => {
    const inbox = {
      archiveChat: jest.fn(),
      unarchiveChat: jest.fn().mockResolvedValue({ success: true }),
    };
    const controller = new ChatsController(
      inbox as unknown as ChatInboxService,
    );

    await controller.setArchived(actor, "chat-a", { archived: false });
    expect(inbox.unarchiveChat).toHaveBeenCalledWith(actor, "chat-a");
    expect(inbox.archiveChat).not.toHaveBeenCalled();
  });
});
