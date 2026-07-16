import { MANAGER_ADMIN_ROLES } from "./actor-context";

// Comma-separated quoted role literals, derived once from MANAGER_ADMIN_ROLES.
// These are hardcoded, non-user-supplied identifiers, so embedding them in SQL
// is safe — the caller still binds the role VALUE as a parameter.
const MANAGER_ADMIN_ROLES_SQL_LIST = MANAGER_ADMIN_ROLES.map(
  (role) => `'${role}'`,
).join(", ");

/**
 * SQL membership test that a role expression is one of the management roles
 * (manager/director/admin/system_admin). Previously this list was hand-copied
 * into ~8 CRM queries; centralising it here means adding/renaming a management
 * role touches MANAGER_ADMIN_ROLES only.
 *
 * @param roleExpr the SQL expression holding the role, e.g. "$1" or a bound
 *                 parameter placeholder. Cast to ::text is applied for you.
 */
export function managerAdminRolesSql(roleExpr: string): string {
  return `${roleExpr}::text in (${MANAGER_ADMIN_ROLES_SQL_LIST})`;
}
