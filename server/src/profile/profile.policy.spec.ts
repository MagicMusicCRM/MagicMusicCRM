import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { ProfilePolicy } from './profile.policy';

describe('ProfilePolicy', () => {
  const policy = new ProfilePolicy();

  it('allows users to read their own profile', () => {
    expect(() =>
      policy.assertCanReadProfile({ userId: 'user-a', role: 'client' }, 'user-a')
    ).not.toThrow();
  });

  it('hides foreign profiles from clients', () => {
    expect(() =>
      policy.assertCanReadProfile({ userId: 'user-a', role: 'client' }, 'user-b')
    ).toThrow(NotFoundException);
  });

  it('allows managers to list profiles and update client or teacher roles only', () => {
    expect(() =>
      policy.assertCanListProfiles({ userId: 'manager-a', role: 'manager' })
    ).not.toThrow();
    expect(() =>
      policy.assertCanUpdateRole(
        { userId: 'manager-a', role: 'manager' },
        'client',
        'teacher'
      )
    ).not.toThrow();
    expect(() =>
      policy.assertCanUpdateRole(
        { userId: 'manager-a', role: 'manager' },
        'teacher',
        'client'
      )
    ).not.toThrow();
    expect(() =>
      policy.assertCanUpdateRole(
        { userId: 'manager-a', role: 'manager' },
        'client',
        'admin'
      )
    ).toThrow(ForbiddenException);
    expect(() =>
      policy.assertCanUpdateRole(
        { userId: 'manager-a', role: 'manager' },
        'admin',
        'manager'
      )
    ).toThrow(ForbiddenException);
    expect(() =>
      policy.assertCanUpdateRole(
        { userId: 'manager-a', role: 'manager' },
        'client',
        'system_admin'
      )
    ).toThrow(ForbiddenException);
  });

  it('allows admins and system admins to update roles', () => {
    expect(() =>
      policy.assertCanUpdateRole({ userId: 'admin-a', role: 'admin' })
    ).not.toThrow();
    expect(() =>
      policy.assertCanUpdateRole({ userId: 'system-a', role: 'system_admin' })
    ).not.toThrow();
  });
});
