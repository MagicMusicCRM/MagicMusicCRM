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

  it('allows managers to assign operational roles up to manager, but not admin tiers', () => {
    expect(() =>
      policy.assertCanListProfiles({ userId: 'manager-a', role: 'manager' })
    ).not.toThrow();
    // May assign client / teacher / manager (the top operational role).
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
        'manager'
      )
    ).not.toThrow();
    expect(() =>
      policy.assertCanUpdateRole(
        { userId: 'manager-a', role: 'manager' },
        'manager',
        'teacher'
      )
    ).not.toThrow();
    // Must NOT grant admin-tier roles (privilege escalation above own tier).
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
        'client',
        'system_admin'
      )
    ).toThrow(ForbiddenException);
    // Must NOT modify users who already hold an admin-tier role.
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
        'system_admin',
        'teacher'
      )
    ).toThrow(ForbiddenException);
  });

  it('forbids clients and teachers from updating roles', () => {
    expect(() =>
      policy.assertCanUpdateRole(
        { userId: 'client-a', role: 'client' },
        'client',
        'teacher'
      )
    ).toThrow(ForbiddenException);
    expect(() =>
      policy.assertCanUpdateRole(
        { userId: 'teacher-a', role: 'teacher' },
        'client',
        'manager'
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
