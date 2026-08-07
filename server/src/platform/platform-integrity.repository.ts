import { ConflictException, Injectable } from "@nestjs/common";
import { randomUUID } from "crypto";
import { PoolClient } from "pg";
import {
  ClaimedOutboxEvent,
  PlatformAuditInput,
  PlatformOutboxInput,
  VersionedMutationResultRef,
} from "./platform-integrity.types";
import {
  safeFailureName,
  safeAuditReason,
  safeAuditReasonText,
  safeOutboxPayload,
  safeReference,
} from "./platform-integrity.util";

interface IdempotencyRow {
  id: string;
  request_fingerprint: string;
  status: "pending" | "completed";
  result_ref: VersionedMutationResultRef | null;
  result_version: number | string | null;
  audit_event_id: string | null;
  outbox_event_id: string | null;
}

interface VersionRow {
  version: number | string;
}

interface OutboxRow {
  event_id: string;
  event_type: string;
  occurred_at: Date | string;
  aggregate_type: string;
  aggregate_id: string;
  aggregate_version: number | string;
  request_id: string;
  payload: Record<string, unknown>;
  attempts: number | string;
}

export interface IdempotencyReservation {
  recordId: string;
  replay:
    | {
        resultRef: VersionedMutationResultRef;
        version: number;
        auditId: string;
        eventId: string;
      }
    | null;
}

@Injectable()
export class PlatformIntegrityRepository {
  async reserveIdempotency(
    client: PoolClient,
    input: {
      actorKey: string;
      operation: string;
      idempotencyKey: string;
      fingerprint: string;
      expiresAt?: Date;
    },
  ): Promise<IdempotencyReservation> {
    const inserted = await client.query<{ id: string }>(
      `
        insert into app.idempotency_records (
          actor_key,
          operation,
          idempotency_key,
          request_fingerprint,
          expires_at
        )
        values ($1, $2, $3, $4, $5)
        on conflict (actor_key, operation, idempotency_key) do nothing
        returning id
      `,
      [
        input.actorKey,
        input.operation,
        input.idempotencyKey,
        input.fingerprint,
        input.expiresAt ?? null,
      ],
    );
    const record = await client.query<IdempotencyRow>(
      `
        select
          id,
          request_fingerprint,
          status,
          result_ref,
          result_version,
          audit_event_id,
          outbox_event_id
          from app.idempotency_records
         where actor_key = $1
           and operation = $2
           and idempotency_key = $3
         for update
      `,
      [input.actorKey, input.operation, input.idempotencyKey],
    );
    const row = record.rows[0];
    if (!row) {
      throw new Error("Idempotency reservation disappeared.");
    }
    if (row.request_fingerprint !== input.fingerprint) {
      throw new ConflictException({
        code: "IDEMPOTENCY_KEY_REUSED",
        message: "Idempotency key was already used with another payload.",
      });
    }
    if (inserted.rowCount === 0) {
      if (
        row.status !== "completed" ||
        row.result_ref === null ||
        row.result_version === null ||
        row.audit_event_id === null ||
        row.outbox_event_id === null
      ) {
        throw new ConflictException({
          code: "IDEMPOTENCY_IN_PROGRESS",
          message: "The original mutation is still in progress.",
        });
      }
      return {
        recordId: row.id,
        replay: {
          resultRef: row.result_ref,
          version: Number(row.result_version),
          auditId: row.audit_event_id,
          eventId: row.outbox_event_id,
        },
      };
    }
    return { recordId: row.id, replay: null };
  }

  async advanceVersion(
    client: PoolClient,
    aggregateType: string,
    aggregateId: string,
    expectedVersion: number,
  ): Promise<number> {
    if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 0) {
      throw new TypeError("Expected version must be a non-negative integer.");
    }

