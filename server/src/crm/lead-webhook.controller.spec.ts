import { ServiceUnavailableException, UnauthorizedException } from "@nestjs/common";
import { LeadsService } from "./leads.service";
import { LeadWebhookController } from "./lead-webhook.controller";

describe("LeadWebhookController", () => {
  const originalSecret = process.env.LEAD_WEBHOOK_SECRET;

  afterEach(() => {
    if (originalSecret === undefined) {
      delete process.env.LEAD_WEBHOOK_SECRET;
    } else {
      process.env.LEAD_WEBHOOK_SECRET = originalSecret;
    }
  });

  const createController = () => {
    const crm = {
      createLeadFromSiteWebhook: jest.fn().mockResolvedValue({ leadId: "lead-1" }),
    };
    const controller = new LeadWebhookController(crm as unknown as LeadsService);
    return { controller, crm };
  };

  const dto = { name: "Иван", phone: "89991234567" };

  it("returns 503 when LEAD_WEBHOOK_SECRET is not configured", async () => {
    delete process.env.LEAD_WEBHOOK_SECRET;
    const { controller, crm } = createController();
    await expect(controller.receiveLead("whatever", dto)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(crm.createLeadFromSiteWebhook).not.toHaveBeenCalled();
  });

  it("returns 401 on a wrong or missing secret", async () => {
    process.env.LEAD_WEBHOOK_SECRET = "top-secret";
    const { controller, crm } = createController();
    await expect(controller.receiveLead("wrong", dto)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    await expect(controller.receiveLead(undefined, dto)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(crm.createLeadFromSiteWebhook).not.toHaveBeenCalled();
  });

  it("creates the lead when the secret matches", async () => {
    process.env.LEAD_WEBHOOK_SECRET = "top-secret";
    const { controller, crm } = createController();
    await expect(controller.receiveLead("top-secret", dto)).resolves.toEqual({
      leadId: "lead-1",
    });
    expect(crm.createLeadFromSiteWebhook).toHaveBeenCalledWith(dto);
  });
});
