import { PaymentLifecycleService } from './payment-lifecycle.service';
import { PaymentLifecycleRepository, PaymentRecordRow } from './payment-lifecycle.repository';
import { SubscriptionIssueRepository } from './subscription-issue.repository';
import { CrmPolicy } from '../crm.policy';
import { PlatformIntegrityService } from '../../platform/platform-integrity.service';
import { CommerceProjectionRepository } from './commerce-projection.repository';
import { SubscriptionReservationService } from './subscription-reservation.service';

describe('payment result consistency', () => {
  it('replays a command with the version of the returned state and excludes later history', async () => {
    const repository = {
      findRecord: jest.fn().mockResolvedValue({
        id: 'record', student_id: 'student', amount_minor: '12345', currency_code: 'RUB',
        status: 'posted_pending', version: 3, actual_payment_id: null,
      } as PaymentRecordRow),
      // Another command commits after findRecord but before the history read.
      listStatusEvents: jest.fn().mockResolvedValue([1, 2, 3, 4].map(version => ({
        id: `event-${version}`, aggregate_version: version, after_status: 'posted_pending',
      }))),
    };
    const integrity = { executeVersionedMutation: jest.fn().mockResolvedValue({
      resultRef: { entityId: 'record', version: 1 }, version: 1, replayed: true,
    }) };
    const reservations = { publishPostCommit: jest.fn() };
    const service = new PaymentLifecycleService(
      repository as unknown as PaymentLifecycleRepository, {} as SubscriptionIssueRepository,
      new CrmPolicy(), integrity as unknown as PlatformIntegrityService,
      { resolveStudentScope: async () => ({ branchId: 'branch' }) } as unknown as CommerceProjectionRepository,
      reservations as unknown as SubscriptionReservationService,
    );
    const result = await service.create({ userId: 'actor', role: 'director' }, 'student', {
      amountMinor: '12345', currencyCode: 'RUB', status: 'posted_pending', reason: 'Повтор запроса',
    }, { idempotencyKey: 'same-command-key', requestId: 'same-request' });
    expect(result.paymentRecord.version).toBe(3);
    expect(result.statusHistory.map(event => event.version)).toEqual([1, 2, 3]);
    expect(reservations.publishPostCommit).not.toHaveBeenCalled();
  });
});
