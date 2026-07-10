export type UserRole =
  | 'client'
  | 'teacher'
  | 'manager'
  | 'admin'
  | 'director'
  | 'system_admin';

export interface ActorContext {
  userId: string;
  role: UserRole;
}

// JWT issuer/audience claims — set on sign, verified on every request, so a
// token minted for another service/environment (or with a reused secret) is
// rejected (KVA: "JWT не содержит/не проверяет iss/aud").
export const JWT_ISSUER = 'magicmusiccrm';
export const JWT_AUDIENCE = 'magicmusiccrm-app';

export interface AuthenticatedRequest {
  user?: ActorContext;
}

export function isStaffRole(role: UserRole): boolean {
  return (
    role === 'admin' ||
    role === 'manager' ||
    role === 'director' ||
    role === 'system_admin'
  );
}

export function isAdminRole(role: UserRole): boolean {
  return role === 'admin' || role === 'system_admin';
}

export function isManagerOrAdminRole(role: UserRole): boolean {
  return role === 'manager' || role === 'director' || isAdminRole(role);
}

// Иерархия ролей (бизнес-правило владельца): Управляющий (manager) ВЫШЕ
// Администратора (admin), Директор (director) ВЫШЕ Управляющего.
// client < teacher < admin < manager < director < system_admin.
export const ROLE_LEVEL: Record<UserRole, number> = {
  client: 0,
  teacher: 1,
  admin: 2,
  manager: 3,
  director: 4,
  system_admin: 5,
};

// Управляющий/Директор или Администратор системы (но НЕ Администратор).
export function isManagerRole(role: UserRole): boolean {
  return role === 'manager' || role === 'director' || role === 'system_admin';
}

/**
 * Может ли актор с ролью `actorRole` назначать/управлять ролью `targetRole`
 * (используется и для назначаемой новой роли, и для текущей роли цели).
 *
 * - system_admin: полный контроль (может назначить любую роль, включая
 *   system_admin); защита последнего system_admin реализована в сервисе.
 * - director (Директор): только роли СТРОГО НИЖЕ себя
 *   (client/teacher/admin/manager).
 * - manager (Управляющий): только роли СТРОГО НИЖЕ себя (client/teacher/admin);
 *   в частности НЕ может назначать director и system_admin.
 * - admin и ниже: НЕ управляют ролями вообще.
 */
export function canAssignRole(
  actorRole: UserRole,
  targetRole: UserRole
): boolean {
  if (actorRole === 'system_admin') return true;
  if (actorRole === 'manager' || actorRole === 'director') {
    return ROLE_LEVEL[targetRole] < ROLE_LEVEL[actorRole];
  }
  return false;
}
