/**
 * Branch-scoping helpers shared across CRM/analytics (B4 BranchScope). Pure
 * functions — no state, no DI. A CRM entity's effective branch is the real
 * `branch_id` column when set, else the legacy `custom_data->>'branchId'` /
 * `branch_id` json fallback (dual-write migration is still in flight).
 */

const UUID_RE =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/** SQL expression for an aliased row's effective branch id (column ?? json). */
export function branchIdExpr(alias: string): string {
  return `coalesce(${alias}.branch_id::text, ${alias}.custom_data->>'branchId', ${alias}.custom_data->>'branch_id')`;
}

/**
 * SQL predicate that keeps delegated Managers inside their assigned branches.
 * Other operational roles remain governed by their capability checks. Keeping
 * this expression shared prevents collection searches and direct mutations
 * from drifting into different branch-scope rules.
 */
export function managerBranchScopeSql(input: {
  roleExpression: string;
  userIdExpression: string;
  branchExpression: string;
}): string {
  return `(
    ${input.roleExpression}::text <> 'manager'
    or exists (
      select 1
      from app.user_crm_links scope_link
      join app.staff_members scope_staff
        on scope_staff.id = scope_link.entity_id
       and scope_link.entity_type = 'staff'
       and scope_link.deleted_at is null
       and scope_staff.deleted_at is null
      join app.staff_branch_assignments scope_assignment
        on scope_assignment.staff_member_id = scope_staff.id
       and scope_assignment.deleted_at is null
      where scope_link.user_id = ${input.userIdExpression}::uuid
        and scope_assignment.branch_id::text = ${input.branchExpression}
    )
  )`;
}

/**
 * Pull a valid branch UUID out of a customDataPatch (`branchId` or `branch_id`),
 * for dual-writing the real column alongside the legacy json.
 */
export function extractBranchId(
  patch: Record<string, unknown> | undefined | null,
): string | null {
  const raw = patch?.["branchId"] ?? patch?.["branch_id"];
  return typeof raw === "string" && UUID_RE.test(raw) ? raw : null;
}
