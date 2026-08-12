import { validate } from "class-validator";
import { SendMessageDto } from "./send-message.dto";

describe("SendMessageDto", () => {
  it("accepts image messages with an attachment file id", async () => {
    const dto = Object.assign(new SendMessageDto(), {
      content: "Фото",
      messageType: "image",
      attachmentFileId: "8c7890ec-e04e-4e4e-9a68-972f852979b3",
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it("continues to reject unknown message types", async () => {
    const dto = Object.assign(new SendMessageDto(), {
      content: "Фото",
      messageType: "photo",
    });

    expect(await validate(dto)).not.toHaveLength(0);
  });

  it("accepts a bounded persisted voice duration", async () => {
    const dto = Object.assign(new SendMessageDto(), {
      messageType: "voice",
      attachmentFileId: "8c7890ec-e04e-4e4e-9a68-972f852979b3",
      voiceDurationMs: 1_500,
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it.each([0, 3_600_001, 1.5])(
    "rejects invalid voice duration %s",
    async (voiceDurationMs) => {
      const dto = Object.assign(new SendMessageDto(), {
        messageType: "voice",
        attachmentFileId: "8c7890ec-e04e-4e4e-9a68-972f852979b3",
        voiceDurationMs,
      });

      expect(await validate(dto)).not.toHaveLength(0);
    },
  );
});
