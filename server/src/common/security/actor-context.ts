export type UserRole =
  | 'client'
  | 'teacher'
  | 'manager'
  | 'admin'
  | 'system_admin';

export interface ActorContext {
  userId: string;
  role: UserRole;
}

export interface AuthenticatedRequest {
  user?: ActorContext;
}

export function isStaffRole(role: UserRole): boolean {
  return role === 'admin' || role === 'manager' || role === 'system_admin';
}

export function isAdminRole(role: UserRole): boolean {
  return role === 'admin' || role === 'system_admin';
}

export function isManagerOrAdminRole(role: UserRole): boolean {
  return role === 'manager' || isAdminRole(role);
}
