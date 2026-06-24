import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../db/database.service';
import { MessengerPolicy } from './messenger.policy';

describe('MessengerPolicy', () => {
  let query: jest.Mock;
  let policy: MessengerPolicy;

  beforeEach(() => {
    query = jest.fn();
    policy = new MessengerPolicy({ query } as unknown as DatabaseService);
  });

  it('allows chat members to read their own chat', () => {
    expect(() =>
      policy.assertCanReadChat(
        { userId: 'client-a', role: 'client' },
        { id: 'chat-a', type: 'direct', memberUserId: 'client-a', memberRole: 'member' }
      )
    ).not.toThrow();
  });

  it('hides foreign direct chats from clients', () => {
    expect(() =>
      policy.assertCanReadChat(
        { userId: 'client-a', role: 'client' },
        { id: 'chat-b', type: 'direct', memberUserId: null, memberRole: null }
      )
    ).toThrow(NotFoundException);
  });

  it('allows staff to read administration queues without explicit membership', () => {
    expect(() =>
      policy.assertCanReadChat(
        { userId: 'manager-a', role: 'manager' },
        { id: 'chat-admin', type: 'administration', memberUserId: null, memberRole: null }
      )
    ).not.toThrow();
  });

  it('denies direct chats without teaching relationship for non-staff actors', async () => {
    query.mockResolvedValueOnce({ rows: [{ allowed: false }] });

    await expect(
      policy.canCreateDirectChat({ userId: 'client-a', role: 'client' }, 'teacher-a')
    ).rejects.toThrow(ForbiddenException);
  });

  it('forbids a client from creating any direct chat', async () => {
    await expect(policy.canCreateDirectChat({ userId: 'c', role: 'client' }, 'x'))
      .rejects.toThrow(ForbiddenException);
  });

  it('forbids a direct chat whose target is a client', async () => {
    query.mockResolvedValueOnce({ rows: [{ role: 'client' }] }); // target lookup
    await expect(policy.canCreateDirectChat({ userId: 't', role: 'teacher' }, 'client-x'))
      .rejects.toThrow(ForbiddenException);
  });

  it('allows a direct chat between two non-client staff/teachers', async () => {
    query.mockResolvedValueOnce({ rows: [{ role: 'admin' }] }); // target lookup
    await expect(policy.canCreateDirectChat({ userId: 't', role: 'teacher' }, 'admin-x'))
      .resolves.toBeUndefined();
  });

  it('allows channel writes for explicit write permission', () => {
    expect(() =>
      policy.assertCanWriteChannel(
        { userId: 'teacher-a', role: 'teacher' },
        { id: 'channel-a', canRead: true, canWrite: true }
      )
    ).not.toThrow();
  });

  it('authorizes a channel realtime room join when the actor can read it', async () => {
    query.mockResolvedValueOnce({
      rows: [{ id: 'channel-a', canRead: true, canWrite: false }]
    });

    await expect(
      policy.canJoinRealtimeRoom(
        { userId: 'client-a', role: 'client' },
        'channel',
        'channel-a'
      )
    ).resolves.toBeUndefined();
  });

  it('denies a channel realtime room join when the actor cannot read it', async () => {
    query.mockResolvedValueOnce({
      rows: [{ id: 'channel-a', canRead: false, canWrite: false }]
    });

    await expect(
      policy.canJoinRealtimeRoom(
        { userId: 'client-a', role: 'client' },
        'channel',
        'channel-a'
      )
    ).rejects.toThrow(NotFoundException);
  });

  it('rejects realtime room joins for unknown room types', async () => {
    await expect(
      policy.canJoinRealtimeRoom(
        { userId: 'client-a', role: 'client' },
        'bogus',
        'whatever'
      )
    ).rejects.toThrow(ForbiddenException);
  });

  it('hides the announcements composer from client/teacher (no channel write)', () => {
    for (const role of ['client', 'teacher'] as const) {
      expect(() =>
        policy.assertCanWriteChannel(
          { userId: 'u', role },
          { id: 'announcements', canRead: true, canWrite: false }
        )
      ).toThrow(ForbiddenException);
    }
  });

  it('allows admin/manager/system_admin to write the announcements channel', () => {
    for (const role of ['admin', 'manager', 'system_admin'] as const) {
      expect(() =>
        policy.assertCanWriteChannel(
          { userId: 'u', role },
          { id: 'announcements', canRead: true, canWrite: false }
        )
      ).not.toThrow();
    }
  });
});
