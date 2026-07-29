import type { Server } from 'socket.io';
import { RealtimeBus } from './realtime-bus';

describe('RealtimeBus', () => {
  it('broadcasts crm.changed to the shared CRM room', () => {
    const emit = jest.fn();
    const to = jest.fn(() => ({ emit }));
    const bus = new RealtimeBus();
    bus.setServer({ to } as unknown as Server);

    bus.emitCrmChanged({ entity: 'lesson', action: 'created', id: 'l1' });

    expect(to).toHaveBeenCalledWith('crm');
    expect(emit).toHaveBeenCalledWith('crm.changed', {
      entity: 'lesson',
      action: 'created',
      id: 'l1'
    });
  });

  it('broadcasts an opaque finance hint to staff and client rooms only', () => {
    const emit = jest.fn();
    const to = jest.fn((_room: string) => ({ emit }));
    const bus = new RealtimeBus();
    bus.setServer({ to } as unknown as Server);

    bus.emitFinanceChanged(['client-a', 'client-a', 'client-b', '']);

    expect(to.mock.calls.map(([room]) => room)).toEqual([
      RealtimeBus.financeRoom,
      'user:client-a',
      'user:client-b'
    ]);
    expect(to).not.toHaveBeenCalledWith('user:teacher-a');
    expect(emit).toHaveBeenCalledTimes(3);
    for (const call of emit.mock.calls) {
      expect(call).toEqual([
        'finance.changed',
        { scope: 'client-finance' }
      ]);
      expect(Object.keys(call[1])).toEqual(['scope']);
    }
  });

  it('is a no-op (never throws) when no server is registered', () => {
    const bus = new RealtimeBus();
    expect(() =>
      bus.emitCrmChanged({ entity: 'lead', action: 'deleted', id: 'x' })
    ).not.toThrow();
  });

  it('publishes safe user-scoped and global package invalidation', () => {
    const roomEmit = jest.fn();
    const broadcastEmit = jest.fn();
    const to = jest.fn(() => ({ emit: roomEmit }));
    const bus = new RealtimeBus();
    bus.setServer({ to, emit: broadcastEmit } as unknown as Server);

    bus.emitUserAccessInvalidated('user-a', 2);
    bus.emitRoleAccessInvalidated('manager', 3);

    expect(to).toHaveBeenCalledWith('user:user-a');
    expect(roomEmit).toHaveBeenCalledWith('access.invalidated', {
      accessVersion: 2,
      scope: 'user'
    });
    expect(broadcastEmit).toHaveBeenCalledWith('access.invalidated', {
      accessVersion: 3,
      scope: 'role'
    });
  });
});
