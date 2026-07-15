import {
  Body,
  Controller,
  Headers,
  Post,
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import { createHash, timingSafeEqual } from "node:crypto";
import { LeadIntakeService } from "./lead-intake.service";
import { LeadWebhookDto } from "./dto/lead-webhook.dto";

/**
 * Public (no JWT) endpoint for the marketing site's lead form. Authenticated
 * by a shared secret in the X-Webhook-Secret header; while LEAD_WEBHOOK_SECRET
 * is not configured the endpoint answers 503 so it cannot be probed open.
 */
@Controller("public")
export class LeadWebhookController {
  constructor(private readonly leads: LeadIntakeService) {}

  @Post("lead-webhook")
  async receiveLead(
    @Headers("x-webhook-secret") secret: string | undefined,
    @Body() dto: LeadWebhookDto,
  ) {
    const expected = process.env.LEAD_WEBHOOK_SECRET ?? "";
    if (!expected) {
      throw new ServiceUnavailableException("Вебхук заявок не настроен.");
    }
    if (!this.secretsMatch(secret ?? "", expected)) {
      throw new UnauthorizedException("Неверный секрет вебхука.");
    }
    return this.leads.createLeadFromSiteWebhook(dto);
  }

  // Constant-time comparison (hash both sides so lengths always match).
  private secretsMatch(provided: string, expected: string): boolean {
    const a = createHash("sha256").update(provided).digest();
    const b = createHash("sha256").update(expected).digest();
    return timingSafeEqual(a, b);
  }
}
