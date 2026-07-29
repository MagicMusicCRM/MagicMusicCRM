import { Injectable } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityRepository } from "./platform-integrity.repository";
import {
  ClaimedOutboxEvent,
  VersionedMutationCommand,
  VersionedMutationResult,
  VersionedMutationResultRef,
} from "./platform-integrity.types";
import {
  computeOutboxBackoffSeconds,
  fingerprintPayload,
  safeReference,
} from "./platform-integrity.util";

@Injectable()
export class PlatformIntegrityService {
  constructor(
    private readonly database: DatabaseService,
    private readonly repository: PlatformIntegrityRepository,
  ) {}

  async executeVersionedMutation<
    TResultRef extends VersionedMutationResultRef,
  >(
    command: VersionedMutationCommand<TResultRef>,
  ): Promise<VersionedMutationResult<TResultRef>> {
    const fingerprint = fingerprintPayload({
      operation: command.operation,
      aggregateType: command.aggregateType,
      aggregateId: command.aggregateId,
      expectedVersion: command.expectedVersion,
      payload: command.payload,
    });
    return this.database.transaction(async (client) => {
      const reservation = await this.repository.reserveIdempotency(client, {
        actorKey: command.actorKey,
        operation: command.operation,
        idempotencyKey: command.idempotencyKey,
        fingerprint,
        expiresAt: command.retentionUntil,
      });
      if (reservation.replay) {
        return {
          resultRef: reservation.replay.resultRef as TResultRef,
          version: reservation.replay.version,
          replayed: true,
          auditId: reservation.replay.auditId,
          eventId: reservation.replay.eventId,
        };
      }

      const version = await this.repository.advanceVersion(
        client,
        command.aggregateType,
        command.aggregateId,
        command.expectedVersion,
      );
      const resultRef = safeReference(
        await command.mutate(client, version),
      ) as TResultRef;
      const auditId = await this.repository.appendAudit(client, {
        ...command.audit,
        actorUserId: command.actorUserId,
        requestId: command.requestId,
        afterRef: command.audit.afterRef ?? resultRef,
      });
      const eventId = await this.repository.enqueueOutbox(client, {
        ...command.outbox,
        payload: this.withAggregateVersion(
          command.outbox.type,
          command.outbox.payload,
          version,
        ),
        aggregateType: command.aggregateType,
        aggregateId: command.aggregateId,
        aggregateVersion: version,
        requestId: command.requestId,
      });
      await this.repository.completeIdempotency(
        client,
        reservation.recordId,
        resultRef,
        version,
        auditId,
        eventId,
      );
      return {
        resultRef,
        version,
        replayed: false,
        auditId,
        eventId,
      };
    });
  }

  private withAggregateVersion(
    eventType: string,
    payload: Record<string, unknown> | undefined,
    version: number,
  ): Record<string, unknown> | undefined {
    if (
      eventType !== "access.invalidated" &&
      eventType !== "access.package.changed"
    ) {
      return payload;
    }
    return {
      ...payload,
      accessVersion: version,
    };
  }

  claimOutbox(
    workerId: string,
    options: {
      limit?: number;
      leaseSeconds?: number;
      maxAttempts?: number;
    } = {},
  ): Promise<ClaimedOutboxEvent[]> {
    return this.database.transaction((client) =>
      this.repository.claimOutbox(client, {
        workerId,
        limit: options.limit ?? 50,
        leaseSeconds: options.leaseSeconds ?? 300,
        maxAttempts: options.maxAttempts ?? 10,
      }),
    );
  }

  markOutboxPublished(
    eventId: string,
    workerId: string,
  ): Promise<boolean> {
    return this.database.transaction((client) =>
      this.repository.markOutboxPublished(client, eventId, workerId),
    );
  }

  async markOutboxFailed(
    event: Pick<ClaimedOutboxEvent, "eventId" | "attempts">,
    workerId: string,
    error: unknown,
    options: {
      baseSeconds?: number;
      capSeconds?: number;
      maxAttempts?: number;
    } = {},
  ): Promise<"retry" | "dead-letter" | "not-owned"> {
    const retryAfterSeconds = computeOutboxBackoffSeconds(
      event.attempts,
      options.baseSeconds,
      options.capSeconds,
    );
    return this.database.transaction((client) =>
      this.repository.markOutboxFailed(client, {
        eventId: event.eventId,
        workerId,
        error,
        retryAfterSeconds,
        maxAttempts: options.maxAttempts ?? 10,
      }),
    );
  }
}
