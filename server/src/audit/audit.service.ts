import type { PoolClient } from "pg";
import { Injectable } from "@nestjs/common";
import { redactSensitive } from "../common/logging/redact.util";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { safeAuditReasonText } from "../platform/platform-integrity.util";

export interface AuditEventInput {
  actor?: ActorContext;
  action: string;
  entityType: string;
  entityId?: string;
  metadata?: Record<string, unknown>;
}

@Injectable()
export class AuditService {
  constructor(private readonly database: DatabaseService) {}

  async record(event: AuditEventInput, client?: PoolClient): Promise<void> {
    const executor: {
      query(sql: string, params: unknown[]): Promise<unknown>;
    } = client ?? this.database;
    await executor.query(
      `
        insert into app.audit_events (
          actor_user_id,
          action,
          entity_type,
          entity_id,
          metadata,
          reason_text
        )
        values ($1, $2, $3, $4, $5::jsonb, $6)
      `,
      [
        event.actor?.userId ?? null,
        event.action,
        event.entityType,
        event.entityId ?? null,
        JSON.stringify(redactSensitive(event.metadata ?? {})),
        typeof event.metadata?.reason === 'string'
          ? safeAuditReasonText(event.metadata.reason)
          : null
      ]
    );
  }
}