    const result =
      expectedVersion === 0
        ? await client.query<VersionRow>(
            `
              insert into app.aggregate_versions (
                aggregate_type,
                aggregate_id,
                version
              )
              values ($1, $2, 1)
              on conflict (aggregate_type, aggregate_id) do nothing
              returning version
            `,
            [aggregateType, aggregateId],
          )
        : await client.query<VersionRow>(
            `
              update app.aggregate_versions
                 set version = version + 1,
                     updated_at = now()
               where aggregate_type = $1
                 and aggregate_id = $2
                 and version = $3
              returning version
            `,
            [aggregateType, aggregateId, expectedVersion],
          );
    const row = result.rows[0];
    if (!row) {
      const current = await client.query<VersionRow>(
        `
          select version
            from app.aggregate_versions
           where aggregate_type = $1 and aggregate_id = $2
        `,
        [aggregateType, aggregateId],
      );
      throw new ConflictException({
        code: "STALE_VERSION",
        message: "Aggregate version is stale.",
        expectedVersion,
        currentVersion:
          current.rows[0] === undefined
            ? null
            : Number(current.rows[0].version),
      });
    }
    return Number(row.version);
  }

  async appendAudit(
    client: PoolClient,
    input: PlatformAuditInput & {
      actorUserId?: string;
      requestId: string;
    },
  ): Promise<string> {
    const id = input.id ?? randomUUID();
    await client.query(
      `
        insert into app.audit_events (
          id,
          actor_user_id,
          action,
          entity_type,
          entity_id,
          metadata,
          request_id,
          before_ref,
          after_ref,
          reason,
          reason_text
        )
        values (
          $1, $2, $3, $4, $5, $6::jsonb, $7, $8::jsonb, $9::jsonb, $10,
          $11
        )
      `,
      [
        id,
        input.actorUserId ?? null,
        input.action,
        input.entityType,
        input.entityId ?? null,
        JSON.stringify(safeReference(input.metadata ?? {})),
        input.requestId,
        input.beforeRef
          ? JSON.stringify(safeReference(input.beforeRef))
          : null,
        input.afterRef
          ? JSON.stringify(safeReference(input.afterRef))
          : null,
        safeAuditReason(input.reason),
        safeAuditReasonText(input.reasonText),
      ],
    );
    return id;
  }

  async enqueueOutbox(
    client: PoolClient,
    input: PlatformOutboxInput & {
      aggregateType: string;
      aggregateId: string;
      aggregateVersion: number;
      requestId: string;
    },
  ): Promise<string> {
    const eventId = randomUUID();
    await client.query(
      `
        insert into app.platform_outbox_events (
          event_id,
          event_type,
          aggregate_type,
          aggregate_id,
          aggregate_version,
          request_id,
          payload
        )
        values ($1, $2, $3, $4, $5, $6, $7::jsonb)
      `,
      [
        eventId,
        input.type,
        input.aggregateType,
        input.aggregateId,
        input.aggregateVersion,
        input.requestId,
        JSON.stringify(safeOutboxPayload(input.payload)),
      ],
    );
    return eventId;
  }

  async completeIdempotency(
    client: PoolClient,
    recordId: string,
    resultRef: VersionedMutationResultRef,
    version: number,
    auditId: string,
    eventId: string,
  ): Promise<void> {
    const result = await client.query(
      `
        update app.idempotency_records
           set status = 'completed',
               result_ref = $2::jsonb,
               result_version = $3,
               audit_event_id = $4,
               outbox_event_id = $5,
               completed_at = now()
         where id = $1 and status = 'pending'
      `,
      [
        recordId,
        JSON.stringify(safeReference(resultRef)),
        version,
        auditId,
        eventId,
      ],
    );
    if (result.rowCount !== 1) {
      throw new Error("Idempotency record could not be completed.");
    }
  }

  async claimOutbox(
    client: PoolClient,
    input: {
      workerId: string;
      limit: number;
      leaseSeconds: number;
      maxAttempts: number;
    },
  ): Promise<ClaimedOutboxEvent[]> {
    const result = await client.query<OutboxRow>(
      `
        with due as (
          select event_id
            from app.platform_outbox_events
           where published_at is null
             and dead_lettered_at is null
             and available_at <= now()
             and attempts < $4
             and (
               claimed_at is null
               or claimed_at < now() - make_interval(secs => $3)
             )
           order by available_at, occurred_at, event_id
           for update skip locked
           limit $2
        )
        update app.platform_outbox_events event
           set claimed_at = now(),
               claimed_by = $1,
               attempts = event.attempts + 1
          from due
         where event.event_id = due.event_id
        returning
          event.event_id,
          event.event_type,
          event.occurred_at,
          event.aggregate_type,
          event.aggregate_id,
          event.aggregate_version,
          event.request_id,
          event.payload,
          event.attempts
      `,
      [
        input.workerId,
        Math.max(1, Math.floor(input.limit)),
        Math.max(1, Math.floor(input.leaseSeconds)),
        Math.max(1, Math.floor(input.maxAttempts)),
      ],
    );
    return result.rows.map((row) => ({
      eventId: row.event_id,
      type: row.event_type,
      occurredAt: new Date(row.occurred_at),
      aggregateType: row.aggregate_type,
      aggregateId: row.aggregate_id,
      aggregateVersion: Number(row.aggregate_version),
      requestId: row.request_id,
      payload: row.payload,
      attempts: Number(row.attempts),
    }));
  }

  async markOutboxPublished(
    client: PoolClient,
    eventId: string,
    workerId: string,
  ): Promise<boolean> {
    const result = await client.query(
      `
        update app.platform_outbox_events
           set published_at = now(),
               claimed_at = null,
               claimed_by = null,
               last_error = null
         where event_id = $1
           and claimed_by = $2
           and published_at is null
           and dead_lettered_at is null
      `,
      [eventId, workerId],
    );
    return result.rowCount === 1;
  }

  async markOutboxFailed(
    client: PoolClient,
    input: {
      eventId: string;
      workerId: string;
      error: unknown;
      retryAfterSeconds: number;
      maxAttempts: number;
    },
  ): Promise<"retry" | "dead-letter" | "not-owned"> {
    const result = await client.query<{ dead_lettered_at: Date | null }>(
      `
        update app.platform_outbox_events
           set available_at = now() + make_interval(secs => $4),
               claimed_at = null,
               claimed_by = null,
               last_error = $3,
               dead_lettered_at =
                 case when attempts >= $5 then now() else null end
         where event_id = $1
           and claimed_by = $2
           and published_at is null
           and dead_lettered_at is null
        returning dead_lettered_at
      `,
      [
        input.eventId,
        input.workerId,
        safeFailureName(input.error),
        Math.max(1, Math.floor(input.retryAfterSeconds)),
        Math.max(1, Math.floor(input.maxAttempts)),
      ],
    );
    const row = result.rows[0];
    if (!row) return "not-owned";
    return row.dead_lettered_at ? "dead-letter" : "retry";
  }
}
