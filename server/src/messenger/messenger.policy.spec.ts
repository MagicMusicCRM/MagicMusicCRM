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

  describe('assertCanAssign', () => {
    const unassignedChat = {
      id: 'chat-a', type: 'administration', memberUserId: null, memberRole: null,
      assignedToUserId: null
    };
    const chatAssignedToOther = {
      id: 'chat-a', type: 'administration', memberUserId: null, memberRole: null,
      assignedToUserId: 'staff-other'
    };
    const chatAssignedToSelf = {
      id: 'chat-a', type: 'administration', memberUserId: null, memberRole: null,
      assignedToUserId: 'manager-a'
    };

    it('allows manager-tier staff to mark a chat assigned to someone else', () => {
      expect(() =>
        policy.assertCanAssign(
          { userId: 'manager-a', role: 'manager' },
          chatAssignedToOther
        )
      ).not.toThrow();
    });

    it('allows admin staff to claim an unassigned chat', () => {
      expect(() =>
        policy.assertCanAssign(
          { userId: 'admin-a', role: 'admin' },
          unassignedChat
        )
      ).not.toThrow();
    });

    it('allows admin staff to refresh their own work marker', () => {
      expect(() =>
        policy.assertCanAssign(
          { userId: 'manager-a', role: 'admin' },
          chatAssignedToSelf
        )
      ).not.toThrow();
    });

    it('allows admin staff to continue work even when another staff member was marked', () => {
      expect(() =>
        policy.assertCanAssign(
          { userId: 'admin-a', role: 'admin' },
          chatAssignedToOther
        )
      ).not.toThrow();
    });

    it('forbids clients from marking chats as in work', () => {
      expect(() =>
        policy.assertCanAssign(
          { userId: 'client-a', role: 'client' },
          unassignedChat
        )
      ).toThrow(ForbiddenException);
    });
  });

  describe('чёрный список = бан на отправку', () => {
    // ✔ Решение владельца 17.07: «этот клиент не может писать далее в чатах
    // школы и админам — по сути бан».
    it('forbids a blacklisted client from sending', async () => {
      query.mockResolvedValue({ rows: [{ blacklisted: true }] });
      await expect(
        policy.assertNotBlacklisted({ userId: 'client-a', role: 'client' })
      ).rejects.toThrow(ForbiddenException);
    });

    it('lets an ordinary client send', async () => {
      query.mockResolvedValue({ rows: [{ blacklisted: false }] });
      await expect(
        policy.assertNotBlacklisted({ userId: 'client-a', role: 'client' })
      ).resolves.toBeUndefined();
    });

    it('does not ask about staff at all', async () => {
      // Чёрный список — свойство клиента. Отметка в карточке педагога — это
      // другое понятие и другой процесс; спрашивать про неё здесь значило бы
      // молча их склеить.
      await expect(
        policy.assertNotBlacklisted({ userId: 'manager-a', role: 'manager' })
      ).resolves.toBeUndefined();
      expect(query).not.toHaveBeenCalled();
    });

    it('tells the banned client why, instead of failing silently', async () => {
      query.mockResolvedValue({ rows: [{ blacklisted: true }] });
      await expect(
        policy.assertNotBlacklisted({ userId: 'client-a', role: 'client' })
      ).rejects.toThrow(/чёрном списке/i);
    });
  });
});
