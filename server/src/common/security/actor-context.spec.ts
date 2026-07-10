import {
  canAssignRole,
  isManagerOrAdminRole,
  isManagerRole,
  isStaffRole,
  ROLE_LEVEL,
  UserRole,
} from './actor-context';

// KVA-239: client < teacher < admin < manager < director < system_admin.
describe('ROLE_LEVEL — иерархия ролей', () => {
  it('orders roles per owner rule (manager > admin, director > manager)', () => {
    expect(ROLE_LEVEL.client).toBeLessThan(ROLE_LEVEL.teacher);
    expect(ROLE_LEVEL.teacher).toBeLessThan(ROLE_LEVEL.admin);
    expect(ROLE_LEVEL.admin).toBeLessThan(ROLE_LEVEL.manager);
    expect(ROLE_LEVEL.manager).toBeLessThan(ROLE_LEVEL.director);
    expect(ROLE_LEVEL.director).toBeLessThan(ROLE_LEVEL.system_admin);
  });
});

describe('canAssignRole', () => {
  const all: UserRole[] = [
    'client',
    'teacher',
    'admin',
    'manager',
    'director',
    'system_admin',
  ];

  it('system_admin may assign every role', () => {
    for (const target of all) {
      expect(canAssignRole('system_admin', target)).toBe(true);
    }
  });

  it('director assigns strictly below director (incl. manager)', () => {
    expect(canAssignRole('director', 'client')).toBe(true);
    expect(canAssignRole('director', 'teacher')).toBe(true);
    expect(canAssignRole('director', 'admin')).toBe(true);
    expect(canAssignRole('director', 'manager')).toBe(true);
    expect(canAssignRole('director', 'director')).toBe(false);
    expect(canAssignRole('director', 'system_admin')).toBe(false);
  });

  it('manager assigns strictly below manager (NOT director/system_admin)', () => {
    expect(canAssignRole('manager', 'client')).toBe(true);
    expect(canAssignRole('manager', 'teacher')).toBe(true);
    expect(canAssignRole('manager', 'admin')).toBe(true);
    expect(canAssignRole('manager', 'manager')).toBe(false);
    expect(canAssignRole('manager', 'director')).toBe(false);
    expect(canAssignRole('manager', 'system_admin')).toBe(false);
  });

  it('admin and below assign nothing', () => {
    for (const actor of ['admin', 'teacher', 'client'] as const) {
      for (const target of all) {
        expect(canAssignRole(actor, target)).toBe(false);
      }
    }
  });
});

describe('staff predicates include director', () => {
  it('director is staff / manager-tier / manager-or-admin', () => {
    expect(isStaffRole('director')).toBe(true);
    expect(isManagerRole('director')).toBe(true);
    expect(isManagerOrAdminRole('director')).toBe(true);
  });
});
