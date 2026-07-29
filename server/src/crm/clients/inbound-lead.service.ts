import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { LeadWebhookDto } from "../dto/lead-webhook.dto";
import { ClientConfigRepository } from "./client-config.repository";
import { ClientWriteValidator } from "./client-write.validator";

export interface InboundLeadCommand {
  ingestionId: string;
  payload: LeadWebhookDto;
}

@Injectable()
export class InboundLeadService {
  constructor(
    private readonly integrity: PlatformIntegrityService,
    private readonly configRepository: ClientConfigRepository,
    private readonly validator: ClientWriteValidator,
  ) {}

  async ingest(command: InboundLeadCommand): Promise<{
    leadId: string;
    replayed: boolean;
  }> {
    const result = await this.integrity.executeVersionedMutation({
      actorKey: "integration:lead-webhook",
      operation: "crm.inbound-lead.ingest",
      idempotencyKey: command.ingestionId,
      payload: command.payload,
      aggregateType: "inbound_lead_ingestion",
      aggregateId: command.ingestionId,
      expectedVersion: 0,
      requestId: `inbound-lead:${command.ingestionId}`,
      audit: {
        action: "crm.inbound_lead_ingested",
        entityType: "inbound_lead_ingestion",
        entityId: command.ingestionId,
      },
      outbox: {
        type: "inbound.lead.created",
        payload: {
          aggregateId: command.ingestionId,
          state: "queued",
        },
      },
      mutate: async (client) => {
        // Validation belongs inside the reserved mutation: a completed
        // ingestion must replay even if its source is archived afterwards.
        const validated = await this.validator.validateLeadCreate(
          command.payload,
        );
        const notes =
          [
            command.payload.discipline?.trim()
              ? `Дисциплина: ${command.payload.discipline.trim()}`
              : null,
            command.payload.comment?.trim() || null,
          ]
            .filter(Boolean)
            .join("\n") || null;
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.leads (
              first_name,
              last_name,
              phone,
              email,
              source,
              source_id,
              notes,
              status_id,
              inbound_id
            )
            select
              $1,
              $2,
              $3,
              $4,
              source.canonical_name,
              source.id,
              $6,
              (
                select min(status.id::text)::uuid
                from app.lead_statuses status
                where lower(btrim(status.name)) = 'новый'
              ),
              $7
            from app.lead_sources source
            where source.id = $5
              and source.is_active
              and source.deleted_at is null
            returning id
          `,
          [
            validated.firstName,
            validated.lastName,
            validated.phone,
            command.payload.email?.trim().toLowerCase() || null,
            validated.sourceId,
            notes,
            command.ingestionId,
          ],
        );
        const leadId = inserted.rows[0]?.id;
        if (!leadId) {
          throw new UnprocessableEntityException({
            code: "SOURCE_INACTIVE",
            field: "sourceId",
            message: "Выберите активный источник.",
          });
        }
        await this.configRepository.saveValues(
          client,
          "lead",
          leadId,
          validated.customFields,
        );
        return { leadId };
      },
    });

    return {
      leadId: String(result.resultRef.leadId),
      replayed: result.replayed,
    };
  }
}
