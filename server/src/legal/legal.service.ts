import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { AuditService } from '../audit/audit.service';
import { ActorContext } from '../common/security/actor-context';
import { DatabaseService } from '../db/database.service';
import { AcceptCurrentConsentsDto } from './dto/accept-current-consents.dto';
import { CreateDeletionRequestDto } from './dto/create-deletion-request.dto';
import { ListDeletionRequestsQuery } from './dto/list-deletion-requests.query';
import { UpdateDeletionRequestDto } from './dto/update-deletion-request.dto';
import { DeletionRequestAccessRecord, LegalPolicy } from './legal.policy';
import { AccountDeletionStatus, ConsentEvidence, LegalDocumentType } from './legal.types';

interface LegalDocumentRow {
  id: string;
  document_type: LegalDocumentType;
  version: string;
  title: string;
  url: string | null;
  file_id: string | null;
  published_at: Date | string;
}

interface GateRow {
  current_count: string;
  accepted_count: string;
  deletion_pending: boolean;
  role: ActorContext['role'];
  profile_complete: boolean;
}

interface DeletionRequestRow extends DeletionRequestAccessRecord {
  reason: string | null;
  requested_at: Date | string;
  resolved_at: Date | string | null;
  resolved_by: string | null;
  resolution_note: string | null;
  updated_at: Date | string;
  user_email?: string;
}

interface CountRow {
  total: string;
}

