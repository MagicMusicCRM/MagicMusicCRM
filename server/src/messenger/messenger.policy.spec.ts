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

  it('allows channel writes for explicit write permission', () => {
    expect(() =>
      policy.assertCanWriteChannel(
        { userId: 'teacher-a', role: 'teacher' },
        { id: 'channel-a', canRead: true, canWrite: true }
      )
    ).not.toThrow();
  });
});
