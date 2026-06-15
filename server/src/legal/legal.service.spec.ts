import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { DatabaseService } from '../db/database.service';
import { LegalPolicy } from './legal.policy';
import { LegalService } from './legal.service';

describe('LegalService', () => {
  const actor = { userId: '11111111-1111-4111-8111-111111111111', role: 'client' as const };
  const admin = { userId: '22222222-2222-4222-8222-222222222222', role: 'admin' as const };
  const docA = {
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    document_type: 'privacy_policy',
    version: '2026-06-11',
    title: 'Privacy',
    url: 'https://magicmusiccrm-legal.vercel.app/privacy/',
    file_id: null,
    published_at: new Date('2026-06-11T00:00:00Z')
  };
  const docB = {
    ...docA,
    id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    document_type: 'terms_of_use',
    title: 'Terms',
    url: 'https://magicmusiccrm-legal.vercel.app/terms/'
  };
  const deletionRequest = {
    id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    user_id: actor.userId,
    status: 'pending',
    reason: 'reason',
    requested_at: new Date('2026-06-11T00:00:00Z'),
    resolved_at: null,
    resolved_by: null,
    resolution_note: null,
    updated_at: new Date('2026-06-11T00:00:00Z')
  };

  function createService() {
    const database = {
      query: jest.fn(),
      transaction: jest.fn()
    } as unknown as jest.Mocked<Pick<DatabaseService, 'query' | 'transaction'>>;
    const audit = {
      record: jest.fn()
    } as unknown as jest.Mocked<Pick<AuditService, 'record'>>;
    const service = new LegalService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      new LegalPolicy()
    );
    return { service, database, audit };
  }

  it('returns false legal gate until all current docs are accepted', async () => {
    const { service, database } = createService();
    database.query.mockResolvedValueOnce({
      rows: [
        {
          current_count: '2',
          accepted_count: '1',
          deletion_pending: false,
          role: 'client',
          profile_complete: true
        }
      ]
    } as never);

    await expect(service.getGate(actor)).resolves.toEqual({
      role: 'client',
      profileComplete: true,
      legalAccepted: false,
      deletionPending: false
    });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [actor.userId, actor.role]);
  });

  it('treats missing legal documents as already accepted', async () => {
    const { service, database } = createService();
    database.query.mockResolvedValueOnce({
      rows: [
        {
          current_count: '0',
          accepted_count: '0',
          deletion_pending: false,
          role: 'client',
          profile_complete: true
        },
      ],
    } as never);

    await expect(service.getGate(actor)).resolves.toEqual({
      role: 'client',
      profileComplete: true,
      legalAccepted: true,
      deletionPending: false
    });
  });

  it('uses profile fields as a fallback when legacy profile_completed is false', async () => {
    const { service, database } = createService();
    database.query.mockResolvedValueOnce({
      rows: [
        {
          current_count: '1',
          accepted_count: '1',
          deletion_pending: false,
          role: 'client',
          profile_complete: true
        },
      ],
    } as never);

    await service.getGate(actor);

    const gateSql = database.query.mock.calls[0]?.[0] as string;
    expect(gateSql).toContain(
      'coalesce((select profile_completed from user_state), false)'
    );
    expect(gateSql).toContain('or coalesce');
  });

  it('rejects partial consent for current documents', async () => {
    const { service, database } = createService();
    database.query.mockResolvedValueOnce({ rows: [docA, docB] } as never);

    await expect(
      service.acceptCurrentDocuments(
        actor,
        { documentIds: [docA.id] },
        { ip: '127.0.0.1', userAgent: 'jest' }
      )
    ).rejects.toThrow(BadRequestException);
  });

  it('accepts the exact current document set and records audit without raw evidence', async () => {
    const { service, database, audit } = createService();
    database.query.mockResolvedValueOnce({ rows: [docA, docB] } as never);
    database.transaction.mockImplementationOnce(async (work) => {
      const client = { query: jest.fn().mockResolvedValue({ rows: [] }) };
      return work(client as never);
    });

    await expect(
      service.acceptCurrentDocuments(
        actor,
        { documentIds: [docB.id, docA.id] },
        { ip: '127.0.0.1', userAgent: 'jest-agent' }
      )
    ).resolves.toEqual({ accepted: true });

    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'legal.consents_accepted',
        metadata: { documentIds: [docA.id, docB.id] }
      })
    );
  });

  it('returns an existing active deletion request idempotently', async () => {
    const { service, database, audit } = createService();
    database.query.mockResolvedValueOnce({ rows: [deletionRequest] } as never);

    await expect(
      service.createDeletionRequest(actor, { acknowledgement: true, reason: 'new reason' })
    ).resolves.toMatchObject({
      id: deletionRequest.id,
      status: 'pending'
    });
    expect(audit.record).not.toHaveBeenCalled();
  });

  it('allows only admin to update deletion request lifecycle', async () => {
    const { service, database } = createService();
    database.query.mockResolvedValueOnce({ rows: [deletionRequest] } as never);

    await expect(
      service.updateDeletionRequest(
        { userId: 'manager-a', role: 'manager' },
        deletionRequest.id,
        { status: 'processing' }
      )
    ).rejects.toThrow(ForbiddenException);
  });

  it('updates deletion lifecycle and revokes user access on completion', async () => {
    const { service, database, audit } = createService();
    const processing = { ...deletionRequest, status: 'processing' };
    const completed = {
      ...processing,
      status: 'completed',
      resolved_at: new Date('2026-06-11T01:00:00Z'),
      resolved_by: admin.userId
    };
    database.query.mockResolvedValueOnce({ rows: [processing] } as never);
    database.transaction.mockImplementationOnce(async (work) => {
      const client = {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [completed] })
          .mockResolvedValue({ rows: [] })
      };
      return work(client as never);
    });

    await expect(
      service.updateDeletionRequest(admin, deletionRequest.id, {
        status: 'completed',
        resolutionNote: 'done'
      })
    ).resolves.toMatchObject({ id: deletionRequest.id, status: 'completed' });

    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'legal.deletion_status_updated',
        metadata: { from: 'processing', to: 'completed' }
      })
    );
  });
});