@Injectable()
export class LegalService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: LegalPolicy
  ) {}

  async getGate(actor: ActorContext) {
    const result = await this.database.query<GateRow>(
      `
        with current_docs as (
          select id from app.legal_documents where is_current = true
        ),
        accepted_docs as (
          select lc.document_id
          from app.legal_consents lc
          join current_docs cd on cd.id = lc.document_id
          where lc.user_id = $1
        ),
        active_deletion as (
          select exists (
            select 1
            from app.account_deletion_requests
            where user_id = $1
              and status in ('pending', 'processing')
          ) as deletion_pending
        ),
        user_state as (
          select role, profile_completed
          from app.users
          where id = $1
            and deleted_at is null
        ),
        profile_state as (
          select
            btrim(coalesce(first_name, '')) as first_name,
            btrim(coalesce(last_name, '')) as last_name,
            btrim(coalesce(phone, '')) as phone
          from app.profiles
          where user_id = $1
            and deleted_at is null
          limit 1
        )
        select
          (select count(*) from current_docs)::text as current_count,
          (select count(*) from accepted_docs)::text as accepted_count,
          (select deletion_pending from active_deletion) as deletion_pending,
          coalesce((select role from user_state), $2::app.user_role) as role,
          (
            coalesce((select profile_completed from user_state), false)
            or coalesce(
              (
                select
                  first_name <> '' and last_name <> '' and phone <> ''
                from profile_state
              ),
              false
            )
          ) as profile_complete
      `,
      [actor.userId, actor.role]
    );
    const row = result.rows[0];
    const currentCount = Number(row?.current_count ?? '0');
    const acceptedCount = Number(row?.accepted_count ?? '0');
    const legalAccepted =
      currentCount === 0 || acceptedCount === currentCount;
    return {
      role: row?.role ?? actor.role,
      profileComplete: row?.profile_complete === true,
      legalAccepted,
      deletionPending: row?.deletion_pending === true
    };
  }

  async listCurrentDocuments() {
    const result = await this.database.query<LegalDocumentRow>(
      `
        select id, document_type, version, title, url, file_id, published_at
        from app.legal_documents
        where is_current = true
        order by document_type asc
      `
    );
    return result.rows.map((row) => this.toDocumentDto(row));
  }

  async acceptCurrentDocuments(
    actor: ActorContext,
    dto: AcceptCurrentConsentsDto,
    evidence: ConsentEvidence
  ) {
    const current = await this.database.query<LegalDocumentRow>(
      `
        select id, document_type, version, title, url, file_id, published_at
        from app.legal_documents
        where is_current = true
        order by document_type asc
      `
    );
    if (current.rows.length === 0) {
      throw new BadRequestException('Нет опубликованных юридических документов.');
    }
    this.assertExactCurrentDocumentSet(
      current.rows.map((row) => row.id),
      dto.documentIds
    );

    const ipHash = this.optionalHash(evidence.ip);
    const userAgentHash = this.optionalHash(evidence.userAgent);

    await this.database.transaction(async (client) => {
      for (const document of current.rows) {
        await client.query(
          `
            insert into app.legal_consents (
              user_id, document_id, version, ip_hash, user_agent_hash
            )
            values ($1, $2, $3, $4, $5)
            on conflict (user_id, document_id) do nothing
          `,
          [actor.userId, document.id, document.version, ipHash, userAgentHash]
        );
      }
    });

    await this.audit.record({
      actor,
      action: 'legal.consents_accepted',
      entityType: 'legal_consent',
      metadata: { documentIds: current.rows.map((row) => row.id) }
    });

    return { accepted: true };
  }

  async createDeletionRequest(actor: ActorContext, dto: CreateDeletionRequestDto) {
    const existing = await this.findActiveDeletionRequest(actor.userId);
    if (existing) return this.toDeletionRequestDto(existing);

    const result = await this.database.query<DeletionRequestRow>(
      `
        insert into app.account_deletion_requests (user_id, reason)
        values ($1, $2)
        returning id, user_id, status, reason, requested_at, resolved_at,
          resolved_by, resolution_note, updated_at
      `,
      [actor.userId, dto.reason?.trim() || null]
    );
    const request = result.rows[0];

    await this.audit.record({
      actor,
      action: 'legal.deletion_requested',
      entityType: 'account_deletion_request',
      entityId: request.id
    });

    return this.toDeletionRequestDto(request);
  }

  async getOwnDeletionRequest(actor: ActorContext) {
    const request = await this.findLatestDeletionRequest(actor.userId);
    return request ? this.toDeletionRequestDto(request) : null;
  }

  async listDeletionRequests(actor: ActorContext, query: ListDeletionRequestsQuery) {
    this.policy.assertCanListDeletionRequests(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<DeletionRequestRow & CountRow>(
      `
        select adr.id, adr.user_id, adr.status, adr.reason, adr.requested_at,
          adr.resolved_at, adr.resolved_by, adr.resolution_note, adr.updated_at,
          u.email as user_email, count(*) over() as total
        from app.account_deletion_requests adr
        join app.users u on u.id = adr.user_id
        where ($1::text is null or adr.status = $1::app.account_deletion_status)
        order by adr.requested_at desc, adr.id desc
        limit $2
      `,
      [query.status ?? null, limit]
    );

    return {
      items: result.rows.map((row) => this.toDeletionRequestDto(row)),
      total: Number(result.rows[0]?.total ?? '0')
    };
  }

  async updateDeletionRequest(actor: ActorContext, id: string, dto: UpdateDeletionRequestDto) {
    this.policy.assertCanUpdateDeletionRequest(actor);
    const current = await this.requireDeletionRequest(id);
    this.policy.assertCanReadDeletionRequest(actor, current);
    this.policy.assertValidTransition(current.status, dto.status);

    const result = await this.database.transaction(async (client) => {
      const updated = await client.query<DeletionRequestRow>(
        `
          update app.account_deletion_requests
          set
            status = $2::app.account_deletion_status,
            resolved_at = case when $2::app.account_deletion_status in ('completed', 'rejected', 'cancelled') then now() else resolved_at end,
            resolved_by = case when $2::app.account_deletion_status in ('completed', 'rejected', 'cancelled') then $3 else resolved_by end,
            resolution_note = coalesce($4, resolution_note),
            updated_at = now()
          where id = $1
          returning id, user_id, status, reason, requested_at, resolved_at,
            resolved_by, resolution_note, updated_at
        `,
        [id, dto.status, actor.userId, dto.resolutionNote?.trim() || null]
      );

      if (dto.status === 'completed') {
        await client.query(
          `
            update app.users
            set deleted_at = coalesce(deleted_at, now()), updated_at = now()
            where id = $1
          `,
          [current.user_id]
        );
        await client.query(
          `
            update app.profiles
            set deleted_at = coalesce(deleted_at, now()), updated_at = now()
            where user_id = $1
          `,
          [current.user_id]
        );
        await client.query(
          `
            update app.refresh_sessions
            set revoked_at = coalesce(revoked_at, now())
            where user_id = $1
          `,
          [current.user_id]
        );
      }

      return updated.rows[0];
    });

    await this.audit.record({
      actor,
      action: 'legal.deletion_status_updated',
      entityType: 'account_deletion_request',
      entityId: id,
      metadata: { from: current.status, to: dto.status }
    });

    return this.toDeletionRequestDto(result);
  }

  private async findActiveDeletionRequest(userId: string): Promise<DeletionRequestRow | undefined> {
    const result = await this.database.query<DeletionRequestRow>(
      `
        select id, user_id, status, reason, requested_at, resolved_at,
          resolved_by, resolution_note, updated_at
        from app.account_deletion_requests
        where user_id = $1
          and status in ('pending', 'processing')
        order by requested_at desc
        limit 1
      `,
      [userId]
    );
    return result.rows[0];
  }

  private async findLatestDeletionRequest(userId: string): Promise<DeletionRequestRow | undefined> {
    const result = await this.database.query<DeletionRequestRow>(
      `
        select id, user_id, status, reason, requested_at, resolved_at,
          resolved_by, resolution_note, updated_at
        from app.account_deletion_requests
        where user_id = $1
        order by requested_at desc
        limit 1
      `,
      [userId]
    );
    return result.rows[0];
  }

  private async requireDeletionRequest(id: string): Promise<DeletionRequestRow> {
    const result = await this.database.query<DeletionRequestRow>(
      `
        select id, user_id, status, reason, requested_at, resolved_at,
          resolved_by, resolution_note, updated_at
        from app.account_deletion_requests
        where id = $1
        limit 1
      `,
      [id]
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException('Запрос на удаление не найден.');
    return row;
  }

  private assertExactCurrentDocumentSet(currentIds: string[], acceptedIds: string[]): void {
    const current = new Set(currentIds);
    const accepted = new Set(acceptedIds);
    if (current.size !== accepted.size) {
      throw new BadRequestException('Нужно принять все актуальные документы.');
    }
    for (const id of current) {
      if (!accepted.has(id)) {
        throw new BadRequestException('Нужно принять все актуальные документы.');
      }
    }
  }

  private optionalHash(value?: string): string | null {
    const normalized = value?.trim();
    if (!normalized) return null;
    return createHash('sha256').update(normalized).digest('hex');
  }

  private toDocumentDto(row: LegalDocumentRow) {
    return {
      id: row.id,
      type: row.document_type,
      documentType: row.document_type,
      title: row.title,
      version: row.version,
      url: row.url,
      fileId: row.file_id,
      publishedAt: row.published_at
    };
  }

  private toDeletionRequestDto(row: DeletionRequestRow) {
    return {
      id: row.id,
      userId: row.user_id,
      userEmail: row.user_email,
      status: row.status,
      reason: row.reason,
      requestedAt: row.requested_at,
      resolvedAt: row.resolved_at,
      resolvedBy: row.resolved_by,
      resolutionNote: row.resolution_note,
      updatedAt: row.updated_at
    };
  }
}
