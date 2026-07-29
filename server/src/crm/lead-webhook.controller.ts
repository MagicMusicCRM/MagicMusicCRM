import {
  Body,
  Controller,
  Headers,
  Post,
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import {
  createInboundLeadSignature,
  inboundLeadSignatureMatches,
  INBOUND_LEAD_REPLAY_WINDOW_SECONDS,
} from "./clients/inbound-lead-signature";
import { InboundLeadService } from "./clients/inbound-lead.service";
import { LeadWebhookDto } from "./dto/lead-webhook.dto";

/**
 * Public (no JWT) endpoint for the marketing site's lead form. Authenticated
 * by an HMAC signature over timestamp, ingestion id, and canonical payload.
 * While LEAD_WEBHOOK_SECRET is not configured the endpoint answers 503 so it
 * cannot be probed open.
 */
@Controller("public")
export class LeadWebhookController {
  constructor(private readonly inboundLeads: InboundLeadService) {}

  @Post("lead-webhook")
  async receiveLead(
    @Headers("x-ingestion-id") ingestionId: string | undefined,
    @Headers("x-webhook-timestamp") timestamp: string | undefined,
    @Headers("x-webhook-signature") signature: string | undefined,
    @Body() dto: LeadWebhookDto,
  ) {
    const secret = process.env.LEAD_WEBHOOK_SECRET ?? "";
    if (!secret) {
      throw new ServiceUnavailableException("Вебхук заявок не настроен.");
    }
    if (!ingestionId || !this.isUuid(ingestionId)) {
      throw new UnauthorizedException("Неверный идентификатор ingestion.");
    }
    const timestampSeconds = Number(timestamp);
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (
      !Number.isSafeInteger(timestampSeconds) ||
      Math.abs(nowSeconds - timestampSeconds) >
        INBOUND_LEAD_REPLAY_WINDOW_SECONDS
    ) {
      throw new UnauthorizedException("Подпись вебхука просрочена.");
    }
    const expected = createInboundLeadSignature(
      secret,
      timestampSeconds,
      ingestionId,
      dto,
    );
    if (!inboundLeadSignatureMatches(signature ?? "", expected)) {
      throw new UnauthorizedException("Неверная подпись вебхука.");
    }
    return this.inboundLeads.ingest({ ingestionId, payload: dto });
  }

  private isUuid(value: string): boolean {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
  }
}
