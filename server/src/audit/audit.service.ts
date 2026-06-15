import { Injectable } from '@nestjs/common';
import { redactSensitive } from '../common/logging/redact.util';
import { ActorContext } from '../common/security/actor-context';
import { DatabaseService } from '../db/database.service';

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

  async record(event: AuditEventInput): Promise<void> {
    await this.database.query(
      `
        insert into app.audit_events (
          actor_user_id,
          action,
          entity_type,
          entity_id,
          metadata
        )
        values ($1, $2, $3, $4, $5::jsonb)
      `,
      [
        event.actor?.userId ?? null,
        event.action,
        event.entityType,
        event.entityId ?? null,
        JSON.stringify(redactSensitive(event.metadata ?? {}))
      ]
    );
  }
}
