import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { NotificationsPolicy } from './notifications.policy';

describe('NotificationsPolicy', () => {
  const policy = new NotificationsPolicy();

  it('allows only recipient to read notification', () => {
    expect(() =>
      policy.assertCanReadRecipient(
        { userId: 'user-a', role: 'client' },
        { notification_id: 'notification-a', user_id: 'user-a' }
      )
    ).not.toThrow();
    expect(() =>
      policy.assertCanReadRecipient(
        { userId: 'user-b', role: 'client' },
        { notification_id: 'notification-a', user_id: 'user-a' }
      )
    ).toThrow(NotFoundException);
  });

  it('allows only manager and admin to send admin notifications', () => {
    expect(() => policy.assertCanAdminSend({ userId: 'manager', role: 'manager' })).not.toThrow();
    expect(() => policy.assertCanAdminSend({ userId: 'admin', role: 'admin' })).not.toThrow();
    expect(() => policy.assertCanAdminSend({ userId: 'client', role: 'client' })).toThrow(
      ForbiddenException
    );
  });
});
