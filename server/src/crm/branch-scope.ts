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
 * Pull a valid branch UUID out of a customDataPatch (`branchId` or `branch_id`),
 * for dual-writing the real column alongside the legacy json.
 */
export function extractBranchId(
  patch: Record<string, unknown> | undefined | null,
): string | null {
  const raw = patch?.["branchId"] ?? patch?.["branch_id"];
  return typeof raw === "string" && UUID_RE.test(raw) ? raw : null;
}
