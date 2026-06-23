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

  it('is a no-op (never throws) when no server is registered', () => {
    const bus = new RealtimeBus();
    expect(() =>
      bus.emitCrmChanged({ entity: 'lead', action: 'deleted', id: 'x' })
    ).not.toThrow();
  });
});
