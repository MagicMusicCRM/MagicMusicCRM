import {
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import {
  createInboundLeadSignature,
  INBOUND_LEAD_REPLAY_WINDOW_SECONDS,
} from "./clients/inbound-lead-signature";
import { InboundLeadService } from "./clients/inbound-lead.service";
import { LeadWebhookController } from "./lead-webhook.controller";

describe("LeadWebhookController", () => {
  const originalSecret = process.env.LEAD_WEBHOOK_SECRET;
  const ingestionId = "10000000-0000-4000-8000-000000000001";
  const dto = {
    firstName: "Иван",
    lastName: "Петров",
    phone: "89991234567",
    sourceId: "20000000-0000-4000-8000-000000000001",
  };

  afterEach(() => {
    jest.restoreAllMocks();
    if (originalSecret === undefined) {
      delete process.env.LEAD_WEBHOOK_SECRET;
    } else {
      process.env.LEAD_WEBHOOK_SECRET = originalSecret;
    }
  });

  const createController = () => {
    const inbound = {
      ingest: jest.fn().mockResolvedValue({
        leadId: "lead-1",
        replayed: false,
      }),
    };
    const controller = new LeadWebhookController(
      inbound as unknown as InboundLeadService,
    );
    return { controller, inbound };
  };

  it("returns 503 when LEAD_WEBHOOK_SECRET is not configured", async () => {
    delete process.env.LEAD_WEBHOOK_SECRET;
    const { controller, inbound } = createController();
    await expect(
      controller.receiveLead(ingestionId, "1", "sha256=bad", dto),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(inbound.ingest).not.toHaveBeenCalled();
  });

  it("rejects missing identity, stale requests, and invalid signatures", async () => {
    process.env.LEAD_WEBHOOK_SECRET = "top-secret";
    const nowSeconds = 1_800_000_000;
    jest.spyOn(Date, "now").mockReturnValue(nowSeconds * 1000);
    const { controller, inbound } = createController();

    await expect(
      controller.receiveLead(undefined, String(nowSeconds), "sha256=bad", dto),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(
      controller.receiveLead(
        ingestionId,
        String(nowSeconds - INBOUND_LEAD_REPLAY_WINDOW_SECONDS - 1),
        "sha256=bad",
        dto,
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(
      controller.receiveLead(
        ingestionId,
        String(nowSeconds),
        "sha256=bad",
        dto,
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(inbound.ingest).not.toHaveBeenCalled();
  });

  it("accepts a fresh canonical HMAC signature", async () => {
    process.env.LEAD_WEBHOOK_SECRET = "top-secret";
    const nowSeconds = 1_800_000_000;
    jest.spyOn(Date, "now").mockReturnValue(nowSeconds * 1000);
    const signature = createInboundLeadSignature(
      process.env.LEAD_WEBHOOK_SECRET,
      nowSeconds,
      ingestionId,
      dto,
    );
    const { controller, inbound } = createController();

    await expect(
      controller.receiveLead(
        ingestionId,
        String(nowSeconds),
        signature,
        dto,
      ),
    ).resolves.toEqual({ leadId: "lead-1", replayed: false });
    expect(inbound.ingest).toHaveBeenCalledWith({
      ingestionId,
      payload: dto,
    });
  });
});
