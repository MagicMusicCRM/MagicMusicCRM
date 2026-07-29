import { PoolClient } from "pg";

export interface PlatformAuditInput {
  action: string;
  entityType: string;
  entityId?: string;
  beforeRef?: Record<string, unknown>;
  afterRef?: Record<string, unknown>;
  reason?: string;
  metadata?: Record<string, unknown>;
}

export interface PlatformOutboxInput {
  type: string;
  payload?: Record<string, unknown>;
}

export interface VersionedMutationResultRef {
  [key: string]: unknown;
}

export interface VersionedMutationCommand<
  TResultRef extends VersionedMutationResultRef,
> {
  actorKey: string;
  actorUserId?: string;
  operation: string;
  idempotencyKey: string;
  payload: unknown;
  aggregateType: string;
  aggregateId: string;
  expectedVersion: number;
  requestId: string;
  audit: PlatformAuditInput;
  outbox: PlatformOutboxInput;
  retentionUntil?: Date;
  mutate: (
    client: PoolClient,
    nextVersion: number,
  ) => Promise<TResultRef>;
}

export interface VersionedMutationResult<
  TResultRef extends VersionedMutationResultRef,
> {
  resultRef: TResultRef;
  version: number;
  replayed: boolean;
  auditId: string;
  eventId: string;
}

export interface ClaimedOutboxEvent {
  eventId: string;
  type: string;
  occurredAt: Date;
  aggregateType: string;
  aggregateId: string;
  aggregateVersion: number;
  requestId: string;
  payload: Record<string, unknown>;
  attempts: number;
}
