import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { ProfilePolicy } from './profile.policy';

describe('ProfilePolicy', () => {
  const policy = new ProfilePolicy();

  const sys = { userId: 'sys-a', role: 'system_admin' as const };
  const manager = { userId: 'mgr-a', role: 'manager' as const };
  const director = { userId: 'dir-a', role: 'director' as const };
  const admin = { userId: 'adm-a', role: 'admin' as const };
  const teacher = { userId: 'tch-a', role: 'teacher' as const };
  const client = { userId: 'cli-a', role: 'client' as const };

  it('allows users to read their own profile', () => {
    expect(() =>
      policy.assertCanReadProfile(client, 'cli-a')
    ).not.toThrow();
  });

  it('hides foreign profiles from clients', () => {
    expect(() =>
      policy.assertCanReadProfile(client, 'user-b')
    ).toThrow(NotFoundException);
  });

  it('allows operational staff to list profiles, forbids non-staff', () => {
    expect(() => policy.assertCanListProfiles(manager)).not.toThrow();
    expect(() => policy.assertCanListProfiles(admin)).not.toThrow();
    expect(() => policy.assertCanListProfiles(sys)).not.toThrow();
    expect(() => policy.assertCanListProfiles(teacher)).toThrow(ForbiddenException);
    expect(() => policy.assertCanListProfiles(client)).toThrow(ForbiddenException);
  });

  describe('assertCanUpdateRole — иерархия ролей (manager > admin)', () => {
    it('system_admin may assign any role, including system_admin', () => {
      for (const target of [
        'client',
        'teacher',
        'admin',
        'manager',
        'director',
        'system_admin',
      ] as const) {
        expect(() =>
          policy.assertCanUpdateRole(sys, 'client', target)
        ).not.toThrow();
      }
      // and may modify a user who already holds system_admin
      expect(() =>
        policy.assertCanUpdateRole(sys, 'system_admin', 'manager')
      ).not.toThrow();
    });

    it('manager may assign roles strictly below manager (client/teacher/admin)', () => {
      expect(() =>
        policy.assertCanUpdateRole(manager, 'client', 'teacher')
      ).not.toThrow();
      expect(() =>
        policy.assertCanUpdateRole(manager, 'client', 'admin')
      ).not.toThrow();
      expect(() =>
        policy.assertCanUpdateRole(manager, 'teacher', 'client')
      ).not.toThrow();
    });

    it('manager may NOT grant manager, director or system_admin', () => {
      expect(() =>
        policy.assertCanUpdateRole(manager, 'client', 'manager')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(manager, 'client', 'director')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(manager, 'client', 'system_admin')
      ).toThrow(ForbiddenException);
    });

    it('director may assign roles strictly below director (incl. manager)', () => {
      for (const target of ['client', 'teacher', 'admin', 'manager'] as const) {
        expect(() =>
          policy.assertCanUpdateRole(director, 'client', target)
        ).not.toThrow();
      }
    });

    it('director may NOT grant director or system_admin, nor modify them', () => {
      expect(() =>
        policy.assertCanUpdateRole(director, 'client', 'director')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(director, 'client', 'system_admin')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(director, 'director', 'manager')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(director, 'system_admin', 'client')
      ).toThrow(ForbiddenException);
    });

    it('manager may NOT modify a user who currently holds director', () => {
      expect(() =>
        policy.assertCanUpdateRole(manager, 'director', 'client')
      ).toThrow(ForbiddenException);
    });

    it('manager may NOT modify a user who currently holds manager or system_admin', () => {
      expect(() =>
        policy.assertCanUpdateRole(manager, 'manager', 'admin')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(manager, 'system_admin', 'teacher')
      ).toThrow(ForbiddenException);
    });

    it('admin may NOT manage roles at all (admin is below manager)', () => {
      expect(() =>
        policy.assertCanUpdateRole(admin, 'client', 'teacher')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(admin, 'client', 'admin')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(admin, 'client', 'system_admin')
      ).toThrow(ForbiddenException);
      // cannot promote itself to manager
      expect(() =>
        policy.assertCanUpdateRole(admin, 'admin', 'manager')
      ).toThrow(ForbiddenException);
    });

    it('clients and teachers may not update roles', () => {
      expect(() =>
        policy.assertCanUpdateRole(client, 'client', 'teacher')
      ).toThrow(ForbiddenException);
      expect(() =>
        policy.assertCanUpdateRole(teacher, 'client', 'admin')
      ).toThrow(ForbiddenException);
    });
  });
});
