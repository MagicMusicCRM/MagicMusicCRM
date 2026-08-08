import { PlatformOutboxWorker } from './platform-outbox.worker';

describe('PlatformOutboxWorker', () => {
  it('publishes known invalidations and retries unknown events', async () => {
    const events = [
      {
        eventId: 'event-subscription',
        type: 'commerce.subscription.changed',
        occurredAt: new Date(),
        aggregateType: 'commerce:issued-subscription',
        aggregateId: 'subscription-a',
        aggregateVersion: 2,
        requestId: 'request-a',
        payload: { entityId: 'subscription-a' },
        attempts: 1
      },
      {
        eventId: 'event-access',
        type: 'access.invalidated',
        occurredAt: new Date(),
        aggregateType: 'access:user',
        aggregateId: 'user-a',
        aggregateVersion: 7,
        requestId: 'request-b',
        payload: { entityId: 'user-a' },
        attempts: 1
      },
      {
        eventId: 'event-unknown',
        type: 'unknown.changed',
        occurredAt: new Date(),
        aggregateType: 'unknown',
        aggregateId: 'unknown-a',
        aggregateVersion: 1,
        requestId: 'request-c',
        payload: {},
        attempts: 1
      }
    ];
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue(events),
      markOutboxPublished: jest.fn().mockResolvedValue(true),
      markOutboxFailed: jest.fn().mockResolvedValue('retry')
    };
    const realtime = {
      isReady: jest.fn().mockReturnValue(true),
      emitFinanceChanged: jest.fn(),
      emitCrmChanged: jest.fn(),
      emitUserAccessInvalidated: jest.fn(),
      emitRoleAccessInvalidated: jest.fn()
    };
    const worker = new PlatformOutboxWorker(integrity as never, realtime as never);

    await expect(worker.runOnce('worker-a')).resolves.toEqual({
      claimed: 3,
      published: 2,
      retry: 1,
      deadLetter: 0
    });
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith([]);
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith(expect.objectContaining({
      entity: 'subscription',
      action: 'updated',
      id: 'subscription-a'
    }));
    expect(realtime.emitUserAccessInvalidated).toHaveBeenCalledWith('user-a', 7);
    expect(integrity.markOutboxPublished).toHaveBeenCalledTimes(2);
    expect(integrity.markOutboxFailed).toHaveBeenCalledWith(
      events[2],
      'worker-a',
      expect.any(Error)
    );
  });

  it('keeps an event pending until realtime is ready', async () => {
    const event = {
      eventId: 'event-task',
      type: 'workflow.task.changed',
      occurredAt: new Date(),
      aggregateType: 'workflow:task',
      aggregateId: 'task-a',
      aggregateVersion: 1,
      requestId: 'request-a',
      payload: {},
      attempts: 1
    };
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue([event]),
      markOutboxPublished: jest.fn(),
      markOutboxFailed: jest.fn().mockResolvedValue('retry')
    };
    const worker = new PlatformOutboxWorker(integrity as never, {
      isReady: () => false
    } as never);

    await expect(worker.runOnce('worker-a')).resolves.toMatchObject({
      published: 0,
      retry: 1
    });
    expect(integrity.markOutboxPublished).not.toHaveBeenCalled();
  });
});
